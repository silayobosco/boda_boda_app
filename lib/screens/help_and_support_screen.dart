import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../localization/locales.dart';
import '../utils/ui_utils.dart'; // For consistent styling

class HelpAndSupportScreen extends StatelessWidget {
  final String userRole;

  const HelpAndSupportScreen({super.key, required this.userRole});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocale.help_and_support.getString(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, theme, AppLocale.faq),
            verticalSpaceMedium,
            // Conditionally display FAQs based on the user's role
            if (userRole == 'Driver')
              ..._getDriverFaqs(context, theme)
            else
              ..._getCustomerFaqs(context, theme),
            verticalSpaceLarge,
            _buildSectionTitle(context, theme, AppLocale.contact_support),
            verticalSpaceMedium,
            _buildContactInfo(context, theme, Icons.email_outlined, AppLocale.email_support,
                'vijiweapp@gmail.com'),
            verticalSpaceSmall,
            _buildContactInfo(
                context, theme, Icons.phone_outlined, AppLocale.call_us, '+255 717 553 937'),
            verticalSpaceSmall,
            _buildContactInfo(context, theme, Icons.chat_bubble_outline, AppLocale.live_chat,
                AppLocale.live_chat_subtitle),
          ],
        ),
      ),
    );
  }

  List<Widget> _getCustomerFaqs(BuildContext context, ThemeData theme) {
    return [
      _buildFaqItem(
        context: context,
        theme: theme,
        questionKey: AppLocale.customer_faq1_q,
        answerKey: AppLocale.customer_faq1_a,
      ),
      _buildFaqItem(
        context: context,
        theme: theme,
        questionKey: AppLocale.customer_faq2_q,
        answerKey: AppLocale.customer_faq2_a,
      ),
      _buildFaqItem(
        context: context,
        theme: theme,
        questionKey: AppLocale.customer_faq3_q,
        answerKey: AppLocale.customer_faq3_a,
      ),
      _buildFaqItem(
        context: context,
        theme: theme,
        questionKey: AppLocale.customer_faq4_q,
        answerKey: AppLocale.customer_faq4_a,
      ),
    ];
  }

  List<Widget> _getDriverFaqs(BuildContext context, ThemeData theme) {
    return [
      _buildFaqItem(
          context: context,
          theme: theme,
          questionKey: AppLocale.driver_faq1_q,
          answerKey: AppLocale.driver_faq1_a),
      _buildFaqItem(
          context: context,
          theme: theme,
          questionKey: AppLocale.driver_faq2_q,
          answerKey: AppLocale.driver_faq2_a),
      _buildFaqItem(
          context: context,
          theme: theme,
          questionKey: AppLocale.driver_faq3_q,
          answerKey: AppLocale.driver_faq3_a),
    ];
  }

  Widget _buildSectionTitle(BuildContext context, ThemeData theme, String titleKey) {
    return Text(
      titleKey.getString(context),
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildFaqItem(
      {required BuildContext context,
      required ThemeData theme,
      required String questionKey,
      required String answerKey}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(questionKey.getString(context),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        childrenPadding: const EdgeInsets.all(16).copyWith(top: 0),
        children: [
          Text(answerKey.getString(context), style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildContactInfo(
      BuildContext context, ThemeData theme, IconData icon, String titleKey, String subtitleValue) {
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.secondary),
      title: Text(titleKey.getString(context), style: theme.textTheme.titleMedium),
      subtitle: Text(
        // Check if the subtitle is a key or a literal value
        subtitleValue.contains('@') || subtitleValue.contains('+')
            ? subtitleValue
            : subtitleValue.getString(context),
        style: theme.textTheme.bodySmall
      ),
      onTap: () async {
        Uri? uri;
        if (titleKey == AppLocale.email_support) {
          uri = Uri.parse('mailto:$subtitleValue');
        } else if (titleKey == AppLocale.call_us) {
          uri = Uri.parse('tel:$subtitleValue');
        }
        // Add live chat navigation later

        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          debugPrint("Could not launch $uri");
        }
      },
    );
  }
}