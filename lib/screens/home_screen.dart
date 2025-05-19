import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Import local notifications
import 'package:firebase_messaging/firebase_messaging.dart'; // Import Firebase Messaging
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart'; // Import AuthService
import '../services/user_service.dart';
import '../models/user_model.dart';
import 'customer_home.dart';
import 'driver_home.dart';
import 'admin_home.dart';
import 'additional_info_screen.dart';
import '../widgets/app_drawer.dart'; 

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _navigatedToAdditionalInfo = false;
  // String? _errorMessage; // Error will be handled by StreamBuilder
  int _selectedIndex = 0;
  // UserModel? _userModel; // UserModel will come from StreamBuilder
  final UserService _userService = UserService();
  final AuthService _authService = AuthService(); // Add AuthService instance
  User? _currentUser; // Store the current Firebase user
  FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _initializeLocalNotifications();
    _initializeFCMAndCurrentUserActions();
  }

  Future<void> _initializeLocalNotifications() async {
    // Initialize settings for Android
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher'); // Replace with your app icon name

    // Initialize settings for iOS (optional, if you target iOS)
    // const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
    //   requestAlertPermission: true,
    //   requestBadgePermission: true,
    //   requestSoundPermission: true,
    // );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      // iOS: initializationSettingsIOS,
    );
    await _flutterLocalNotificationsPlugin.initialize(initializationSettings,
        onDidReceiveNotificationResponse: _onDidReceiveLocalNotificationResponse);
  }

  void _onDidReceiveLocalNotificationResponse(NotificationResponse notificationResponse) async {
    final String? payload = notificationResponse.payload;
    if (payload != null) {
      debugPrint('Local notification payload: $payload');
      // You can parse the payload (if it's JSON, for example) and navigate
      // For now, we'll assume the payload might be the message.data stringified
      // Or you can pass specific data like rideRequestId
      // Map<String, dynamic> data = jsonDecode(payload); // If payload is a JSON string
      // _handleNotificationTap(data);
    }
    // Example: Navigate to a specific screen or handle the tap
  }

  Future<void> _initializeFCMAndCurrentUserActions() async {
    if (_currentUser == null) return;

    // Request notification permissions (iOS and web)
    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    debugPrint('User granted permission: ${settings.authorizationStatus}');

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('HomeScreen: Foreground FCM message received!');
      debugPrint('Message data: ${message.data}');
      if (message.notification != null) {
        debugPrint('Message also contained a notification: ${message.notification!.title}, ${message.notification!.body}');
        _showForegroundNotification(message);
      }
      // You can update UI or show an in-app banner based on message.data
    });

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('HomeScreen: Message opened from background!');
      debugPrint('Message data: ${message.data}');
      // Navigate or perform action based on message.data
      _handleNotificationTap(message.data);
    });

    // Handle notification tap when app is terminated
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('HomeScreen: Message opened from terminated state!');
        debugPrint('Message data: ${message.data}');
        // Navigate or perform action based on message.data
        _handleNotificationTap(message.data);
      }
    });

    // Get and save FCM token
    _authService.getAndSaveFCMToken(); // Assumes AuthService has this method

    // Listen for token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _authService.saveFCMTokenToFirestore(newToken); // Assumes AuthService has this method
    });
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'your_channel_id', // Must match the channel ID in AndroidManifest.xml if you set one, or create one here
      'Your Channel Name', // Name for the channel
      channelDescription: 'Channel for foreground notifications', // Description
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false, // Set to true to show timestamp
      // sound: RawResourceAndroidNotificationSound('your_custom_sound'), // Optional custom sound
    );
    // const DarwinNotificationDetails iOSPlatformChannelSpecifics = DarwinNotificationDetails(); // For iOS
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics /*, iOS: iOSPlatformChannelSpecifics*/);

    await _flutterLocalNotificationsPlugin.show(
        message.hashCode, // Unique ID for the notification
        message.notification?.title,
        message.notification?.body,
        platformChannelSpecifics,
        payload: message.data.toString() // Optional: Pass data to be used when notification is tapped
        );
  }

  List<BottomNavigationBarItem> _getNavigationItems(String role) {
    switch (role) {
      case 'Admin':
        return [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Dashboard',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.admin_panel_settings),
            label: 'Admin',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'Admin',
          ),
        ];
      case 'Driver':
        return [
          const BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Home'),
          const BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Rides',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'Account',
          ),
        ];
      case 'Customer':
      default:
        return [
          const BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Home'),
          const BottomNavigationBarItem(
            icon: Icon(Icons.motorcycle),
            label: 'Rides',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'Account',
          ),
        ];
    }
  }

  Widget _getScreen(int index, String role) {
    switch (role) {
      case 'Admin':
        switch (index) {
          case 0:
            return const AdminHome();
          case 1:
            return const Text(
              "Admin Dashboard Screen",
            ); // Replace with your actual screen
          case 2:
            return const Text(
              "Admin Screen",
            ); // Replace with your actual screen
          default:
            return const Text('Error: Invalid Admin Screen');
        }
      case 'Driver':
        switch (index) {
          case 0:
            return const DriverHome();
          case 1:
            return const Text(
              "Driver Rides Screen",
            ); // Replace with your actual screen
          case 2:
            return const Text(
              "Driver Account Screen",
            ); // Replace with your actual screen
          default:
            return const Text('Error: Invalid Driver Screen');
        }
      case 'Customer':
      default:
        switch (index) {
          case 0:
            return const CustomerHome();
          case 1:
            return const Text(
              "Customer Rides Screen",
            ); // Replace with your actual screen
          case 2:
            return const Text(
              "Customer Account Screen",
            ); // Replace with your actual screen
          default:
            return const Text('Error: Invalid Customer Screen');
        }
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    // Example: Navigate if rideRequestId is present
    final String? rideRequestId = data['rideRequestId'] as String?;
    if (rideRequestId != null) {
      debugPrint("Notification tap: Navigating for ride ID $rideRequestId");
      // Add your navigation logic here, e.g.,
      // Navigator.of(context).pushNamed('/rideDetailsScreen', arguments: rideRequestId);
      // Ensure you have a navigatorKey if calling from outside a widget with context.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      // This case should ideally be handled by a root-level auth listener
      // that navigates to LoginScreen if no user is signed in.
      // For now, providing a fallback UI.
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Not authenticated. Please log in.", style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Example: Navigate to login, adjust route as needed
                  Navigator.of(context).pushReplacementNamed('/login'); // Ensure '/login' route exists
                },
                child: const Text("Go to Login"),
              )
            ],
          ),
        ),
      );
    }

    return StreamBuilder<UserModel?>(
      stream: _userService.getUserModelStream(_currentUser!.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text(
              "Error loading user data: ${snapshot.error}",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error),
            )),
          );
        }

        final userModel = snapshot.data;

        if (userModel == null || userModel.uid == null) {
          // User document doesn't exist or is incomplete.
          // This could be a new user who needs to go to AdditionalInfoScreen,
          // or an error state if a logged-in user has no Firestore doc.
          // The logic below for userModel.role == null will handle AdditionalInfoScreen.
          // If userModel is truly null (doc doesn't exist), you might want to create it
          // or navigate to a specific "create profile" screen.
          // For now, we let the role check handle it.
        }

        // Handle navigation to AdditionalInfoScreen if role is missing
        if (userModel?.role == null) {
          if (!_navigatedToAdditionalInfo) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) { // Ensure widget is still in the tree
                _navigatedToAdditionalInfo = true;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdditionalInfoScreen(userUid: _currentUser!.uid),
                  ),
                );
              }
            });
          }
          // Show loading indicator while navigating or if stuck
          return Scaffold(
            body: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
          );
        }
        // If role is present, reset the flag (in case user went back from AdditionalInfoScreen without completing)
        _navigatedToAdditionalInfo = false;

        return _buildMainScreen(userModel!.role!);
      },
    );
  }
  
    Widget _buildMainScreen(String role) {
      return Scaffold(
        drawer: const AppDrawer(),
        body: _getScreen(_selectedIndex, role),
        bottomNavigationBar: BottomNavigationBar(
          items: _getNavigationItems(role),
          currentIndex: _selectedIndex,
          // Use theme colors
          selectedItemColor: Theme.of(context).colorScheme.primary,
          unselectedItemColor: Theme.of(context).hintColor, // Use theme hint color
          onTap: _onItemTapped,
          backgroundColor: Theme.of(context).colorScheme.surface, // Use theme surface color
          type: BottomNavigationBarType.fixed, // Ensures background color is applied
        ),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
            // Use theme colors for FAB
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            child: const Icon(Icons.menu),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
      );
    }
}
