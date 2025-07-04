import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:provider/provider.dart';

import '../localization/locales.dart';
import '../services/auth_service.dart';

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
}