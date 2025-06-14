import 'package:flutter/material.dart';
import '../utils/ui_utils.dart'; // For spacing and styles

class DriverAccountScreen extends StatelessWidget {
  const DriverAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    //final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Account'),
        automaticallyImplyLeading: false, // No back button if it's a main tab
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionTitle(context, 'Driver Operations'),
          _buildAccountOption(context, Icons.account_balance_wallet, 'Earnings / Wallet', () {
            // TODO: Navigate to Earnings
          }),
          _buildAccountOption(context, Icons.motorcycle, 'Vehicle Management', () {
            // TODO: Navigate to Vehicle Management
          }),
          _buildAccountOption(context, Icons.description, 'Document Management', () {
            // TODO: Navigate to Document Management
          }),
          _buildAccountOption(context, Icons.group_work, 'Kijiwe Profile', () {
            // TODO: Navigate to Kijiwe Profile/Management
          }),
          _buildAccountOption(context, Icons.bar_chart, 'Performance', () {
            // TODO: Navigate to Performance
          }),
          verticalSpaceMedium,
          _buildSectionTitle(context, 'Preferences'),
          _buildAccountOption(context, Icons.notifications_active, 'Notification Preferences', () {
            // TODO: Navigate to Notification Preferences
          }),
          _buildAccountOption(context, Icons.language, 'Language', () {
            // TODO: Navigate to Language Selection
          }),
          verticalSpaceMedium,
          _buildSectionTitle(context, 'Support & Legal'),
          _buildAccountOption(context, Icons.support_agent, 'Help & Support', () {
            // TODO: Navigate to Help & Support
          }),
          _buildAccountOption(context, Icons.info_outline, 'About Us', () {
            // TODO: Navigate to About Us
          }),
          _buildAccountOption(context, Icons.gavel, 'Legal & Privacy', () {
            // TODO: Navigate to Legal & Privacy
          }),
          verticalSpaceLarge,
          _buildAccountOption(context, Icons.delete_forever, 'Delete Account', () {
            // TODO: Implement Delete Account flow
          }, isDestructive: true),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildAccountOption(BuildContext context, IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    final theme = Theme.of(context);
    return ListTile(
        leading: Icon(icon, color: isDestructive ? theme.colorScheme.error : theme.colorScheme.primary),
        title: Text(title, style: TextStyle(color: isDestructive ? theme.colorScheme.error : null)),
        onTap: onTap,
        contentPadding: EdgeInsets.zero);
  }
}