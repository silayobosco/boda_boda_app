import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../localization/locales.dart';
import '../utils/ui_utils.dart';

class LegalAndPrivacyScreen extends StatelessWidget {
  final String userRole;

  const LegalAndPrivacyScreen({super.key, required this.userRole});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocale.legalPrivacy.getString(context)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: userRole == 'Driver'
              ? _getDriverPolicy(context, theme)
              : _getCustomerPolicy(context, theme),
        ),
      ),
    );
  }

  List<Widget> _getCustomerPolicy(BuildContext context, ThemeData theme) {
    return [
      _buildSection(context, theme, AppLocale.termsOfService, AppLocale.customerTerms),
      verticalSpaceLarge,
      _buildSection(context, theme, AppLocale.privacyPolicy, AppLocale.customerPrivacy),
    ];
  }

  List<Widget> _getDriverPolicy(BuildContext context, ThemeData theme) {
    return [
      _buildSection(context, theme, AppLocale.termsOfService, AppLocale.driverTerms),
      verticalSpaceLarge,
      _buildSection(context, theme, AppLocale.privacyPolicy, AppLocale.driverPrivacy),
    ];
  }

  Widget _buildSection(BuildContext context, ThemeData theme, String titleKey, String contentKey) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titleKey.getString(context),
          style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
        ),
        verticalSpaceSmall,
        Text(contentKey.getString(context), style: theme.textTheme.bodyMedium),
      ],
    );
  }
}