import 'package:flutter/material.dart';
import '../utils/ui_utils.dart'; // For consistent styling

class HelpAndSupportScreen extends StatelessWidget {
  const HelpAndSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(theme, 'Frequently Asked Questions'),
            verticalSpaceMedium,
            _buildFaqItem(
              theme: theme,
              question: 'How do I request a ride?',
              answer:
                  'To request a ride, go to the home screen, enter your destination in the "Where to?" box, confirm your pickup location, and then tap "Confirm Route".',
            ),
            _buildFaqItem(
              theme: theme,
              question: 'How is the fare calculated?',
              answer:
                  'Fares are calculated based on a base fare, the distance of the ride, and the estimated time it will take. You will see an estimated fare before you confirm your request.',
            ),
            _buildFaqItem(
              theme: theme,
              question: 'Can I schedule a ride in advance?',
              answer:
                  'Yes! After setting your pickup and destination, you can tap the "Schedule" button to pick a future date and time for your ride.',
            ),
            _buildFaqItem(
              theme: theme,
              question: 'How do I become a driver?',
              answer:
                  'From the side menu, you can select "Become a Driver" to start the registration process. You will need to provide your vehicle details and necessary documents.',
            ),
            verticalSpaceLarge,
            _buildSectionTitle(theme, 'Contact Support'),
            verticalSpaceMedium,
            _buildContactInfo(theme, Icons.email_outlined, 'Email Support',
                'vijiweapp@gmail.com'),
            verticalSpaceSmall,
            _buildContactInfo(
                theme, Icons.phone_outlined, 'Call Us', '+255 717 553 937'),
            verticalSpaceSmall,
            _buildContactInfo(theme, Icons.chat_bubble_outline, 'Live Chat',
                'Tap to start a chat with support.'),
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

  Widget _buildFaqItem(
      {required ThemeData theme,
      required String question,
      required String answer}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(question,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        childrenPadding: const EdgeInsets.all(16).copyWith(top: 0),
        children: [
          Text(answer, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildContactInfo(
      ThemeData theme, IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.secondary),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      onTap: () {
        // TODO: Implement contact actions (e.g., launch email, phone dialer, or chat screen)
      },
    );
  }
}