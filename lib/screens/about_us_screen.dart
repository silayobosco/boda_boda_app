import 'package:flutter/material.dart';
import '../utils/ui_utils.dart'; // For consistent styling

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Us'),
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
                'Boda Boda App',
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Center(
              child: Text(
                'Connecting Communities, One Ride at a Time.',
                style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor),
              ),
            ),
            verticalSpaceLarge,
            _buildSectionTitle(theme, 'Our Story'),
            verticalSpaceSmall,
            _buildParagraph(
              theme,
              'Born from the vibrant streets of our city, the Boda Boda App was created to bridge the gap between local riders and the community they serve. We saw an opportunity to use technology to empower local boda boda drivers, providing them with a stable platform to connect with customers, while offering passengers a safe, reliable, and convenient way to travel.',
            ),
            verticalSpaceLarge,
            _buildSectionTitle(theme, 'Our Mission'),
            verticalSpaceSmall,
            _buildParagraph(
              theme,
              'Our mission is to revolutionize urban transport by creating a seamless, community-focused ecosystem. We are committed to improving the livelihoods of our driver partners, ensuring passenger safety, and fostering a sense of trust and connection within the neighborhoods we operate in. We believe in fair fares, transparent operations, and building a sustainable business that benefits everyone.',
            ),
            verticalSpaceLarge,
            _buildSectionTitle(theme, 'Contact Us'),
            verticalSpaceSmall,
            _buildContactInfo(theme, Icons.email_outlined, 'vijiwe@gmail.com'),
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