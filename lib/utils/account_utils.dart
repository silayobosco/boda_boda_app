import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:provider/provider.dart';
import '../localization/locales.dart';
import '../services/auth_service.dart';
import '../providers/driver_provider.dart';

class AccountUtils {
  static Future<void> showDeleteAccountDialog(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocale.deleteAccountTitle.getString(dialogContext)),
        content: Text(AppLocale.deleteAccountContent.getString(dialogContext)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocale.deleteAccountCancel.getString(dialogContext)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(AppLocale.deleteAccountConfirm.getString(dialogContext)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('deleteUserAccount');
        await callable.call();

        if (!context.mounted) return;
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog

        await Provider.of<AuthService>(context, listen: false).signOut();

        if (!context.mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (Route<dynamic> route) => false);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocale.deleteAccountSuccess.getString(context))),
        );
      } catch (e) {
        if (!context.mounted) return;
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocale.deleteAccountError.getString(context)} Please try again.')),
        );
      }
    }
  }

  static void showLogoutConfirmationDialog(BuildContext context, {String? userRole}) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        // It's best practice to get theme and localization from the dialog's own context.
        final theme = Theme.of(dialogContext);

        // Choose the confirmation message based on the user's role.
        final String confirmationMessage = (userRole == 'Driver')
            ? AppLocale.logout_confirmation_driver.getString(dialogContext)
            : AppLocale.logout_confirmation_customer.getString(dialogContext);

        return AlertDialog(
          title: Text(AppLocale.logout.getString(dialogContext)),
          content: Text(confirmationMessage),
          actions: [
            TextButton(
              child: Text(AppLocale.dialog_cancel.getString(dialogContext), style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: Text(AppLocale.logout.getString(dialogContext)),
              onPressed: () async {
                // Close dialog
                Navigator.of(dialogContext).pop();

                // Capture context-dependent objects from the original context before the async gap
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final authService = Provider.of<AuthService>(context, listen: false);

                try {
                  // If user is a driver, make them offline first
                  if (userRole == 'Driver') {
                    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
                    if (driverProvider.isOnline) {
                      await driverProvider.toggleOnlineStatus();
                    }
                  }

                  // Sign out using the AuthService, consistent with delete dialog
                  await authService.signOut();

                  // Navigate to login screen
                  if (!context.mounted) return;
                  navigator.pushNamedAndRemoveUntil('/login', (Route<dynamic> route) => false);
                } catch (e) {
                  debugPrint("Error during logout: $e");
                  if (context.mounted) {
                    scaffoldMessenger.showSnackBar(SnackBar(content: Text('${AppLocale.error_logging_out.getString(context)}: ${e.toString()}')));
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  static void showSwitchRoleDialog(BuildContext context) {
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
              final driverProvider = Provider.of<DriverProvider>(context, listen: false);
              final authService = Provider.of<AuthService>(context, listen: false);
              final String? userId = authService.currentUser?.uid;

              if (userId == null) {
                if (context.mounted) {
                  scaffoldMessenger.showSnackBar(SnackBar(content: Text(AppLocale.error_user_not_found.getString(context))));
                }
                return;
              }

              try {
                // Go offline first
                if (driverProvider.isOnline) {
                  await driverProvider.toggleOnlineStatus();
                }
                
                // Then switch role in Firestore
                await FirebaseFirestore.instance.collection('users').doc(userId).update({'role': 'Customer'});

                // Sign out to force re-authentication with the new role
                await authService.signOut();

                // Navigate to login screen using named route
                if (!context.mounted) return;
                navigator.pushNamedAndRemoveUntil('/login', (route) => false);
              } catch (e) {
                if (context.mounted) {
                    scaffoldMessenger.showSnackBar(SnackBar(content: Text("${AppLocale.failedToSwitchRole.getString(context)}: $e")));
                }
              }
            },
          ),
        ],
      ),
    );
  }

  static void switchRoleToDriver(BuildContext context, String userId) async {
    // Capture context-dependent objects before async gap
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({'role': 'Driver'});

      // Sign out to force re-authentication with the new role
      await authService.signOut();

      // After the await, check if the widget is still mounted before navigating
      if (!context.mounted) return;

      // Navigate to login screen using named route
      navigator.pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      debugPrint("Error switching role to Driver: $e");
      if (context.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('${AppLocale.failedToSwitchRole.getString(context)}: ${e.toString()}')),
        );
      }
    }
  }
}