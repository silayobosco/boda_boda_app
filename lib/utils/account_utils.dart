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
            onPressed: () => Navigator.of(dialogContext).pop(false), // Return false when cancel is pressed
            child: Text(AppLocale.deleteAccountCancel.getString(dialogContext)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(AppLocale.deleteAccountConfirm.getString(dialogContext)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // Capture localized strings before the async gap.
        final authService = Provider.of<AuthService>(context, listen: false);
        final successMessage = AppLocale.deleteAccountSuccess.getString(context);
        final errorMessage = AppLocale.deleteAccountError.getString(context);
        final scaffoldMessenger = ScaffoldMessenger.of(context);

      //showDialog(
        //context: context,
        //barrierDismissible: false,
        //builder: (context) => const Center(child: CircularProgressIndicator()),
      //);
      try {
          final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('deleteUserAccount');
          await callable.call();

          if (!context.mounted) return; // Check if the widget is still mounted
          Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog on success

          await authService.signOut(); // Sign out after successful deletion

          if (!context.mounted) return; // Check before navigating
          Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/login', (Route<dynamic> route) => false);

          scaffoldMessenger.showSnackBar(SnackBar(content: Text(successMessage)));
      } catch (e) {
        if (!context.mounted) return; // Handle errors gracefully
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog on error
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('$errorMessage Please try again.')),
        );
      }
    }
  }

  static void showLogoutConfirmationDialog(BuildContext context, {String? userRole}) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        // It's best practice to get theme and localization from the dialog's own context.
        final theme = Theme.of(dialogContext); // Use dialogContext for theme

        // Choose the confirmation message based on the user's role.
        final String confirmationMessage = (userRole == 'Driver')
            ? AppLocale.logout_confirmation_driver.getString(dialogContext)
            : AppLocale.logout_confirmation_customer.getString(dialogContext);

        return AlertDialog(
          title: Text(AppLocale.logout.getString(dialogContext)),
          content: Text(confirmationMessage),
          actions: [
              TextButton(
              // Cancel action remains as before
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
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
                // Close confirmation dialog
                Navigator.of(dialogContext).pop();

                // Show loading indicator
                //showDialog(
                  //context: context,
                  //barrierDismissible: false,
                  //builder: (context) => const Center(child: CircularProgressIndicator()),
                //);

                // Capture context-dependent objects from the original context before the async gap
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final authService = Provider.of<AuthService>(context, listen: false);
                final errorLoggingOutMessage = AppLocale.error_logging_out.getString(context);

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

                  if (!context.mounted) return;
                  // Use root navigator for both actions to ensure dialog is dismissed before navigation
                  Navigator.of(context, rootNavigator: true).popAndPushNamed('/login');
                } catch (e) {
                    if (context.mounted) {
                    Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog
                  }
                  debugPrint("Error during logout: $e");
                  if (context.mounted) {
                    scaffoldMessenger.showSnackBar(SnackBar(content: Text('$errorLoggingOutMessage: ${e.toString()}')));
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
              // Close confirmation dialog first
              Navigator.of(dialogContext).pop();

              // Show loading indicator
              //showDialog(
                //context: context,
                //barrierDismissible: false,
                //builder: (context) => const Center(child: CircularProgressIndicator()),
              //);

              // Capture context-dependent objects before async gap
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final driverProvider = Provider.of<DriverProvider>(context, listen: false);
              final authService = Provider.of<AuthService>(context, listen: false);
              final String? userId = authService.currentUser?.uid;
              final userNotFoundMessage = AppLocale.error_user_not_found.getString(context);
              final failedToSwitchMessage = AppLocale.failedToSwitchRole.getString(context);

              if (userId == null) {
                if (context.mounted) {
                  scaffoldMessenger.showSnackBar(SnackBar(content: Text(userNotFoundMessage)));
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
                if (!context.mounted) return; // Check before navigation
                // Use root navigator for both actions
                Navigator.of(context, rootNavigator: true).popAndPushNamed('/login');
              } catch (e) {
                if (context.mounted) {
                    // Dismiss loading dialog on error
                    Navigator.of(context, rootNavigator: true).pop();
                    scaffoldMessenger.showSnackBar(SnackBar(content: Text("$failedToSwitchMessage: $e")));
                  }
              }
            },
          ),
        ],
      ),
    );
  }

  static void showSwitchToDriverDialog(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final String? userId = authService.currentUser?.uid;

      if (userId == null) {
      final userNotFoundMessage = AppLocale.error_user_not_found.getString(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userNotFoundMessage)));
      }
      return;
    }

    // Show confirmation dialog
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocale.switchToDriverTitle.getString(dialogContext)),
        content: Text(AppLocale.switchToDriverContent.getString(dialogContext)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocale.dialog_cancel.getString(dialogContext)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocale.switchToDriverConfirm.getString(dialogContext)),
              ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    // Show loading indicator
    //showDialog(
      //context: context,
      //barrierDismissible: false,
      //builder: (context) => const Center(child: CircularProgressIndicator()),
    //);

    // Capture context-dependent objects before async gap
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final failedToSwitchMessage = AppLocale.failedToSwitchRole.getString(context);

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({'role': 'Driver'});
      await authService.signOut();

      if (!context.mounted) return;
      // Use root navigator for both actions
      Navigator.of(context, rootNavigator: true).popAndPushNamed('/login');
    } catch (e) {
      debugPrint("Error switching role to Driver: $e");
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Dismiss loading dialog
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('$failedToSwitchMessage: ${e.toString()}')));
      }
    }
  }
}