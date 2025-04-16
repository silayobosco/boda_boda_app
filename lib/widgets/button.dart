import 'package:flutter/material.dart';

class Button extends StatelessWidget {
  final Color? buttonColor;
  final Color? textColor;
  final String text;
  final VoidCallback onTap;

  const Button({
    super.key,
    this.buttonColor,
    this.textColor,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        foregroundColor: textColor,
      ),
      child: Text(text),
    );
  }
}