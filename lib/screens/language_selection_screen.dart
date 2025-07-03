import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../localization/locales.dart'; // Import your locales

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  final FlutterLocalization _localization = FlutterLocalization.instance;

  void _onLanguageChanged(String languageCode) {
    _localization.translate(languageCode);
    // The UI will rebuild automatically because FlutterLocalization uses an InheritedWidget,
    // but we call setState to ensure the checkmark updates instantly.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocale.selectLanguage.getString(context)),
      ),
      body: ListView(
        children: [
          _buildLanguageTile(context, AppLocale.english.getString(context), 'en'),
          _buildLanguageTile(context, AppLocale.swahili.getString(context), 'sw'),
        ],
      ),
    );
  }

  Widget _buildLanguageTile(BuildContext context, String languageName, String languageCode) {
    final bool isSelected = _localization.currentLocale?.languageCode == languageCode;
    return ListTile(
      title: Text(languageName),
      trailing: isSelected ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
      onTap: () => _onLanguageChanged(languageCode),
    );
  }
}