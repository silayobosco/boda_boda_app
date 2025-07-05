import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../localization/locales.dart';
import '../utils/ui_utils.dart'; // For consistent styling

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocale.aboutUs.getString(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Image.asset(
                'assets/icon.png', // Assuming you have a logo here
                height: 100,
              ),
            ),
            verticalSpaceMedium,
            Center(
              child: Text(
                AppLocale.appName.getString(context),
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Center(
              child: Text(
                AppLocale.appTagline.getString(context),
                style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor),
              ),
            ),
            verticalSpaceLarge,
            _buildSectionTitle(theme, AppLocale.ourStory.getString(context)),
            verticalSpaceSmall,
            _buildParagraph(
              theme,
              AppLocale.ourStoryParagraph.getString(context),
            ),
            verticalSpaceLarge,
            _buildSectionTitle(theme, AppLocale.ourMission.getString(context)),
            verticalSpaceSmall,
            _buildParagraph(
              theme,
              AppLocale.ourMissionParagraph.getString(context),
            ),
            verticalSpaceLarge,
            _buildSectionTitle(theme, AppLocale.contactUs.getString(context)),
            verticalSpaceSmall,
            _buildContactInfo(theme, Icons.email_outlined, 'vijiweapp@gmail.com'),
            verticalSpaceSmall,
            _buildContactInfo(theme, Icons.phone_outlined, '+255 717 553 937'),
            verticalSpaceSmall,
            _buildContactInfo(theme, Icons.location_on_outlined, 'jitegemee, mabibo, Dar es Salaam, Tanzania'),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildParagraph(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
      textAlign: TextAlign.justify,
    );
  }

  Widget _buildContactInfo(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.secondary, size: 20),
        horizontalSpaceMedium,
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}