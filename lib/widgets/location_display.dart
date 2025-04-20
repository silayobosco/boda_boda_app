import 'package:flutter/material.dart';

class LocationDisplay extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool isPickup;
  final VoidCallback onClear;
  final VoidCallback onEdit;

  const LocationDisplay({
    Key? key,
    required this.label,
    required this.controller,
    required this.isPickup,
    required this.onClear,
    required this.onEdit,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            isPickup ? Icons.my_location : Icons.flag,
            color: isPickup ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: label,
                border: InputBorder.none,
              ),
              onTap: onEdit,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}