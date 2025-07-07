import 'package:flutter/material.dart';

/// Builds a styled section title for account screens.
Widget buildAccountSectionTitle(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
  );
}

/// Builds a styled ListTile for account screen options.
Widget buildAccountOption(BuildContext context, IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
  final theme = Theme.of(context);
  final color = isDestructive ? theme.colorScheme.error : theme.colorScheme.primary;

  return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: isDestructive ? theme.colorScheme.error : null)),
      onTap: onTap,
      contentPadding: EdgeInsets.zero);
}