import 'package:flutter/material.dart';
import 'admin/admin_dashboard_screen.dart';
import 'admin/user_management_screen.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // Number of tabs
      child: Scaffold(
        // The AppBar is now part of the Scaffold within DefaultTabController
        appBar: AppBar(
          // The title is now part of the AppBar within the Scaffold
          title: const Text('Admin Panel'),
          // The TabBar is placed in the bottom of the AppBar
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
              Tab(icon: Icon(Icons.people_alt_outlined), text: 'Users'),
            ],
          ),
        ),
        // The body is a TabBarView to display the content of each tab
        body: const TabBarView(
          children: [
            // Content for the 'Dashboard' tab
            AdminDashboardScreen(),
            // Content for the 'Users' tab
            UserManagementScreen(),
          ],
        ),
      ),
    );  
  }
}


