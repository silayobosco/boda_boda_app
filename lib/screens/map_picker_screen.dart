import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';

class MapPickerScreen extends StatefulWidget {
  final LatLng initialLocation;

  const MapPickerScreen({super.key, required this.initialLocation});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late LatLng _pickedLocation;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _pickedLocation = widget.initialLocation;
  }

  void _onCameraMove(CameraPosition position) {
    // No need for setState here as we only need the final position on confirm.
    _pickedLocation = position.target;
  }

  @override
  Widget build(BuildContext context) {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Kijiwe Location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.of(context).pop(_pickedLocation),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialLocation,
              zoom: 16.0,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onCameraMove: _onCameraMove,
            myLocationEnabled: true,
            myLocationButtonEnabled: false, // We have our own UI for this
          ),
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 48.0), // Adjust to center pin point
              child: Icon(Icons.location_pin, size: 48.0, color: Colors.red),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
                onPressed: () => Navigator.of(context).pop(_pickedLocation),
                child: const Text('Confirm This Location'),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: FloatingActionButton.small(
              onPressed: () => _mapController?.animateCamera(CameraUpdate.newLatLng(
                  LatLng(locationProvider.currentLocation!.latitude, locationProvider.currentLocation!.longitude),
              )),
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}