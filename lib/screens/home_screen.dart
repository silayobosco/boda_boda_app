import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auth_service.dart'; // Import AuthService
import '../services/user_service.dart';
import '../models/user_model.dart';
import 'customer_home.dart';
import 'driver_home.dart';
import 'additional_info_screen.dart';
import '../providers/location_provider.dart'; // Ensure LocationProvider is imported
import 'customer_account_screen.dart'; // Import CustomerAccountScreen
import 'driver_account_screen.dart'; // Import DriverAccountScreen
import 'rides_screen.dart'; // Import the new RidesScreen
import 'package:flutter/material.dart'; // Import Material package
import '../widgets/app_drawer.dart'; 
import 'package:flutter_localization/flutter_localization.dart';
import '../localization/locales.dart';
import 'package:provider/provider.dart';
import 'driver/kijiwe_admin_home.dart'; // Import KijiweAdminHome

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

  @override
  void initState() {
    super.initState();
    _authService = Provider.of<AuthService>(context, listen: false); 

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
    super.dispose();
  }

  // Accept UserModel as a parameter
  Future<void> _initializeUserDependentServices(UserModel? userModel) async {
    if (userModel == null) {
      debugPrint("HomeScreen: No user model, cannot initialize user-dependent services.");
      return;
    }

    // Only run this logic if the user model has changed.
    if (_currentUserModel?.uid == userModel.uid) {
      return;
    }

    _currentUserModel = userModel;
    debugPrint("HomeScreen: Initializing user-dependent services for ${userModel.name}");

    // If the user is a driver, update the DriverProvider with the latest UserModel.
    // This centralizes data fetching and ensures consistency.
    if (userModel.role == 'Driver') {
      // Assuming you add a method like `updateFromUserModel` to your DriverProvider
      // Provider.of<DriverProvider>(context, listen: false).updateFromUserModel(userModel);
    }

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

  List<BottomNavigationBarItem> _getNavigationItems(String role, {String? kijiweAdminId, String? currentUserId}) {
    switch (role) {
      case 'Driver':
        // Check if current driver is a kijiwe admin
        final isKijiweAdmin = kijiweAdminId != null && currentUserId != null && kijiweAdminId == currentUserId;
        
        if (isKijiweAdmin) {
          return [
            const BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Home'),
            const BottomNavigationBarItem(
              icon: Icon(Icons.assignment),
              label: 'Rides',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.admin_panel_settings),
              label: 'Admin',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.account_circle),
              label: 'Account',
            ),
          ];
        } else {
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
        }
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

  List<Widget> _getCurrentScreenList(UserModel userModel, {String? kijiweAdminId}) {
    // Build the screen lists on the fly to pass necessary data.
    switch (userModel.role) {
      case 'Driver':
        // Check if current driver is a kijiwe admin
        final isKijiweAdmin = kijiweAdminId != null && userModel.uid != null && kijiweAdminId == userModel.uid;
        
        if (isKijiweAdmin) {
          return [
            const DriverHome(key: PageStorageKey('DriverHome')),
            const RidesScreen(key: PageStorageKey('DriverRides'), role: 'Driver'),
            KijiweAdminHome(key: const PageStorageKey('KijiweAdminHome')),
            DriverAccountScreen(key: const PageStorageKey('DriverAccountScreen')),
          ];
        } else {
          return const [
            DriverHome(key: PageStorageKey('DriverHome')),
            RidesScreen(key: PageStorageKey('DriverRides'), role: 'Driver'),
            DriverAccountScreen(key: PageStorageKey('DriverAccountScreen')),
          ];
        }
      case 'Customer':
      default:
        return [
          const CustomerHome(key: PageStorageKey('CustomerHome')),
          const RidesScreen(key: PageStorageKey('CustomerRides'), role: 'Customer'),
          // Pass the userModel to avoid re-fetching data inside the account screen.
          CustomerAccountScreen(
            key: const PageStorageKey('CustomerAccountScreen'),
            userModel: userModel,
          ),
        ];
    }
  }


  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
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
          return _buildMainScreen(userModel);
        }
      },
    );
  }
  
  Widget _buildMainScreen(UserModel userModel) {
    // For drivers, check if they are kijiwe admin
    String? kijiweAdminId;
    if (userModel.role == 'Driver' && userModel.driverProfile != null) {
      final kijiweId = userModel.driverProfile!['kijiweId'] as String?;
      if (kijiweId != null) {
        // We'll need to fetch the kijiwe admin ID
        // For now, we'll use a FutureBuilder to handle this
        return FutureBuilder<String?>(
          future: _getKijiweAdminId(kijiweId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Scaffold(
                body: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
              );
            }
            
            kijiweAdminId = snapshot.data;
            return _buildMainScreenContent(userModel, kijiweAdminId);
          },
        );
      }
    }
    
    return _buildMainScreenContent(userModel, kijiweAdminId);
  }
  
  Widget _buildMainScreenContent(UserModel userModel, String? kijiweAdminId) {
    final List<Widget> currentScreenList = _getCurrentScreenList(userModel, kijiweAdminId: kijiweAdminId);
    
    return Scaffold(
      drawer: AppDrawer(
        userRole: userModel.role!,
        userName: userModel.name ?? AppLocale.unknownUser.getString(context),
        userEmail: userModel.email,
        photoUrl: userModel.profileImageUrl,
      ),
      body: IndexedStack( // Use IndexedStack to preserve state of screens
        index: _selectedIndex,
        children: currentScreenList,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: _getNavigationItems(userModel.role!, kijiweAdminId: kijiweAdminId, currentUserId: userModel.uid ?? ''),
        currentIndex: _selectedIndex,
        // Use theme colors
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant, // Use theme onSurfaceVariant color
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
  
  Future<String?> _getKijiweAdminId(String kijiweId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final kijiweDoc = await firestore.collection('kijiwe').doc(kijiweId).get();
      if (kijiweDoc.exists) {
        final kijiweData = kijiweDoc.data()!;
        return kijiweData['adminId'] as String?;
      }
    } catch (e) {
      debugPrint('Error fetching kijiwe admin ID: $e');
    }
    return null;
  }
}
