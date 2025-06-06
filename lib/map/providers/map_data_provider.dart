import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapDataProvider extends ChangeNotifier {
  LatLng? _currentLocation; // Store the current location
  final List<LatLng> _markers = []; // Store markers

  // Getter for current location
  LatLng? get currentLocation => _currentLocation;

  // Getter for markers
  List<LatLng> get markers => _markers;

  // Update the current location
  void updateCurrentLocation(LatLng location) {
    _currentLocation = location;
    notifyListeners(); // Notify listeners about the change
  }

  // Add a marker
  void addMarker(LatLng marker) {
    _markers.add(marker);
    notifyListeners(); // Notify listeners about the change
  }
}