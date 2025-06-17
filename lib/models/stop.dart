import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

class Stop {
  final String name;
  final String? address;
  LatLng? location;
  final TextEditingController controller;
  final FocusNode focusNode; // Add FocusNode

  Stop({
    required this.name,
    this.address,
    this.location,
  })  : controller = TextEditingController(text: address), // Initialize controller with address
        focusNode = FocusNode(); // Initialize FocusNode

  // Method to dispose resources
  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}