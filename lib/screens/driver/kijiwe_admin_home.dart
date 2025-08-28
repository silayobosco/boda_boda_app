import 'package:flutter/material.dart';
import 'kijiwe_admin_dashboard_screen.dart';

import 'kijiwe_admin_reports_screen.dart';
import 'kijiwe_admin_settings_screen.dart';

class KijiweAdminHome extends StatelessWidget {
  const KijiweAdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3, // Number of tabs
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kijiwe Admin Panel'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
              Tab(icon: Icon(Icons.analytics_outlined), text: 'Reports'),
              Tab(icon: Icon(Icons.settings_outlined), text: 'Settings'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            KijiweAdminDashboardScreen(),
            KijiweAdminReportsScreen(),
            KijiweAdminSettingsScreen(),
          ],
        ),
      ),
    );
  }
}
