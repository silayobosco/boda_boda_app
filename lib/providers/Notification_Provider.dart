 import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Example for local notifications
import '../services/firestore_service.dart';
import '../services/auth_service.dart'; // Import AuthService

class NotificationProvider {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirestoreService _firestoreService;
  final AuthService _authService; // Add AuthService dependency
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Callbacks to interact with the UI layer (e.g., HomeScreen)
  final Function(RemoteMessage message) onForegroundMessageReceived;
  final Function(Map<String, dynamic> data) onNotificationTap;

  bool _isFcmInitialized = false; // Flag to ensure FCM setup runs once

  NotificationProvider({
    required AuthService authService,
    required FirestoreService firestoreService,
    required this.onForegroundMessageReceived,
    required this.onNotificationTap,
  }) : _authService = authService,
       _firestoreService = firestoreService {
    _initializeLocalNotifications(); // Initialize local notifications immediately
  }

  Future<void> initialize() async {
    // This method now focuses on FCM related setup and permissions
    // Local notifications are initialized in the constructor.
    if (_isFcmInitialized) {
      debugPrint("NotificationProvider: FCM already initialized. Verifying permissions.");
      // Even if initialized, it's good to check notification permissions
      // as they can be changed by the user in system settings.
      await checkAndRequestNotificationPermissions();
      return;
    }
    debugPrint("NotificationProvider: Initializing FCM setup...");

    // Request notification permissions first
    await checkAndRequestNotificationPermissions();

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

      onForegroundMessageReceived(message); // Then call the UI callback for other actions
      }
    );
  }

  void _setupInteractionHandlers() {
    // When the app is opened from a background state (not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Message opened from background: ${message.messageId}');
      onNotificationTap(message.data); // Use the callback
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

      onNotificationTap(message.data); // Use the callback
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
        // Handle tap on local notification
        debugPrint('Local notification tapped: ${notificationResponse.payload}');
        // You might want to parse the payload and navigate
      }
    );
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    // Example using flutter_local_notifications
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'your_channel_id', //  unique channel ID
      'Your Channel Name', // channel name
      channelDescription: 'Your channel description', // channel description
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
      // sound: RawResourceAndroidNotificationSound('custom_sound'), // if you have a custom sound
    );
    // Add iOS details if needed
    // const DarwinNotificationDetails iOSPlatformChannelSpecifics = DarwinNotificationDetails();
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics /*, iOS: iOSPlatformChannelSpecifics*/);

    await _localNotificationsPlugin.show(
      message.hashCode, // Unique ID for the notification
      message.notification?.title,
      message.notification?.body,
      platformChannelSpecifics,
      payload: message.data.toString(), // Optional: pass data to be used when notification is tapped
    );
  }
}