import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:provider/provider.dart';
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
              _buildAccountOption(context, Icons.delete_forever, AppLocale.deleteAccount.getString(context),
                  () => AccountUtils.showDeleteAccountDialog(context), isDestructive: true),
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
}