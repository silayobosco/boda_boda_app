import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../localization/locales.dart';
import '../screens/about_us_screen.dart';
import '../screens/help_and_support_screen.dart';
import '../screens/language_selection_screen.dart';
import '../screens/legal_and_privacy_screen.dart';
import '../utils/ui_utils.dart';

class SharedAccountOptions extends StatelessWidget {
  final String userRole;
  const SharedAccountOptions({super.key, required this.userRole});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              MaterialPageRoute(builder: (context) => HelpAndSupportScreen(userRole: userRole)));
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
            MaterialPageRoute(builder: (context) => LegalAndPrivacyScreen(userRole: userRole)),
          );
        }),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildAccountOption(BuildContext context, IconData icon, String title, VoidCallback onTap) {
    final theme = Theme.of(context);
    return ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        onTap: onTap,
        contentPadding: EdgeInsets.zero);
  }
}