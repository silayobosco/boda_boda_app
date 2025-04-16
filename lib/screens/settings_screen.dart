import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Dark Mode'),
            Switch(
              value: themeProvider.themeMode == ThemeMode.dark,
              onChanged: (value) {
                final themeMode = value ? ThemeMode.dark : ThemeMode.light;
                themeProvider.setThemeMode(themeMode);
              },
            ),
          ],
        ),
      ),
    );
  }
}