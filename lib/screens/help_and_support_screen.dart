import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/ui_utils.dart'; // For consistent styling

class HelpAndSupportScreen extends StatelessWidget {
  final String userRole;

  const HelpAndSupportScreen({super.key, required this.userRole});

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
            // Conditionally display FAQs based on the user's role
            if (userRole == 'Driver')
              ..._getDriverFaqs(theme)
            else
              ..._getCustomerFaqs(theme),
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

  List<Widget> _getCustomerFaqs(ThemeData theme) {
    return [
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
    ];
  }

  List<Widget> _getDriverFaqs(ThemeData theme) {
    return [
      _buildFaqItem(
          theme: theme,
          question: 'How do I go online to receive requests?',
          answer: 'On the driver home screen, tap the "Go Online" button. You must be part of a Kijiwe to receive ride requests.'),
      _buildFaqItem(
          theme: theme,
          question: 'How are my earnings calculated?',
          answer: 'Your earnings are the final fare minus the app\'s commission. You can view a detailed breakdown of your earnings for each ride in the "Earnings" section of your account.'),
      _buildFaqItem(
          theme: theme,
          question: 'What happens if I decline a ride request?',
          answer: 'Declining a ride will make you unavailable for a short period. Frequent declines may affect your driver score. The request will be sent to the next available driver in the queue.'),
    ];
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
      onTap: () async {
        Uri? uri;
        if (title.toLowerCase().contains('email')) {
          uri = Uri.parse('mailto:$subtitle');
        } else if (title.toLowerCase().contains('call')) {
          uri = Uri.parse('tel:$subtitle');
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