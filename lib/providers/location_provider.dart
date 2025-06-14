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

  double? get heading => _heading; // Return the internal _heading value

  Future<bool> checkAndRequestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await Geolocator.requestPermission() == LocationPermission.whileInUse || await Geolocator.requestPermission() == LocationPermission.always; // Simplified for brevity
      if (!serviceEnabled) {
        debugPrint("LocationProvider: Location services are disabled by user.");
        return false;
      }
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint("LocationProvider: Location permission denied by user.");
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint("LocationProvider: Location permission denied forever by user.");
      // Optionally, guide user to app settings
      return false;
    }

    debugPrint("LocationProvider: Location permission status: $permission");
    return permission == LocationPermission.whileInUse || permission == LocationPermission.always;
  }

  Future<void> _init() async {
    try {
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
      Position currentPosition = await Geolocator.getCurrentPosition(); // Prefer current for more accuracy
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
    bool permissionOK = await checkAndRequestLocationPermission();
    if (!permissionOK) {
      _currentLocation = null;
      _heading = 0; // Reset heading
      notifyListeners();
      return;
    }
    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _updatePositionData(LatLng(position.latitude, position.longitude), heading: position.heading);
    } catch (e) {
      debugPrint('Error updating location: $e');
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