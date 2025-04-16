import 'package:flutter/material.dart';

// App Colors - Define your app's color palette here
const Color primaryColor = Colors.blue; // Main brand color
const Color secondaryColor = Colors.blueAccent; // Secondary brand color
const Color accentColor = Colors.amber; // Highlight color
const Color backgroundColor = Colors.white; // Default background color
const Color textColor = Colors.black; // Default text color
const Color hintTextColor = Colors.grey; // Hint text color
const Color errorColor = Colors.red; // Error message color

// Text Styles - Define reusable text styles for your app
TextStyle appTextStyle({
  double fontSize = 16, // Default font size
  FontWeight fontWeight = FontWeight.normal, // Default font weight
  Color color = textColor, // Default text color
  TextDecoration? decoration, // Optional text decoration (e.g., underline)
}) {
  return TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    decoration: decoration,
  );
}

TextStyle headingTextStyle({
  double fontSize = 24, // Heading font size
  FontWeight fontWeight = FontWeight.bold, // Heading font weight
  Color color = textColor, // Heading text color
}) {
  return TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
  );
}

// Box Decorations - Define reusable box decorations (e.g., backgrounds, borders)
BoxDecoration appBoxDecoration({
  Color color = backgroundColor, // Default background color
  double borderRadius = 8.0, // Default border radius
  Border? border, // Optional border
  BoxShadow? boxShadow, // Optional box shadow
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(borderRadius),
    border: border,
    boxShadow: [boxShadow ?? BoxShadow()], // Use provided boxShadow or default
  );
}

// Input Decoration - Define reusable input decorations for text fields
InputDecoration appInputDecoration({
  String? labelText, // Optional label text
  String? hintText, // Optional hint text
  Widget? prefixIcon, // Optional prefix icon
  Widget? suffixIcon, // Optional suffix icon
  String? errorText, // Optional error message
}) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    errorText: errorText,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)), // Default border
    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: primaryColor), borderRadius: BorderRadius.circular(8.0)), // Border when focused
    errorBorder: OutlineInputBorder(borderSide: BorderSide(color: errorColor), borderRadius: BorderRadius.circular(8.0)), // Border when error
  );
}

// Button Styles - Define reusable button styles
ButtonStyle appButtonStyle({
  Color backgroundColor = primaryColor, // Default button background color
  Color textColor = Colors.white, // Default button text color
}) {
  return ElevatedButton.styleFrom(
    backgroundColor: backgroundColor,
    foregroundColor: textColor,
    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15), // Button padding
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)), // Button shape
  );
}

// Spacing - Define reusable SizedBox widgets for spacing
const SizedBox verticalSpaceSmall = SizedBox(height: 8.0);
const SizedBox verticalSpaceMedium = SizedBox(height: 16.0);
const SizedBox verticalSpaceLarge = SizedBox(height: 24.0);

const SizedBox horizontalSpaceSmall = SizedBox(width: 8.0);
const SizedBox horizontalSpaceMedium = SizedBox(width: 16.0);
const SizedBox horizontalSpaceLarge = SizedBox(width: 24.0);

// Add more utility functions as needed...