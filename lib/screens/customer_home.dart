import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // Import Google Maps
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import '../providers/map_data_provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  _CustomerHomeState createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> with AutomaticKeepAliveClientMixin {
  GoogleMapController? _mapController; // Use GoogleMapController
  ll.LatLng? _pickupLocation;
  ll.LatLng? _dropOffLocation;
  final Set<Marker> _markers = {}; // Use Marker for Google Maps
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  List<Map<String, dynamic>> _destinationSuggestions = [];
  bool _selectingPickup = false;
  final String _mapboxAccessToken = 'pk.eyJ1IjoidmlqaXdlYXBwIiwiYSI6ImNtOHQ0bzZvdTA2NW4ya3IxOWltb295ZGQifQ.THPBBXLJCaMsHCv5HQnc4Q'; // Replace with your Mapbox token

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final currentLocation = Provider.of<LocationProvider>(context, listen: false).currentLocation;
    if (currentLocation != null) {
      _pickupLocation = currentLocation;
      _updateGooglePickupMarker(LatLng(currentLocation.latitude, currentLocation.longitude)); // Use Google Maps LatLng
      _reverseGeocode(_pickupLocation!, _pickupController);
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _reverseGeocode(ll.LatLng location, TextEditingController controller) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty) {
        final Placemark place = placemarks.first;
        controller.text = '${place.street}, ${place.locality}, ${place.administrativeArea}';
      } else {
        controller.text = 'Address not found';
      }
    } catch (e) {
      print('Error reverse geocoding: $e');
      controller.text = 'Finding address...';
    }
  }

  void _updateGooglePickupMarker(LatLng location) {
    setState(() {
      _markers.removeWhere((marker) => marker.markerId == const MarkerId('pickup'));
      _markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: location,
          infoWindow: const InfoWindow(title: 'Pickup'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    });
    _mapController?.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: location, zoom: 15),
    ));
  }

  void _updateGoogleDropOffMarker(LatLng? location) {
    if (location != null) {
      setState(() {
        _markers.removeWhere((marker) => marker.markerId == const MarkerId('dropoff'));
        _markers.add(
          Marker(
            markerId: const MarkerId('dropoff'),
            position: location,
            infoWindow: const InfoWindow(title: 'Drop-off'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );
      });
    } else {
      setState(() {
        _markers.removeWhere((marker) => marker.markerId == const MarkerId('dropoff'));
      });
    }
  }

  void _handleMapTapForGoogleMaps(LatLng tappedLatLng) async {
    final llTappedLatLng = ll.LatLng(tappedLatLng.latitude, tappedLatLng.longitude);

    if (_selectingPickup) {
      setState(() {
        _pickupLocation = llTappedLatLng;
        _updateGooglePickupMarker(tappedLatLng);
        _reverseGeocode(_pickupLocation!, _pickupController);
        _selectingPickup = false;
      });
    } else if (_dropOffLocation == null) {
      setState(() {
        _dropOffLocation = llTappedLatLng;
        _updateGoogleDropOffMarker(tappedLatLng);
        _reverseGeocode(_dropOffLocation!, _destinationController);
      });
    }
  }

  void _clearPickupSelection() {
    setState(() {
      _pickupLocation = null;
      _markers.removeWhere((marker) => marker.markerId == const MarkerId('pickup'));
      _pickupController.clear();
    });
  }

  void _clearDropOffSelection() {
    setState(() {
      _dropOffLocation = null;
      _markers.removeWhere((marker) => marker.markerId == const MarkerId('dropoff'));
      _destinationController.clear();
    });
  }

  void _editPickupLocation() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tap on the map to select a new pickup location.')),
    );
    _selectingPickup = true;
  }

  Future<List<Map<String, dynamic>>> _getMapboxSuggestions(String query, ll.LatLng? proximity) async {
    final baseUrl = 'https://api.mapbox.com/geocoding/v5/mapbox.places/';
    final endpoint = Uri.encodeFull('$query.json');
    String url = '$baseUrl$endpoint?access_token=$_mapboxAccessToken';

    if (proximity != null) {
      url += '&proximity=${proximity.longitude},${proximity.latitude}';
    }

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['features'] as List).map((feature) {
        return {
          'place_name': feature['place_name'],
          'coordinates': (feature['geometry']['coordinates'] as List).cast<double>().reversed.toList(),
        };
      }).toList();
    } else {
      print('Mapbox Geocoding API Error: ${response.statusCode} - ${response.body}');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final locationProvider = Provider.of<LocationProvider>(context);
    final mapDataProvider = Provider.of<MapDataProvider>(context);

    if (locationProvider.currentLocation == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final initialCameraPosition = CameraPosition(
      target: LatLng(
        locationProvider.currentLocation!.latitude,
        locationProvider.currentLocation!.longitude,
      ),
      zoom: 15.0,
    );

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap( // Use GoogleMap
            key: const PageStorageKey<String>('customerMap'),
            initialCameraPosition: initialCameraPosition,
            onMapCreated: (GoogleMapController controller) async { // Use GoogleMapController
              _mapController = controller;
            },
            onTap: _handleMapTapForGoogleMaps, // Use the Google Maps tap handler
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            markers: _markers, // Use the Google Maps markers set
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.3,
            minChildSize: 0.3,
            maxChildSize: 0.7,
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 10,
                      color: Colors.grey,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Where to?',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _destinationController,
                      decoration: InputDecoration(
                        labelText: 'Choose Destination',
                        prefixIcon: const Icon(Icons.flag, color: Colors.red),
                        suffixIcon: _dropOffLocation != null
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: _clearDropOffSelection,
                              )
                            : null,
                      ),
                      style: const TextStyle(color: Colors.black),
                      onTap: () {
                        // Implement logic to open a full-screen search or map selection for destination
                      },
                      onChanged: (value) async {
                        if (value.isNotEmpty) {
                          final currentLocation = Provider.of<LocationProvider>(context, listen: false).currentLocation;
                          final suggestions = await _getMapboxSuggestions(
                            value,
                            ll.LatLng(currentLocation!.latitude, currentLocation.longitude),
                          );
                          setState(() {
                            _destinationSuggestions = suggestions;
                          });
                        } else {
                          setState(() {
                            _destinationSuggestions = [];
                          });
                        }
                      },
                    ),
                    if (_destinationSuggestions.isNotEmpty)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _destinationSuggestions.length,
                        itemBuilder: (context, index) {
                          final suggestion = _destinationSuggestions[index];
                          return ListTile(
                            leading: const Icon(Icons.location_on),
                            title: Text(suggestion['place_name'] ?? ''),
                            onTap: () {
                              final coordinates = suggestion['coordinates'] as List<double>;
                              final latLng = ll.LatLng(coordinates[0], coordinates[1]);
                              setState(() {
                                _dropOffLocation = latLng;
                                _updateGoogleDropOffMarker(LatLng(latLng.latitude, latLng.longitude));
                                _destinationController.text = suggestion['place_name'] ?? '';
                                _destinationSuggestions = [];
                              });
                              _reverseGeocode(_dropOffLocation!, _destinationController);
                            },
                          );
                        },
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _pickupController,
                      decoration: InputDecoration(
                        labelText: 'Pickup Location',
                        prefixIcon: const Icon(Icons.location_on, color: Colors.green),
                        suffixIcon: _pickupLocation != null
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: _clearPickupSelection,
                              )
                            : null,
                      ),
                      style: const TextStyle(color: Colors.black),
                      onTap: _editPickupLocation,
                    ),
                    const SizedBox(height: 24),
                    if (_dropOffLocation != null && _pickupLocation != null)
                      ElevatedButton(
                        onPressed: () {
                          // Request a ride logic
                          print('Requesting ride from $_pickupLocation to $_dropOffLocation');
                          // Implement your ride request submission here
                        },
                        child: const Text('Request Ride'),
                      ),
                    if (_dropOffLocation == null)
                      const Text(
                        'Select your destination to request a ride.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    const SizedBox(height: 50),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}