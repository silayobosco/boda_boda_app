import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Example for local notifications
import '../utils/notification_localization_util.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart'; // Import AuthService

class NotificationProvider with ChangeNotifier {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirestoreService _firestoreService;
  final AuthService _authService; // Add AuthService dependency
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Callbacks will be set during initialization
  late Function(RemoteMessage message) _onForegroundMessageReceived;
  late Function(Map<String, dynamic> data) _onNotificationTap;

  bool _isFcmInitialized = false; // Flag to ensure FCM setup runs once

  NotificationProvider({
    required AuthService authService,
    required FirestoreService firestoreService,
  }) : _authService = authService,
       _firestoreService = firestoreService {
    _initializeLocalNotifications(); // Initialize local notifications immediately
  }

  Future<void> initialize({
    required Function(RemoteMessage message) onForegroundMessageReceived,
    required Function(Map<String, dynamic> data) onNotificationTap,
  }) async {
    if (_isFcmInitialized) {
      debugPrint("NotificationProvider: FCM already initialized. Verifying permissions.");
      await checkAndRequestNotificationPermissions();
      return;
    }
    debugPrint("NotificationProvider: Initializing FCM setup...");

    // Request notification permissions first
    await checkAndRequestNotificationPermissions();

    // Store the callbacks
    _onForegroundMessageReceived = onForegroundMessageReceived;
    _onNotificationTap = onNotificationTap;

    // Then proceed with token and listeners
    await _getAndSaveDeviceToken();
    _setupForegroundNotifications();
    _listenForTokenRefresh();
    _setupInteractionHandlers(); // For taps on notifications
    _isFcmInitialized = true; // Mark FCM setup as complete
    debugPrint("NotificationProvider: FCM setup completed.");
  }

  bool get isFcmSetupComplete => _isFcmInitialized;

    Future<bool> checkAndRequestNotificationPermissions() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    debugPrint('NotificationProvider: User granted notification permission status: ${settings.authorizationStatus}');
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
           settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<void> _getAndSaveDeviceToken() async {
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _authService.saveFCMTokenToFirestore(token); // Use AuthService to save token
      }
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
     if (userId != null) {
       await _authService.saveFCMTokenToFirestore(token); // Use AuthService
    }
  }

  void _listenForTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      debugPrint('FCM Token refreshed: $newToken');
      _saveTokenToFirestore(newToken);
    });
  }

  void _setupForegroundNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('NotificationProvider: Foreground FCM message received!');
      // Show the local notification first
      if (message.notification != null) { // Only show if there's a notification part
        _showLocalNotification(message);
      }
      // If it's a chat message and the user is not on the chat screen for this ride,
      // NotificationProvider could show a generic local notification here.
      // However, the current setup relies on the onForegroundMessageReceived callback
      // in HomeScreen to decide on further actions or UI updates based on the message type
      // and app state (e.g., current screen).

      _onForegroundMessageReceived(message); // Then call the UI callback for other actions
      }
    );
  }

  void _setupInteractionHandlers() {
    // When the app is opened from a background state (not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Message opened from background: ${message.messageId}');
      _onNotificationTap(message.data); // Use the callback
      // Example of how onNotificationTap might be used in HomeScreen:
      // if (message.data['type'] == 'chat_message') {
      //   final rideRequestId = message.data['rideRequestId'];
      //   // Navigate to ChatScreen(rideRequestId: rideRequestId, ...);
      // }
    });

    // When the app is opened from a terminated state
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('Message opened from terminated state: ${message.messageId}');
        // Example of how onNotificationTap might be used in HomeScreen:
        // if (message.data['type'] == 'chat_message') { ... }

      _onNotificationTap(message.data); // Use the callback
      }
    });
  }

  Future<void> _initializeLocalNotifications() async {
    // Example initialization for flutter_local_notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher'); // Replace with your app icon
    // Add iOS and macOS initialization if needed
    // const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings();
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      // iOS: initializationSettingsIOS,
    );
    await _localNotificationsPlugin.initialize(initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) async {
        // This handles taps on the main notification body when the app is in the foreground.
        debugPrint('Local notification tapped with payload: ${notificationResponse.payload}');
        if (notificationResponse.payload != null && notificationResponse.payload!.isNotEmpty) {
          try {
            final Map<String, dynamic> data = jsonDecode(notificationResponse.payload!);
            _onNotificationTap(data); // Use the main handler to navigate
          } catch (e) {
            debugPrint('Error decoding notification payload: $e');
          }
        }
      },
      // This callback is needed for Android to handle background actions like "Reply"
      onDidReceiveBackgroundNotificationResponse: onDidReceiveBackgroundNotificationResponse,
    );
  }

  // This function needs to be a top-level function or a static method to be used as a callback for background execution.
  @pragma('vm:entry-point')
  static void onDidReceiveBackgroundNotificationResponse(NotificationResponse notificationResponse) {
    // This is called when a notification action (like 'Reply') is tapped while the app is in the background or terminated.
    // IMPORTANT: This runs in a separate isolate. You cannot update UI or use providers from the main app here.
    // You would need to re-initialize services like Firebase to send a message.
    debugPrint('Background notification action tapped: actionId=${notificationResponse.actionId}, input=${notificationResponse.input}');

    // Here you would implement the logic to send the reply.
    // This is a complex task involving background processing.
    // For now, we just log the action.
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final String type = message.data['type'] ?? '';
    List<AndroidNotificationAction> actions = [];

    // Add a "Reply" action for chat messages
    if (type == 'chat_message') {
      // Localize action button text
      final replyActionText = await NotificationLocalizationUtil.getLocalizedText('notification_action_reply');
      final replyInputLabel = await NotificationLocalizationUtil.getLocalizedText('notification_input_label_reply');
      actions.add(AndroidNotificationAction('reply_action', replyActionText, inputs: [AndroidNotificationActionInput(label: replyInputLabel)]));
    }

    // --- NEW: Handle localization for foreground notifications ---
    // Use appName from locales as a fallback title
    String notificationTitle = message.notification?.title ?? await NotificationLocalizationUtil.getLocalizedText('appName');
    String notificationBody = message.notification?.body ?? '';

    // If localization keys are present, use the utility to translate them.
    // This ensures consistency with the background handler.
    if (message.data.containsKey('title_loc_key')) {
      notificationTitle = await NotificationLocalizationUtil.getLocalizedTitle(message.data); // This uses getLocalizedText internally
    }
    if (message.data.containsKey('body_loc_key')) {
      notificationBody = await NotificationLocalizationUtil.getLocalizedBody(message.data); // This uses getLocalizedText internally
    }
    // --- END NEW ---

    // Localize channel details
    final channelName = await NotificationLocalizationUtil.getLocalizedText('notification_channel_name');
    final channelDescription = await NotificationLocalizationUtil.getLocalizedText('notification_channel_description');

    final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'your_channel_id', //  unique channel ID
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      actions: actions,
    );
    // Add iOS details if needed
    // const DarwinNotificationDetails iOSPlatformChannelSpecifics = DarwinNotificationDetails();
    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics /*, iOS: iOSPlatformChannelSpecifics*/);

    await _localNotificationsPlugin.show(
      message.hashCode, // Unique ID for the notification
      notificationTitle,
      notificationBody,
      platformChannelSpecifics,
      // Encode the data map as a JSON string for easy parsing on tap.
      payload: jsonEncode(message.data),
    );
  }
}