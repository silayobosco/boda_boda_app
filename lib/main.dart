import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Keep for StreamBuilder
import 'package:provider/provider.dart'; // Import provider
import 'theme/app_theme.dart'; // Import AppThemes and ThemeProvider
import 'screens/additional_info_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'firebase_options.dart'; 
import 'providers/notification_provider.dart';
import 'providers/location_provider.dart';
import 'map/providers/map_data_provider.dart';
import 'providers/ride_request_provider.dart';
import 'services/auth_service.dart';
import 'providers/driver_provider.dart';
import 'services/firestore_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'localization/locales.dart';
import 'screens/chat_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

@pragma('vm:entry-point') // Required for release mode on Android
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize services for the background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint("Handling a background message: ${message.messageId}");
  debugPrint('Message data: ${message.data}');

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Setup for showing the notification. The channel ID must match the one used in NotificationProvider.
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'your_channel_id',
    'Your Channel Name',
    channelDescription: 'Your channel description',
    importance: Importance.max,
    priority: Priority.high,
    showWhen: true,
  );
  const NotificationDetails platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  // Show the notification
  await flutterLocalNotificationsPlugin.show(
    message.hashCode,
    message.notification?.title,
    message.notification?.body,
    platformChannelSpecifics,
    payload: jsonEncode(message.data), // Pass the data payload for tap handling
  );
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FlutterLocalization.instance.ensureInitialized();
  //await FirebaseAppCheck.instance.activate(
    // For Android, use Play Integrity
    //androidProvider: AndroidProvider.playIntegrity,
    // For iOS, use App Attest or Device Check
    //appleProvider: AppleProvider.appAttest,
  //);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(
  MultiProvider(
    providers: [
      // By creating the ThemeProvider here and calling loadThemeMode,
      // the theme is loaded correctly for the entire app.
      ChangeNotifierProvider(create: (_) => ThemeProvider()..loadThemeMode()),
      ChangeNotifierProvider(create: (_) => LocationProvider()),
      ChangeNotifierProvider(create: (_) => MapDataProvider()),
      ChangeNotifierProvider(create: (_) => DriverProvider()),
      ChangeNotifierProvider(
          create: (context) => NotificationProvider( // Use context.read for consistency
              authService: context.read<AuthService>(),
              firestoreService: context.read<FirestoreService>(),
          )),
      // Instantiate services directly in the provider list to avoid global variables.
      Provider<AuthService>(create: (_) => AuthService()),
      Provider<FirestoreService>(create: (_) => FirestoreService()),
      // RideRequestProvider depends on FirestoreService, so it uses `context.read`.
      ChangeNotifierProvider<RideRequestProvider>(
        create: (context) => RideRequestProvider(
          firestoreService: context.read<FirestoreService>(),
        )
      ),
    ],
    child: const MyApp(),
  ),
);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FlutterLocalization localization = FlutterLocalization.instance;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    localization.init(
      mapLocales: [
        const MapLocale('en', AppLocale.EN),
        const MapLocale('sw', AppLocale.SW),
      ],
      initLanguageCode: 'en',
    );
    localization.onTranslatedLanguage = (locale) {
      setState(() {});
    };

    // Initialize notifications after the first frame to ensure context is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeNotifications();
    });

    super.initState();
  }

  void _initializeNotifications() {
    if (!mounted) return;
    final notificationProvider = Provider.of<NotificationProvider>(context, listen: false);
    notificationProvider.initialize(
      onNotificationTap: _handleNotificationTap,
      onForegroundMessageReceived: _handleForegroundMessage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          supportedLocales: localization.supportedLocales,
          localizationsDelegates: localization.localizationsDelegates,
          debugShowCheckedModeBanner: false,
          title: 'Boda Boda App',
          theme: AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          themeMode: themeProvider.themeMode,
          home: StreamBuilder(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return const HomeScreen(); // User is logged in
              } else {
                return const LoginScreen(); // User is logged out
             }
           },
          ),
          routes: {
            '/login': (context) => const LoginScreen(),
            '/register': (context) => const RegisterScreen(),
            '/home': (context) => const HomeScreen(),
            '/settings': (context) => SettingsScreen(),
            '/additional_info': (context) {
              final user = ModalRoute.of(context)!.settings.arguments as User;
              return AdditionalInfoScreen(userUid: user.uid);
            },
          },
        );
      },
    );
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint("Foreground message received in UI: ${message.notification?.title}");
    // This is a great place to show an in-app banner or update a badge count.
    // For now, we'll just log it. The local notification is already shown by the provider.
  }

  /// Handles navigation when a notification is tapped.
  void _handleNotificationTap(Map<String, dynamic> data) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      debugPrint("Navigator key is null, cannot handle notification tap.");
      return;
    }

    final String? type = data['type'] as String?;
    debugPrint("Handling notification tap with data: $data");

    if (type == 'chat_message') {
      final String? rideRequestId = data['rideRequestId'] as String?;
      // The sender of the notification is the person you will be replying to.
      final String? recipientId = data['senderId'] as String?;
      final String? recipientName = data['senderName'] as String?;

      if (rideRequestId != null && recipientId != null) {
        navigator.push(MaterialPageRoute(
          builder: (context) => ChatScreen(
            rideRequestId: rideRequestId,
            recipientId: recipientId,
            recipientName: recipientName ?? "Chat",
          ),
        ));
      }
    } else {
      // For any other notification type (new_ride_request, ride_cancelled, etc.),
      // navigate to the main home screen. This ensures the app is in a known state.
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    }
  }
}