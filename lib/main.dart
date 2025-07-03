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
import 'providers/location_provider.dart';
import 'map/providers/map_data_provider.dart';
import 'providers/ride_request_provider.dart';
import 'services/auth_service.dart';
import 'providers/driver_provider.dart';
import 'services/firestore_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'localization/locales.dart';

@pragma('vm:entry-point') // Required for release mode on Android
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize services for the background isolate
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FlutterLocalization.instance.ensureInitialized();

  // Initialize localization for the background isolate as well.
  // This is crucial because the background handler runs in a separate context.
  final FlutterLocalization localization = FlutterLocalization.instance;
  localization.init(
    mapLocales: [
      const MapLocale('en', AppLocale.EN),
      const MapLocale('sw', AppLocale.SW),
    ],
    initLanguageCode: 'en', // Use a default language for background tasks
  );

  debugPrint("Handling a background message: ${message.messageId}");
  debugPrint('Message data: ${message.data}');
  // You can perform background tasks here, or save data to be picked up when the app opens.
  // For example, you can save the message to Firestore or local storage.
  // If you want to show a notification, you can use flutter_local_notifications or similar package.
  // Make sure to handle the notification in a way that is appropriate for your app.
  // For example, if you want to show a local notification:
  // final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  // const AndroidInitializationSettings initializationSettingsAndroid =
  //     AndroidInitializationSettings('@mipmap/ic_launcher');
  // const InitializationSettings initializationSettings = InitializationSettings(
  //   android: initializationSettingsAndroid,
  // );
  // await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  // await flutterLocalNotificationsPlugin.show(
  //   0,
  //   message.notification?.title,
  //   message.notification?.body,
  //   NotificationDetails(
  //     android: AndroidNotificationDetails(
  //       'your_channel_id',
  //       'your_channel_name',
  //       channelDescription: 'your_channel_description',
  //       importance: Importance.max,
  //       priority: Priority.high,
  //       showWhen: false,
  //     ),
  //   ),
  // );
  // Note: Make sure to handle the notification in a way that is appropriate for your app.
  // You cannot update UI directly from here.
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
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
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
}