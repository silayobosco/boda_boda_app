import 'driver_registration_screen.dart';
import 'login_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../utils/ui_utils.dart'; // For spacing and styles
import 'about_us_screen.dart';
import 'help_and_support_screen.dart';
import 'saved_places_screen.dart';
import '../localization/locales.dart';
import 'language_selection_screen.dart';
import 'legal_and_privacy_screen.dart';
import '../utils/account_utils.dart';

class CustomerAccountScreen extends StatelessWidget {
  const CustomerAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocale.myAccount.getString(context)),
        centerTitle: true,
        automaticallyImplyLeading: false, // No back button if it's a main tab
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionTitle(context, AppLocale.accountManagement.getString(context)),
          _buildAccountOption(context, Icons.payment, AppLocale.paymentMethods.getString(context), () {
            // TODO: Navigate to Payment Methods
          }),
          _buildAccountOption(context, Icons.place, AppLocale.savedPlaces.getString(context), () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SavedPlacesScreen(),
              ),
            );
          }),
          verticalSpaceMedium,
          _buildSectionTitle(context, AppLocale.preferences.getString(context)),
          _buildAccountOption(context, Icons.notifications, AppLocale.notificationPreferences.getString(context), () {
            // TODO: Navigate to Notification Preferences
          }),
          _buildAccountOption(context, Icons.language, AppLocale.language.getString(context), () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const LanguageSelectionScreen()),
            );
          }),
          verticalSpaceMedium,
          _buildSectionTitle(context, AppLocale.supportLegal.getString(context)),
          _buildAccountOption(context, Icons.support_agent, AppLocale.helpSupport.getString(context),
              () {
            Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HelpAndSupportScreen(userRole: 'Customer')));
          }),
          _buildAccountOption(context, Icons.info_outline, AppLocale.aboutUs.getString(context), () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AboutUsScreen(),
              ),
            );
          }),
          _buildAccountOption(context, Icons.gavel, AppLocale.legalPrivacy.getString(context), () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const LegalAndPrivacyScreen(userRole: 'Customer')),
            );
          }),
          verticalSpaceLarge,
          _buildSectionTitle(context, AppLocale.accountActions.getString(context)),
          _buildDriverSwitchOption(context),
          verticalSpaceSmall,
          _buildAccountOption(context, Icons.delete_forever, AppLocale.deleteAccount.getString(context),
              () => AccountUtils.showDeleteAccountDialog(context), isDestructive: true),
          verticalSpaceSmall,
          _buildAccountOption(context, Icons.exit_to_app, AppLocale.logout.getString(context),
              () => _showLogoutConfirmationDialog(context), isDestructive: true),
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

  Widget _buildDriverSwitchOption(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const SizedBox.shrink(); // Should not happen if user is on this screen
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(
            leading: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            title: Text("..."),
            enabled: false,
            contentPadding: EdgeInsets.zero,
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          // Fallback to "Become a Driver" if user data is missing for some reason
          return _buildAccountOption(context, Icons.directions_bike, AppLocale.becomeADriver.getString(context), () {
            _navigateToDriverRegistration(context);
          });
        }

        final userData = snapshot.data!.data();
        final driverProfile = userData?['driverProfile'] as Map<String, dynamic>?;
        final bool hasCompletedDriverProfile = driverProfile?['kijiweId'] != null && (driverProfile!['kijiweId'] as String).isNotEmpty;

        if (hasCompletedDriverProfile) {
          // User has a complete driver profile, allow switching
          return _buildAccountOption(context, Icons.switch_account, AppLocale.switchToDriver.getString(context), () {
            _switchRoleToDriver(context, currentUser.uid);
          });
        } else {
          // User does not have a complete profile, prompt to register
          return _buildAccountOption(context, Icons.directions_bike, AppLocale.becomeADriver.getString(context), () {
            _navigateToDriverRegistration(context);
          });
        }
      },
    );
  }

  void _navigateToDriverRegistration(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DriverRegistrationScreen()),
    );
  }

  void _switchRoleToDriver(BuildContext context, String userId) async {
    // Capture context-dependent objects before async gap
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      // Show a loading indicator if needed, but it should be quick
      // For simplicity, we'll just perform the action directly.

      await FirebaseFirestore.instance.collection('users').doc(userId).update({'role': 'Driver'});

      // Sign out to force re-authentication with the new role
      await FirebaseAuth.instance.signOut();

      // After the await, check if the widget is still mounted before navigating
      if (!context.mounted) return;

      // Navigate to login screen
      navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
    } catch (e) {
      debugPrint("Error switching role to Driver: $e");
      if (context.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('${AppLocale.failedToSwitchRole.getString(context)}: ${e.toString()}')),
        );
      }
    }
  }

  void _showLogoutConfirmationDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocale.logout.getString(context)),
        content: Text(AppLocale.logout_confirmation.getString(context)),
        actions: [
          TextButton(
            child: Text(AppLocale.dialog_cancel.getString(context), style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: Text(AppLocale.logout.getString(context)),
            onPressed: () async {
              // Close dialog
              Navigator.of(dialogContext).pop();

              // Capture context-dependent objects before async gap
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

              try {
                // Sign out from Firebase
                await FirebaseAuth.instance.signOut();

                // Navigate to login screen
                if (!context.mounted) return;
                navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
              } catch (e) {
                debugPrint("Error during logout: $e");
                if (context.mounted) {
                  scaffoldMessenger.showSnackBar(SnackBar(content: Text('${AppLocale.error_logging_out.getString(context)}: ${e.toString()}')));
                }
              }
            },
          ),
        ],
      ),
    );
  }
}