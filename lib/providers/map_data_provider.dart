import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class MapDataProvider extends ChangeNotifier {
  List<MarkerData> _markers = [];
  List<MarkerData> get markers => _markers;

  List<LatLng> _routePoints = [];
  List<LatLng> get routePoints => _routePoints;

  void addMarker(MarkerData marker) {
    _markers.add(marker);
    notifyListeners();
  }

  void setRoutePoints(List<LatLng> points) {
    _routePoints = points;
    notifyListeners();
  }

  void clearMarkers() {
    _markers.clear();
    notifyListeners();
  }

  void clearRoutePoints() {
    _routePoints.clear();
    notifyListeners();
  }
}

class MarkerData {
  final LatLng point;
  final Widget builder;

  MarkerData({required this.point, required this.builder});
}