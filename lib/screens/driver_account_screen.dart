import 'login_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../utils/ui_utils.dart'; // For spacing and styles
import 'about_us_screen.dart';
import 'help_and_support_screen.dart';
import '../localization/locales.dart';
import 'language_selection_screen.dart';
import 'legal_and_privacy_screen.dart';
import '../utils/account_utils.dart';
import '../providers/driver_provider.dart';
import 'kijiwe_profile_screen.dart';

class DriverAccountScreen extends StatelessWidget {
  const DriverAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DriverProvider>(
      builder: (context, driverProvider, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(AppLocale.myAccount.getString(context)),
            centerTitle: true,
            automaticallyImplyLeading: false, // No back button if it's a main tab
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildSectionTitle(context, AppLocale.driverOperations.getString(context)),
              _buildAccountOption(context, Icons.account_balance_wallet, AppLocale.earningsWallet.getString(context), () {
                // TODO: Navigate to Earnings
              }),
              _buildAccountOption(context, Icons.motorcycle, AppLocale.vehicleManagement.getString(context), () {
                // TODO: Navigate to Vehicle Management
              }),
              _buildAccountOption(context, Icons.description, AppLocale.documentManagement.getString(context), () {
                // TODO: Navigate to Document Management
              }),
              _buildAccountOption(context, Icons.group_work, AppLocale.kijiweProfile.getString(context), () {
                final kijiweId = driverProvider.currentKijiweId;
                if (kijiweId != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => KijiweProfileScreen(kijiweId: kijiweId)),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('You are not currently associated with a Kijiwe.')),
                  );
                }
              }),
              _buildAccountOption(context, Icons.bar_chart, AppLocale.performance.getString(context), () {
                // TODO: Navigate to Performance
              }),
              verticalSpaceMedium,
              _buildSectionTitle(context, AppLocale.preferences.getString(context)),
              _buildAccountOption(context, Icons.notifications_active, AppLocale.notificationPreferences.getString(context), () {
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
                    MaterialPageRoute(builder: (context) => const HelpAndSupportScreen(userRole: 'Driver')));
              }),
              _buildAccountOption(context, Icons.info_outline, AppLocale.aboutUs.getString(context), () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AboutUsScreen()),
                );
              }),
              _buildAccountOption(context, Icons.gavel, AppLocale.legalPrivacy.getString(context), () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LegalAndPrivacyScreen(userRole: 'Driver')),
                );
              }),
              verticalSpaceLarge,
              _buildSectionTitle(context, AppLocale.accountActions.getString(context)),
              _buildAccountOption(context, Icons.switch_account, AppLocale.switchToCustomer.getString(context), () {
                _showSwitchRoleDialog(context, driverProvider);
              }),
              verticalSpaceSmall,
              _buildAccountOption(context, Icons.delete_forever, AppLocale.deleteAccount.getString(context),
                  () => AccountUtils.showDeleteAccountDialog(context), isDestructive: true),
              verticalSpaceSmall,
              _buildAccountOption(context, Icons.exit_to_app, AppLocale.logout.getString(context),
                  () => _showLogoutConfirmationDialog(context, driverProvider), isDestructive: true),
            ],
          ),
        );
      },
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

  void _showSwitchRoleDialog(BuildContext context, DriverProvider driverProvider) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocale.switchToCustomer.getString(context)),
        content: Text(AppLocale.switch_to_customer_warning.getString(context)),
        actions: [
          TextButton(
            child: Text(AppLocale.dialog_cancel.getString(context), style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
            child: Text(AppLocale.switch_and_go_offline.getString(context)),
            onPressed: () async {
              // Close dialog first
              Navigator.of(dialogContext).pop();

              // Capture context-dependent objects before async gap
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              final authService = AuthService();
              final String? userId = authService.currentUser?.uid;

              if (userId == null) {
                scaffoldMessenger.showSnackBar(SnackBar(content: Text(AppLocale.error_user_not_found.getString(context))));
                return;
              }

              try {
                // Go offline first (referencing logic from driver_home.dart)
                if (driverProvider.isOnline) {
                  await driverProvider.toggleOnlineStatus();
                }
                
                // Then switch role in Firestore
                await FirebaseFirestore.instance.collection('users').doc(userId).update({'role': 'Customer'});

                // Sign out to force re-authentication with the new role
                await FirebaseAuth.instance.signOut();

                // Navigate to login screen
                navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
              } catch (e) {
                scaffoldMessenger.showSnackBar(SnackBar(content: Text("${AppLocale.failedToSwitchRole.getString(context)}: $e")));
              }
            },
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmationDialog(BuildContext context, DriverProvider driverProvider) {
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
                // Go offline first
                if (driverProvider.isOnline) {
                  await driverProvider.toggleOnlineStatus();
                }

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