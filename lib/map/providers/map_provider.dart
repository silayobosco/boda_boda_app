// lib/map/providers/map_provider.dart
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';

class MapProvider extends ChangeNotifier {
  LatLng? _currentLocation;
  List<latlong.LatLng> _routePoints = [];
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  LatLng? get currentLocation => _currentLocation;
  List<latlong.LatLng> get routePoints => _routePoints;
  Set<Marker> get markers => _markers;
  Set<Polyline> get polylines => _polylines;

  final LocationService _locationService = LocationService();

  MapProvider() {
    _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      _currentLocation = await _locationService.getCurrentLocation() as LatLng?;
      notifyListeners();

      _locationService.getPositionStream().listen((location) {
        _currentLocation = location as LatLng?;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Error initializing location: $e');
    }
  }

  void updateMarkers(Set<Marker> markers) {
    _markers = markers;
    notifyListeners();
  }

  void setRoutePoints(List<latlong.LatLng> points) {
    _routePoints = points;
    _updatePolylines();
    notifyListeners();
  }

  void _updatePolylines() {
    _polylines = {
      Polyline(
        polylineId: const PolylineId('route'),
        color: Colors.blue,
        width: 4,
        points: _routePoints.map((point) => LatLng(point.latitude, point.longitude)).toList(),
      ),
    };
  }
}