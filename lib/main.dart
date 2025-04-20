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


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final themeProvider = ThemeProvider();
  await themeProvider.loadThemeMode();

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
            authService: context.read<AuthService>(),
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