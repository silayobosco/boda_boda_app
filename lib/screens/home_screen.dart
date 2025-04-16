import 'package:flutter/material.dart';
//import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';
import '../theme/app_theme.dart';
import '../utils/ui_utils.dart';
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
  String? _errorMessage;
  String? _userRole;
  int _selectedIndex = 0;
  UserModel? _userModel;
  final UserService _userService = UserService();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userModel = await _userService.getUserModel(user.uid);
        setState(() {
          _userModel = userModel;
        });
      } catch (e) {
        setState(() {
          _errorMessage = "Error loading user data: $e";
        });
      }
    } else {
      // Handle the case where the user is not logged in
      setState(() {
        _errorMessage = "User not logged in";
      });
    }
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
    if (_userModel == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(child: Text(_errorMessage!));
    }

    if (_userModel!.role == null) {
      if (!_navigatedToAdditionalInfo) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigatedToAdditionalInfo = true;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder:
                  (context) => AdditionalInfoScreen(userUid: _userModel!.uid!),
            ),
          );
        });
        return const Center(child: CircularProgressIndicator());
      }
      return const Center(child: CircularProgressIndicator());
    }
    return _buildMainScreen(_userModel!.role!);
  }

    Widget _buildMainScreen(String role) {
      return Scaffold(
        drawer: const AppDrawer(),
        body: _getScreen(_selectedIndex, role),
        bottomNavigationBar: BottomNavigationBar(
          items: _getNavigationItems(role),
          currentIndex: _selectedIndex,
          selectedItemColor: AppThemes.lightTheme.primaryColor,
          unselectedItemColor: hintTextColor,
          onTap: _onItemTapped,
          backgroundColor: AppThemes.lightTheme.scaffoldBackgroundColor,
        ),
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
            child: const Icon(Icons.menu),
            backgroundColor: AppThemes.lightTheme.scaffoldBackgroundColor,
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
      );
    }
}
