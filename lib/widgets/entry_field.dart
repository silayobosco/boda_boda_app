import 'package:flutter/material.dart';

class EntryField extends StatefulWidget {
  final String hintText;
  final bool obscureText;
  final TextEditingController? controller;
  final String? Function(String?)? validator;

  const EntryField({
    super.key,
    required this.hintText,
    this.obscureText = true,
    this.controller,
    this.validator,
  });

  @override
  _EntryFieldState createState() => _EntryFieldState();
}

class _EntryFieldState extends State<EntryField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();
    _obscureText = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: !_obscureText,
      decoration: InputDecoration(
        hintText: widget.hintText,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility : Icons.visibility_off,
          ),
          onPressed: () {
            setState(() {
              _obscureText = !_obscureText;
            });
          },
        ),
      ),
      validator: widget.validator,
    );
  }
}