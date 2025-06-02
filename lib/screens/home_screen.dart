import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Import local notifications
import 'package:firebase_messaging/firebase_messaging.dart'; // Import Firebase Messaging
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart'; // Import AuthService
import '../providers/driver_provider.dart'; // Import DriverProvider
import '../services/user_service.dart';
import '../models/user_model.dart';
import 'customer_home.dart';
import 'driver_home.dart';
import 'admin_home.dart';
import 'additional_info_screen.dart';
import '../widgets/app_drawer.dart'; 
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _navigatedToAdditionalInfo = false;
  // String? _errorMessage; // Error will be handled by StreamBuilder
  int _selectedIndex = 0;
  UserModel? _currentUserModel; // Store the UserModel from the StreamBuilder
  final UserService _userService = UserService();
  final AuthService _authService = AuthService(); // Add AuthService instance
  User? _currentUser; // Store the current Firebase user
  FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _fcmActionsInitializedForCurrentUser = false; // Flag to track initialization

  // Store instances of the main screens for each role to preserve their state
  // Ensure these are initialized appropriately, perhaps in initState or as late final.
  // For simplicity, initializing directly here.
  final List<Widget> _driverScreens = [
    const DriverHome(), // Screen for index 0
    const Text("Driver Rides Screen"), // Placeholder for index 1
    const Text("Driver Account Screen"), // Placeholder for index 2
  ];
  final List<Widget> _customerScreens = [
    const CustomerHome(), // Screen for index 0
    const Text("Customer Rides Screen"), // Placeholder for index 1
    const Text("Customer Account Screen"), // Placeholder for index 2
  ];
  final List<Widget> _adminScreens = [
    const AdminHome(), // Screen for index 0
    const Text("Admin Dashboard Screen"), // Placeholder for index 1
    const Text("Admin Screen"), // Placeholder for index 2
    const Text("Admin Account Screen"), // Placeholder for index 3 (if needed)
  ];

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    _initializeLocalNotifications();
    // FCM initialization will now happen after userModel is loaded in the builder
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

  // Accept UserModel as a parameter
  Future<void> _initializeFCMAndCurrentUserActions(UserModel? userModel) async {
    // Store the userModel in state
    // If userModel changes (e.g., user logs out and logs in as someone else), reset the flag.
    if (_currentUserModel?.uid != userModel?.uid) {
      _fcmActionsInitializedForCurrentUser = false;
    }
    _currentUserModel = userModel;

    if (_fcmActionsInitializedForCurrentUser) return; // Already initialized for this user

    if (_currentUser == null || _currentUserModel == null) return;

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

      // Check if the current user is a Driver and the message contains ride request data
      if (_currentUserModel?.role == 'Driver' &&
          message.data.isNotEmpty &&
          message.data.containsKey('rideRequestId')) {
         try {
           // Access DriverProvider without listening, assuming it's available in the context
           final driverProvider = Provider.of<DriverProvider>(context, listen: false);
           driverProvider.setNewPendingRide(message.data);
           debugPrint("HomeScreen: Passed ride data to DriverProvider.");
         } catch (e) {
           debugPrint("HomeScreen: Could not access DriverProvider or set pending ride: $e");
         }
      }
    });

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('HomeScreen: Message opened from background!');
      // Navigate or perform action based on message.data
      _handleNotificationTap(message.data);
    });

    // Handle notification tap when app is terminated
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('HomeScreen: Message opened from terminated state!');
         if (_currentUserModel?.role == 'Driver' && message.data.isNotEmpty && message.data.containsKey('rideRequestId')) {
           try {
             // Access DriverProvider without listening
             final driverProvider = Provider.of<DriverProvider>(context, listen: false);
             driverProvider.setNewPendingRide(message.data);
             debugPrint("HomeScreen: Passed ride data from terminated state to DriverProvider.");
           } catch (e) {
             debugPrint("HomeScreen: Could not access DriverProvider or set pending ride from terminated state: $e");
           }
        }
        _handleNotificationTap(message.data);
      }
    });

    // Get and save FCM token
    _authService.getAndSaveFCMToken(); // Assumes AuthService has this method

    // Listen for token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _authService.saveFCMTokenToFirestore(newToken); // Assumes AuthService has this method
    });
    _fcmActionsInitializedForCurrentUser = true; // Mark as initialized
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

  List<Widget> _getCurrentScreenList(String role) {
    switch (role) {
      case 'Admin':
        return _adminScreens;
      case 'Driver':
        return _driverScreens;
      case 'Customer':
      default:
        return _customerScreens;
    }
  }

  // This method is no longer strictly needed if IndexedStack directly uses the list,
  // but can be kept if you need to get a single screen instance for other purposes.
  Widget _getScreen(int index, String role) {
    final screenList = _getCurrentScreenList(role);
    if (index >= 0 && index < screenList.length) {
      return screenList[index];
    } else {
      // Fallback for invalid index, though IndexedStack handles this by crashing if index is out of bounds.
      // Consider logging this error.
      return Text('Error: Invalid screen index $index for role $role');
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    final String? rideRequestId = data['rideRequestId'] as String?;
    // Check if the current user is a Driver and the data contains a rideRequestId
    if (_currentUserModel?.role == 'Driver' && rideRequestId != null) {
      debugPrint("Notification tap: Navigating for ride ID $rideRequestId");
      // Ensure we are on the DriverHome screen.
      // This assumes DriverHome is the screen at index 0 for the Driver role.
      // If your navigation is more complex, you might need Navigator.pushNamed or a global key.
      if (_selectedIndex != 0 || _currentUserModel?.role != 'Driver') {
         // Navigate to DriverHome (index 0 for Driver)
         // Using pushReplacement to avoid stacking screens if already deep in navigation
         Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomeScreen()));
         // Note: This will rebuild HomeScreen and the StreamBuilder, which will then
         // re-initialize FCM handlers with the correct context and userModel.
         // The getInitialMessage/onMessageOpenedApp might need to be re-processed slightly.
      }

      // Now that we are (or are ensuring we are) on the correct screen, update the provider.
      try {
        final driverProvider = Provider.of<DriverProvider>(context, listen: false);
        driverProvider.setNewPendingRide(data);
      } catch (e) {
        debugPrint("HomeScreen: Could not access DriverProvider from notification tap handler: $e");
      }
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
        _initializeFCMAndCurrentUserActions(userModel);// Initialize FCM and actions with the loaded userModel


        if (userModel == null || userModel.uid == null) {
          // User document doesn't exist or is incomplete.
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
      final List<Widget> currentScreenList = _getCurrentScreenList(role);
      return Scaffold(
        drawer: const AppDrawer(),
        body: IndexedStack( // Use IndexedStack to preserve state of screens
          index: _selectedIndex,
          children: currentScreenList,
        ),
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
