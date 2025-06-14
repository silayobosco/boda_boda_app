import 'package:firebase_messaging/firebase_messaging.dart';
//import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // Import provider
import 'theme/app_theme.dart'; // Import AppThemes and ThemeProvider
import 'screens/additional_info_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/customer_home.dart';
import 'screens/driver_home.dart';
import 'screens/admin_home.dart';
import 'screens/settings_screen.dart';
import 'firebase_options.dart'; 
import 'providers/location_provider.dart';
import 'map/providers/map_data_provider.dart';
import 'providers/ride_request_provider.dart';
import 'services/auth_service.dart';
import 'providers/driver_provider.dart';
import 'services/firestore_service.dart';

final FirestoreService firestoreService = FirestoreService();
final AuthService authService = AuthService();

@pragma('vm:entry-point') // Required for release mode on Android
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(); // Ensure Firebase is initialized
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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  //await FirebaseAppCheck.instance.activate(
    // For Android, use Play Integrity
    //androidProvider: AndroidProvider.playIntegrity,
    // For iOS, use App Attest or Device Check
    //appleProvider: AppleProvider.appAttest,
  //);
  final themeProvider = ThemeProvider();
  await themeProvider.loadThemeMode();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(
  MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ChangeNotifierProvider(create: (_) => LocationProvider()),
      ChangeNotifierProvider(create: (_) => MapDataProvider()),
      ChangeNotifierProvider(create: (_) => DriverProvider()),
      Provider<AuthService>(create: (_) => authService),
        Provider<FirestoreService>(create: (_) => firestoreService),
        ChangeNotifierProvider<RideRequestProvider>(
          create: (context) => RideRequestProvider(
            firestoreService: context.read<FirestoreService>(),
            // authService: context.read<AuthService>(), // Removed as RideRequestProvider creates its own
          )
        ),
    ],
    child: const MyApp(),
  ),
);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
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

// ✅ Automatically redirect user based on session
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    _checkUserSession();
  }

  void _checkUserSession() async {
    User? user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        String role = userDoc.get("role");

        if (!mounted) return; // Prevents calling setState if widget is disposed

        if (role == "customer") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const CustomerHome()),
          );
        } else if (role == "driver") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const DriverHome()),
          );
        } else if (role == "admin") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AdminHome()),
          );
        }
      }
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ), // Loading screen while checking session
    );
  }
}