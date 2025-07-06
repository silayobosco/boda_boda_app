import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/locales.dart';

/// A utility class to handle notification localization, especially in background isolates
/// where BuildContext is not available.
class NotificationLocalizationUtil {
  // This is the storage key used by the `flutter_localization` package.
  // Using it here allows us to access the user's selected language
  // from a background isolate.
  static const String _storageKey = 'flutter_localization_language_code';

  /// Gets a localized title from the notification data payload.
  ///
  /// Falls back to an empty string if the key is not found.
  static Future<String> getLocalizedTitle(Map<String, dynamic> data) async {
    final String? titleKey = data['title_loc_key'] as String?;
    final dynamic titleArgs = data['title_loc_args'];
    return getLocalizedText(titleKey, args: titleArgs);
  }

  /// Gets a localized body from the notification data payload.
  ///
  /// Falls back to an empty string if the key is not found.
  static Future<String> getLocalizedBody(Map<String, dynamic> data) async {
    final String? bodyKey = data['body_loc_key'] as String?;
    final dynamic bodyArgs = data['body_loc_args'];
    return getLocalizedText(bodyKey, args: bodyArgs);
  }

  /// Fetches the user's selected language from SharedPreferences, finds the corresponding
  /// translation for the given [key], and interpolates any [args].
  static Future<String> getLocalizedText(String? key, {dynamic args}) async {
    if (key == null) return '';

    // In a background isolate, we must read the language from storage ourselves.
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString(_storageKey) ?? 'en'; // Default to 'en'

    // Select the correct translation map based on the language code.
    final Map<String, String> translations = (langCode == 'sw') ? AppLocale.SW as Map<String, String> : AppLocale.EN as Map<String, String>;
    
    String translatedText = translations[key] ?? key; // Fallback to the key itself if no translation is found.

    // If arguments are provided, substitute them into the translated string.
    if (args != null) {
        Map<String, dynamic> arguments;
        if (args is String) {
            try {
                arguments = jsonDecode(args) as Map<String, dynamic>;
            } catch (e) {
                debugPrint("Could not parse notification loc_args: $e");
                return translatedText;
            }
        } else if (args is Map) {
            arguments = Map<String, dynamic>.from(args);
        } else {
            return translatedText;
        }

        // Replace placeholders like {name} with their values.
        arguments.forEach((placeholder, value) {
            translatedText = translatedText.replaceAll('{$placeholder}', value.toString());
        });
    }
    
    return translatedText;
  }
}