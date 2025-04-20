import '../utils/ui_utils.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemes {
  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: backgroundColor,
      background: backgroundColor,
      error: errorColor,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textColor,
      onBackground: textColor,
      onError: Colors.white,
      surfaceVariant: Colors.grey[100], // For subtle backgrounds like field containers
      outline: Colors.grey[400], // For borders
    ),
    primaryColor: primaryColor, // Still useful for direct access
    scaffoldBackgroundColor: backgroundColor, // Use scheme.background
    textTheme: TextTheme(
      // Use appTextStyle for consistency, but could define directly
      titleLarge: headingTextStyle(color: textColor), // For screen titles
      bodyLarge: appTextStyle(color: textColor), // Default body text
      bodyMedium: appTextStyle(fontSize: 14, color: Colors.black87), // Smaller body text
      labelLarge: appTextStyle(color: Colors.white), // For buttons
      bodySmall: appTextStyle(fontSize: 12, color: hintTextColor), // Hint/caption text
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white, // Icon/Title color
      titleTextStyle: headingTextStyle(color: Colors.white, fontSize: 20),
    ),
    iconTheme: IconThemeData(
      color: textColor, // Default icon color
      size: 24.0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      // Use appInputDecoration defaults or define here
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: BorderSide(color: Colors.grey[400]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: primaryColor, width: 2.0),
        borderRadius: BorderRadius.circular(8.0),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: errorColor, width: 1.0),
        borderRadius: BorderRadius.circular(8.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: errorColor, width: 2.0),
        borderRadius: BorderRadius.circular(8.0),
      ),
      hintStyle: appTextStyle(color: hintTextColor),
      labelStyle: appTextStyle(color: textColor),
      floatingLabelStyle: appTextStyle(color: primaryColor), // Label when focused
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: appButtonStyle(), // Uses primaryColor by default
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: BorderSide(color: primaryColor),
        textStyle: appTextStyle(fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: secondaryColor, // Use accent for primary in dark? Or keep primaryColor? Let's try secondary.
      secondary: accentColor,
      surface: Colors.grey[850]!,
      background: Colors.grey[900]!,
      error: errorColor,
      onPrimary: Colors.black, // Text on secondaryColor
      onSecondary: Colors.black, // Text on accentColor
      onSurface: Colors.white,
      onBackground: Colors.white,
      onError: Colors.black,
      surfaceVariant: Colors.grey[800], // For subtle backgrounds
      outline: Colors.grey[600], // For borders
    ),
    primaryColor: secondaryColor,
    scaffoldBackgroundColor: Colors.grey[900]!, // Use scheme.background
    textTheme: TextTheme(
      titleLarge: headingTextStyle(color: Colors.white),
      bodyLarge: appTextStyle(color: Colors.white),
      bodyMedium: appTextStyle(fontSize: 14, color: Colors.white70),
      labelLarge: appTextStyle(color: Colors.black), // Text on dark theme buttons
      bodySmall: appTextStyle(fontSize: 12, color: Colors.grey[400] ?? Colors.grey),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.grey[850]!,
      foregroundColor: Colors.white,
      titleTextStyle: headingTextStyle(color: Colors.white, fontSize: 20),
    ),
    iconTheme: IconThemeData(
      color: Colors.white, // Default icon color
      size: 24.0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.0),
        borderSide: BorderSide(color: Colors.grey[600]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: secondaryColor, width: 2.0),
        borderRadius: BorderRadius.circular(8.0),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: errorColor, width: 1.0),
        borderRadius: BorderRadius.circular(8.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: errorColor, width: 2.0),
        borderRadius: BorderRadius.circular(8.0),
      ),
      hintStyle: appTextStyle(color: Colors.grey[400]!),
      labelStyle: appTextStyle(color: Colors.white),
      floatingLabelStyle: appTextStyle(color: secondaryColor), // Label when focused
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: appButtonStyle(backgroundColor: secondaryColor, textColor: Colors.black), // Adjust text color for contrast
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: secondaryColor,
        side: BorderSide(color: secondaryColor),
        textStyle: appTextStyle(fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      ),
    ),
  );
}

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode themeMode) async {
    _themeMode = themeMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', themeMode.toString());
  }

  Future<void> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeString = prefs.getString('themeMode');
    if (themeModeString != null) {
      _themeMode = ThemeMode.values.firstWhere((e) => e.toString() == themeModeString);
      notifyListeners();
    }
  }
}