import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class LocationProvider extends ChangeNotifier {
  LatLng? _currentLocation;
  double _heading = 0.0;
  StreamSubscription<Position>? _positionStreamSubscription;

  // Public stream for other parts of the app to listen to detailed location updates.
  final StreamController<Position> _locationStreamController = StreamController<Position>.broadcast();
  Stream<Position> get locationStream => _locationStreamController.stream;

  LatLng? get currentLocation => _currentLocation;
  double get heading => _heading;

  LocationProvider() {
    // Immediately check permissions and start listening if possible.
    updateLocation();
    startRealTimeUpdates();
  }

  Future<bool> checkAndRequestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled. Don't request permission,
      // but inform the user or calling function.
      debugPrint("LocationProvider: Location services are disabled.");
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, return false.
        debugPrint("LocationProvider: Location permission denied by user.");
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint("LocationProvider: Location permission denied forever by user.");
      // Permissions are denied forever, handle appropriately.
      return false;
    }

    // Permissions are granted.
    debugPrint("LocationProvider: Location permission status: $permission");
    return permission == LocationPermission.whileInUse || permission == LocationPermission.always;
  }

  void _updatePositionData(Position position) {
    _currentLocation = LatLng(position.latitude, position.longitude);
    _heading = position.heading;
    _locationStreamController.add(position); // Broadcast the full Position object
    notifyListeners();
  }

  Future<void> updateLocation() async {
    bool permissionOK = await checkAndRequestLocationPermission();
    if (!permissionOK) {
      _currentLocation = null;
      _heading = 0; // Reset heading
      notifyListeners();
      return;
    }
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _updatePositionData(position);
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  void startRealTimeUpdates({bool batterySaver = false}) {
    _positionStreamSubscription?.cancel(); // Cancel existing stream if any
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: batterySaver ? LocationAccuracy.low : LocationAccuracy.bestForNavigation,
        distanceFilter: batterySaver ? 30 : 10,
      ),
    ).listen(_updatePositionData);
  }

  void stopRealTimeUpdates() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _locationStreamController.close();
    super.dispose();
  }
}