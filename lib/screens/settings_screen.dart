import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:provider/provider.dart';
import '../localization/locales.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showLanguageSelectionDialog(BuildContext context) {
    final localization = FlutterLocalization.instance;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocale.selectLanguage.getString(context)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(AppLocale.english.getString(context)),
                onTap: () {
                  localization.translate('en');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: Text(AppLocale.swahili.getString(context)),
                onTap: () {
                  localization.translate('sw');
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final localization = FlutterLocalization.instance;

    String getCurrentLanguageName(BuildContext context) {
      switch (localization.currentLocale?.languageCode) {
        case 'en':
          return AppLocale.english.getString(context);
        case 'sw':
          return AppLocale.swahili.getString(context);
        default:
          return AppLocale.english.getString(context); // Fallback to English
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocale.settings.getString(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(8.0),
        children: [
          ListTile(
            title: Text(AppLocale.darkMode.getString(context)),
            trailing: Switch(
              value: themeProvider.themeMode == ThemeMode.dark,
              onChanged: (value) {
                final themeMode = value ? ThemeMode.dark : ThemeMode.light;
                themeProvider.setThemeMode(themeMode);
              },
            ),
          ),
          ListTile(
            title: Text(AppLocale.language.getString(context)),
            subtitle: Text(getCurrentLanguageName(context)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showLanguageSelectionDialog(context),
          ),
        ],
      ),
    );
  }
}