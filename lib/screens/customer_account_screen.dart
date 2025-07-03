import 'package:flutter/material.dart';
import '../utils/ui_utils.dart'; // For spacing and styles
import 'about_us_screen.dart';
import 'help_and_support_screen.dart';
import 'saved_places_screen.dart';

class CustomerAccountScreen extends StatelessWidget {
  const CustomerAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    //final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account'),
        automaticallyImplyLeading: false, // No back button if it's a main tab
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionTitle(context, 'Account Management'),
          _buildAccountOption(context, Icons.payment, 'Payment Methods', () {
            // TODO: Navigate to Payment Methods
          }),
          _buildAccountOption(context, Icons.place, 'Saved Places', () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SavedPlacesScreen(),
              ),
            );
          }),
          verticalSpaceMedium,
          _buildSectionTitle(context, 'Preferences'),
          _buildAccountOption(context, Icons.notifications, 'Notification Preferences', () {
            // TODO: Navigate to Notification Preferences
          }),
          _buildAccountOption(context, Icons.language, 'Language', () {
            // TODO: Navigate to Language Selection
          }),
          verticalSpaceMedium,
          _buildSectionTitle(context, 'Support & Legal'),
          _buildAccountOption(context, Icons.help_outline, 'Help & Support',
              () {
            Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HelpAndSupportScreen(userRole: 'Customer')));
          }),
          _buildAccountOption(context, Icons.info_outline, 'About Us', () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AboutUsScreen(),
              ),
            );
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
    return ListTile(leading: Icon(icon, color: isDestructive ? theme.colorScheme.error : theme.colorScheme.primary), title: Text(title, style: TextStyle(color: isDestructive ? theme.colorScheme.error : null)), onTap: onTap, contentPadding: EdgeInsets.zero);
  }
}