import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart'; // Replace with your actual import

class LocationProvider extends ChangeNotifier {
  LatLng? _currentLocation;
  LatLng? get currentLocation => _currentLocation;

  final LocationService _locationService = LocationService();

  LocationProvider() {
    _init();
  }

  Future<void> _init() async {
    try {
      _currentLocation = await _locationService.getCurrentLocation();
      notifyListeners();

      // Start listening to location stream
      _locationService.getPositionStream().listen((LatLng location) {
        _currentLocation = location;
        notifyListeners();
      });
    } catch (e) {
      print('Error initializing location provider: $e');
    }
  }

  Future<void> updateLocation() async {
    try {
      _currentLocation = await _locationService.getCurrentLocation();
      notifyListeners();
    } catch (e) {
      print('Error updating location: $e');
    }
  }
}