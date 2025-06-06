// lib/map/components/map_widget.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/map_provider.dart';

class CustomMapWidget extends StatefulWidget {
  final Function(LatLng)? onMapTap;
  final bool showUserLocation;
  final bool showRoute;
  final bool showMarkers;

  const CustomMapWidget({
    this.onMapTap,
    this.showUserLocation = true,
    this.showRoute = true,
    this.showMarkers = true,
    super.key,
  });

  @override
  State<CustomMapWidget> createState() => _CustomMapWidgetState();
}

class _CustomMapWidgetState extends State<CustomMapWidget> {
  GoogleMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    final mapProvider = Provider.of<MapProvider>(context);

    return GoogleMap(
      onMapCreated: (controller) {
        _mapController = controller;
        _adjustCamera(mapProvider);
      },
      onTap: widget.onMapTap,
      myLocationEnabled: widget.showUserLocation,
      markers: widget.showMarkers ? mapProvider.markers : {},
      polylines: widget.showRoute ? mapProvider.polylines : {},
      initialCameraPosition: CameraPosition(
        target: mapProvider.currentLocation ?? const LatLng(0, 0),
        zoom: 15,
      ),
    );
  }

  void _adjustCamera(MapProvider mapProvider) {
    if (_mapController == null || mapProvider.currentLocation == null) return;
    
    final bounds = _getVisibleBounds(mapProvider);
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 100),
    );
  }

  LatLngBounds _getVisibleBounds(MapProvider mapProvider) {
    // Implementation from previous _getVisibleMapArea()
    final points = [
      mapProvider.currentLocation!,
      ...mapProvider.routePoints.cast<LatLng>(),
    ];
    
    double? x0, x1, y0, y1;
    for (final latLng in points) {
      x0 = x0 == null ? latLng.latitude : min(x0, latLng.latitude);
      x1 = x1 == null ? latLng.latitude : max(x1, latLng.latitude);
      y0 = y0 == null ? latLng.longitude : min(y0, latLng.longitude);
      y1 = y1 == null ? latLng.longitude : max(y1, latLng.longitude);
    }
    
    return LatLngBounds(
      northeast: LatLng(x1!, y1!),
      southwest: LatLng(x0!, y0!),
    );
  }
}