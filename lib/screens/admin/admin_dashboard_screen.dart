import 'package:flutter/material.dart';
import '../../utils/ui_utils.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dashboard Overview', style: theme.textTheme.titleLarge),
            verticalSpaceMedium,
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                _buildStatCard(theme, 'Total Users', '1,234', Icons.people_outline),
                _buildStatCard(theme, 'Active Drivers', '56', Icons.drive_eta_outlined),
                _buildStatCard(theme, 'Rides Today', '128', Icons.motorcycle_outlined),
                _buildStatCard(theme, 'Total Kijiwes', '15', Icons.groups_outlined),
              ],
            ),
            verticalSpaceLarge,
            Text('Recent Activity', style: theme.textTheme.titleLarge),
            verticalSpaceMedium,
            // Placeholder for recent activity list
            const Center(child: Text('Recent activity feed coming soon.')),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(ThemeData theme, String title, String value, IconData icon) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text(title, style: theme.textTheme.bodyMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}