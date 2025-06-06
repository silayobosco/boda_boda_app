import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ReusableMapWidget extends StatelessWidget {
  final CameraPosition initialCameraPosition;
  final Function(GoogleMapController) onMapCreated;
  final Function(LatLng)? onTap;
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final bool myLocationEnabled;
  final EdgeInsets padding;
  final bool mapToolbarEnabled; // Add missing field
  final bool myLocationButtonEnabled; // Add missing field
  final bool zoomControlsEnabled; // Add missing field

  const ReusableMapWidget({
    super.key,
    required this.initialCameraPosition,
    required this.onMapCreated,
    this.onTap,
    this.markers = const {},
    this.polylines = const {},
    this.myLocationEnabled = false,
    this.padding = EdgeInsets.zero,
    this.zoomControlsEnabled = true, // Default to true
    this.mapToolbarEnabled = true, // Default to true
    this.myLocationButtonEnabled = true, // Default to true
  });

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      mapType: MapType.normal,
      initialCameraPosition: initialCameraPosition,
      onMapCreated: onMapCreated,
      onTap: onTap,
      markers: markers,
      polylines: polylines,
      myLocationEnabled: myLocationEnabled,
      mapToolbarEnabled: mapToolbarEnabled, // Use the defined field
      zoomControlsEnabled: zoomControlsEnabled, // Use the defined field
      myLocationButtonEnabled: myLocationButtonEnabled, // Use the defined field
    );
  }
}