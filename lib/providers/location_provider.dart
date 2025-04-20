import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../map/services/location_service.dart';

class LocationProvider extends ChangeNotifier {
  LatLng? _currentLocation;
  LatLng? get currentLocation => _currentLocation;
  StreamSubscription<LatLng>? _positionStream;  // Matches your LocationService return type
  LatLng? _lastKnownLocation;
  double _heading = 0;

  final LocationService _locationService = LocationService();
  final List<LatLng> _positionBuffer = [];

  LocationProvider() {
    _init();
  }

  double? get heading => null;

  Future<void> _init() async {
    try {
      // Get initial position with heading
      Position initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _updatePositionData(
        LatLng(initialPosition.latitude, initialPosition.longitude),
        heading: initialPosition.heading,
      );
      
      // Start listening to position stream
      _positionStream = _locationService.getPositionStream().listen((latLng) {
        // For heading updates, we need to get the current position again
        _updateHeadingIfNeeded(latLng);
      });
    } catch (e) {
      print('Error initializing location provider: $e');
    }
  }

  Future<void> _updateHeadingIfNeeded(LatLng newPosition) async {
    try {
      Position currentPosition = await Geolocator.getLastKnownPosition() ?? 
          await Geolocator.getCurrentPosition();
      _updatePositionData(newPosition, heading: currentPosition.heading);
    } catch (e) {
      // If we can't get heading, just update position
      _updatePositionData(newPosition);
    }
  }

  void _updatePositionData(LatLng position, {double? heading}) {
    _currentLocation = position;
    _lastKnownLocation = position;
    if (heading != null) {
      _heading = heading;
    }
    notifyListeners();
    _updateDriverPositionOnServer();
  }

  Future<void> updateLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      _updatePositionData(
        LatLng(position.latitude, position.longitude),
        heading: position.heading,
      );
    } catch (e) {
      print('Error updating location: $e');
    }
  }

  void startRealTimeUpdates({bool batterySaver = false}) {
    _positionStream?.cancel(); // Cancel existing stream if any
    _positionStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: batterySaver ? LocationAccuracy.low : LocationAccuracy.bestForNavigation,
        distanceFilter: batterySaver ? 30 : 10,
      ),
    ).map((position) => LatLng(position.latitude, position.longitude))
     .listen((latLng) => _updateHeadingIfNeeded(latLng));
  }

  void stopRealTimeUpdates() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  void _updateDriverPositionOnServer() async {
    if (_lastKnownLocation == null) return;
    
    _positionBuffer.add(_lastKnownLocation!);
    
    if (_positionBuffer.length > 5) {
      try {
        // await api.sendPositionBatch(_positionBuffer);
        _positionBuffer.clear();
      } catch (e) {
        // Retry later
      }
    }
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }
}