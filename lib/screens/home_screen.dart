import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart'; // Import Firebase Messaging
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart'; // Import AuthService
import '../providers/driver_provider.dart'; // Import DriverProvider
import '../services/user_service.dart';
import '../services/firestore_service.dart'; // Import FirestoreService
import '../models/user_model.dart';
import 'customer_home.dart';
import 'driver_home.dart';
import 'admin_home.dart';
import 'additional_info_screen.dart';
import '../providers/location_provider.dart'; // Ensure LocationProvider is imported
import 'customer_account_screen.dart'; // Import CustomerAccountScreen
import 'driver_account_screen.dart'; // Import DriverAccountScreen
import 'chat_screen.dart'; // Import ChatScreen
import 'rides_screen.dart'; // Import the new RidesScreen
import '../providers/Notification_Provider.dart'; // Import NotificationProvider
import 'package:flutter/material.dart'; // Import Material package
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
  late final AuthService _authService; // Use late final
  User? _currentUser; // Store the current Firebase user
  StreamSubscription? _authStateSubscription; // To listen to auth state changes
  StreamSubscription? _onMessageSubscription; // To manage the FCM foreground listener

  // Store instances of the main screens for each role to preserve their state
  // Ensure these are initialized appropriately, perhaps in initState or as late final.
  // For simplicity, initializing directly here.
  final List<Widget> _driverScreens = const [ // Make the list itself const
    DriverHome(key: PageStorageKey('DriverHome')),
    RidesScreen(key: PageStorageKey('DriverRides'), role: 'Driver'),
    DriverAccountScreen(key: PageStorageKey('DriverAccountScreen')),
  ];
  final List<Widget> _customerScreens = const [ // Make the list itself const
    CustomerHome(key: PageStorageKey('CustomerHome')),
    RidesScreen(key: PageStorageKey('CustomerRides'), role: 'Customer'),
    CustomerAccountScreen(key: PageStorageKey('CustomerAccountScreen')),
  ];
  final List<Widget> _adminScreens = const [ // Make the list itself const
    AdminHome(key: PageStorageKey('AdminHome')),
    Text("Admin Dashboard Screen", key: PageStorageKey('AdminDashboard')),
    Text("Admin Screen", key: PageStorageKey('AdminScreenContent')), // Changed key to be more specific
    Text("Admin Account Screen", key: PageStorageKey('AdminAccount')),
  ];

  late final NotificationProvider _notificationProvider; // Add NotificationProvider instance

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false); 
    _notificationProvider = NotificationProvider( // Initialize NotificationProvider
      authService: _authService, firestoreService: Provider.of<FirestoreService>(context, listen: false), onForegroundMessageReceived: _showForegroundNotification, onNotificationTap: _handleNotificationTap,
    );

    // Listen to authentication state changes
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
      }
    });
    // Perform an initial check for the current user, as authStateChanges might not fire immediately
    // if the user is already logged in when the widget initializes.
    _currentUser = FirebaseAuth.instance.currentUser;
  }
  
  @override
  void dispose() {
    _authStateSubscription?.cancel(); // Cancel the auth state listener
    _onMessageSubscription?.cancel(); // Cancel the FCM listener
    super.dispose();
  }

  // Accept UserModel as a parameter
  Future<void> _initializeUserDependentServices(UserModel? userModel) async {
    if (userModel == null) {
      debugPrint("HomeScreen: No user model, cannot initialize user-dependent services.");
      return;
    }

    // Only update _currentUserModel if it's actually different or not set yet.
    // This helps prevent re-running this logic if the stream emits the same userModel.
    if (_currentUserModel?.uid == userModel.uid && _notificationProvider.isFcmSetupComplete) {
       // User is the same and FCM is already set up.
       // We might still want to re-check permissions if app comes from background.
       // For now, we can skip full re-initialization of NotificationProvider.
       // However, let's ensure permissions are checked.
       await _checkAppPermissions();
       return;
    }

    _currentUserModel = userModel;
    debugPrint("HomeScreen: Initializing user-dependent services for ${userModel.name}");

    // Initialize NotificationProvider (it has its own _isFcmInitialized guard)
    // This will also handle its internal notification permission request.
    await _notificationProvider.initialize();

    // Explicitly check/request other critical permissions like location.
    await _checkAppPermissions();
  }

  Future<void> _checkAppPermissions() async {
    // Notification permissions are handled by _notificationProvider.initialize()
    // or can be re-checked via _notificationProvider.checkAndRequestNotificationPermissions()

    // Check and request Location Permissions (via LocationProvider)
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    // Assuming LocationProvider has a method like this:
    bool locationPermissionsGranted = await locationProvider.checkAndRequestLocationPermission();
    if (!locationPermissionsGranted) {
      debugPrint("HomeScreen: Location permissions were not granted.");
      // Optionally, show a persistent message or guide the user to settings.
      if (mounted) {
        // ScaffoldMessenger.of(context).showSnackBar(
        //   const SnackBar(content: Text("Location permission is required for full app functionality.")),
        // );
      }
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
        // This method is now primarily for HomeScreen-specific UI updates
    // when a foreground message is received.
    // The NotificationProvider itself handles showing the actual local notification.
    debugPrint('HomeScreen: _showForegroundNotification callback triggered by NotificationProvider.');
    debugPrint('Message data: ${message.data}');
    if (message.notification != null) {
      debugPrint('Message also contained a notification: ${message.notification!.title}, ${message.notification!.body}');
    }

    // Example: Update DriverProvider if the message is a new ride request
    _updateDriverProviderFromFCM(message.data);

    /* Remove direct access to _localNotificationsPlugin
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

    await _notificationProvider._localNotificationsPlugin.show( // Use the plugin from NotificationProvider
      message.hashCode, // Unique ID for the notification
      message.notification?.title,
      message.notification?.body,
      platformChannelSpecifics,
      payload: message.data.toString() 
      );
    */
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


  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // Helper method to update DriverProvider from FCM data
  void _updateDriverProviderFromFCM(Map<String, dynamic> data) {
    // Add this debug print
    debugPrint("HomeScreen: _updateDriverProviderFromFCM called with data: $data");

    // Check if the notification is a new ride offer for a driver
    bool isNewRideOfferForDriver = data['status'] == 'pending_driver_acceptance' && data.containsKey('rideRequestId');

    if (mounted &&
        (isNewRideOfferForDriver || (_currentUserModel?.role == 'Driver')) && // Allow if new ride offer OR current role is Driver
        data.isNotEmpty &&
        data.containsKey('rideRequestId')) {
      try {
        final driverProvider = Provider.of<DriverProvider>(context, listen: false);
        // Add this debug print
        debugPrint("HomeScreen: Calling driverProvider.setNewPendingRide with data: $data");
        driverProvider.setNewPendingRide(data);
        debugPrint("HomeScreen: Passed ride data to DriverProvider from FCM.");
      } catch (e) {
        debugPrint("HomeScreen: Could not access DriverProvider or set pending ride from FCM: $e");
      }
    } else {
      // Add this debug print
      debugPrint("HomeScreen: _updateDriverProviderFromFCM - Conditions not met. Mounted: $mounted, Role: ${_currentUserModel?.role}, isNewRideOffer: $isNewRideOfferForDriver, Data empty: ${data.isEmpty}, Has rideRequestId: ${data.containsKey('rideRequestId')}");
    }
  }

  // Make the method async to allow fetching user details
  Future<void> _handleNotificationTap(Map<String, dynamic> data) async {
    debugPrint("HomeScreen: _handleNotificationTap called with data: $data");
    final String? rideRequestId = data['rideRequestId'] as String?;

    if (data['type'] == 'chat_message' && rideRequestId != null) {
      debugPrint("HomeScreen: Chat notification tapped for ride ID: $rideRequestId");
      final String? senderId = data['senderId'] as String?;
      String recipientName = "Chat User"; // Placeholder

      if (senderId != null && senderId.isNotEmpty) {
        try {
          // Assuming _userService is available and has a method like getUser.
          // If UserService doesn't have it, you might use FirestoreService directly.
          UserModel? senderProfile = await _userService.getUser(senderId); // Fetch sender's profile
          if (senderProfile != null) {
            recipientName = senderProfile.name ?? "Chat User";
          }
        } catch (e) {
          debugPrint("HomeScreen: Error fetching sender's profile for chat notification: $e");
          // recipientName remains "Chat User"
        }
      }

      // Ensure context is still valid if operations are async before navigation
      if (!mounted) return;

      // Navigate to ChatScreen
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ChatScreen(
          rideRequestId: rideRequestId,
          recipientId: senderId ?? '', // The person who sent the message
          recipientName: recipientName, // Name of the person who sent the message
        )),
      );
    } else if (_currentUserModel?.role == 'Driver' && rideRequestId != null && data['type'] != 'chat_message') { 
      debugPrint("HomeScreen: Ride Action notification tap for Driver, ride ID $rideRequestId. Current selectedIndex: $_selectedIndex");
      // DriverHome is at index 0 in _driverScreens.
      if (_selectedIndex != 0) {
        if (mounted) {
          setState(() {
            _selectedIndex = 0;
            debugPrint("HomeScreen: Switched to DriverHome tab (index 0).");
          });
        }
      }
      // Update the DriverProvider with the new ride data.
      // DriverHome listens to this provider and will show the accept/decline sheet.
      _updateDriverProviderFromFCM(data);
    } else {
      debugPrint("HomeScreen: _handleNotificationTap - Unhandled notification type or conditions not met. Type: ${data['type']}, Role: ${_currentUserModel?.role}, rideRequestId: $rideRequestId");
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
        _initializeUserDependentServices(userModel); // Update local userModel state
        _notificationProvider.initialize(); // Initialize FCM listeners via the provider

        // Handle navigation to AdditionalInfoScreen if role is missing
        // Or if userModel itself is null (still loading, or document truly doesn't exist for a new user)
        if (userModel == null || userModel.role == null) {
          // Only attempt to navigate if not already done/in progress for the current lifecycle of this screen instance
          if (!_navigatedToAdditionalInfo && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Re-check condition inside the callback as the stream might have updated
              if (mounted && (snapshot.data == null || snapshot.data!.role == null)) {
                // Set flag before pushing to prevent re-entry if this callback is triggered multiple times
                // or if the stream emits null again quickly.
                // This setState ensures the loading indicator is shown and we don't attempt to build _buildMainScreen.
                setState(() {
                  _navigatedToAdditionalInfo = true;
                });
                Navigator.push( // CHANGED from pushReplacement
                  context,
                  MaterialPageRoute(builder: (context) => AdditionalInfoScreen(userUid: _currentUser!.uid)),
                ).then((_) {
                  // When AdditionalInfoScreen is popped (either by saving or user backing out),
                  // reset the flag. The StreamBuilder will then re-evaluate.
                  // If role is still null, it will attempt to navigate again.
                  // If role is set, _buildMainScreen will be called.
                  if (mounted) {
                    setState(() {
                      _navigatedToAdditionalInfo = false;
                    });
                  }
                });
              }
            });
          }
          // Always show loading indicator if role is null and we're either navigating,
          // waiting for AdditionalInfoScreen to pop, or waiting for the stream to update.
          return Scaffold(
            body: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
          );
        } else { // Role is present
          // If we were previously in a state of navigating to AIS, but now have a role, ensure the flag is reset.
          if (_navigatedToAdditionalInfo) {
            // This reset is important if the stream updates to a non-null role
            // while _navigatedToAdditionalInfo was true.
            _navigatedToAdditionalInfo = false;
            // No setState needed here as we are about to return _buildMainScreen, which causes a rebuild.
          }
          return _buildMainScreen(userModel.role!);
        }
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
