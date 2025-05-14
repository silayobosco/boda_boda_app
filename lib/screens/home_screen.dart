import 'package:flutter/material.dart';
//import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  User? _currentUser; // Store the current Firebase user

  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
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
