import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

class Stop {
  final String name;
  final String? address;
  LatLng? location;
  final TextEditingController controller;

  Stop({
    required this.name,
    this.address,
    this.location,
  }) : controller = TextEditingController();
}