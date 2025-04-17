import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  _CustomerHomeState createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> with AutomaticKeepAliveClientMixin {
  GoogleMapController? _mapController;
  ll.LatLng? _pickupLocation;
  ll.LatLng? _dropOffLocation;
  final Set<Marker> _markers = {};
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  List<Map<String, dynamic>> _destinationSuggestions = [];
  List<Map<String, dynamic>> _pickupSuggestions = [];
  bool _selectingPickup = false;
  bool _editingPickup = false;
  final String _googlePlacesApiKey = 'AIzaSyCkKD8FP-r9bqi5O-sOjtuksT-0Dr9dgeg';
  final FocusNode _destinationFocusNode = FocusNode();
  final FocusNode _pickupFocusNode = FocusNode();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializePickupLocation();
    _destinationFocusNode.addListener(_onDestinationFocusChange);
    _pickupFocusNode.addListener(_onPickupFocusChange);
  }

  void _onDestinationFocusChange() {
    if (_destinationFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 300), () {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _onPickupFocusChange() {
    if (_pickupFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 300), () {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _initializePickupLocation() async {
    final currentLocation = Provider.of<LocationProvider>(context, listen: false).currentLocation;
    if (currentLocation != null) {
      _pickupLocation = currentLocation;
      _updateGooglePickupMarker(LatLng(currentLocation.latitude, currentLocation.longitude));
      await _reverseGeocode(_pickupLocation!, _pickupController);
    } else {
      print('Current location not immediately available.');
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _destinationFocusNode.dispose();
    _pickupFocusNode.dispose();
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

  Future<List<Map<String, dynamic>>> _getGooglePlacesSuggestions(String query) async {
    if (query.isEmpty) {
      return [];
    }

    final apiKey = _googlePlacesApiKey;
    final baseUrl = 'https://maps.googleapis.com/maps/api/place/autocomplete/json';
    final locationBias = _pickupLocation != null
        ? 'circle:2000@${_pickupLocation!.latitude},${_pickupLocation!.longitude}'
        : null;
    String url = '$baseUrl?input=$query&key=$apiKey';
    if (locationBias != null) {
      url += '&locationbias=$locationBias';
    }

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          return (data['predictions'] as List)
              .map((p) => {
                    'place_id': p['place_id'],
                    'description': p['description'],
                  })
              .toList();
        } else {
          print('Google Places Autocomplete API Error: ${data['status']} - ${data['error_message']}');
          return [];
        }
      } else {
        print('HTTP Error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error fetching Google Places suggestions: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> _getPlaceDetails(String placeId) async {
    final apiKey = _googlePlacesApiKey;
    final baseUrl = 'https://maps.googleapis.com/maps/api/place/details/json';
    final fields = 'geometry';
    final url = '$baseUrl?place_id=$placeId&fields=$fields&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['result'] != null) {
          final geometry = data['result']['geometry']['location'];
          return {
            'latitude': geometry['lat'],
            'longitude': geometry['lng'],
          };
        } else {
          print('Google Places Details API Error: ${data['status']} - ${data['error_message']}');
          return null;
        }
      } else {
        print('HTTP Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching Google Place details: $e');
      return null;
    }
  }

  Widget _buildPickupLocationDisplay() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: Colors.green, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _pickupController.text.isNotEmpty 
                  ? _pickupController.text 
                  : 'Getting current location...',
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _editingPickup = true;
              });
              Future.delayed(const Duration(milliseconds: 50), () {
                _pickupFocusNode.requestFocus();
              });
            },
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupLocationInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Pickup Location',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _pickupController,
          focusNode: _pickupFocusNode,
          decoration: InputDecoration(
            labelText: 'Search pickup location',
            prefixIcon: const Icon(Icons.location_on, color: Colors.green),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pickupController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _pickupController.clear();
                      setState(() {
                        _pickupSuggestions = [];
                      });
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.map),
                  onPressed: _editPickupLocation,
                ),
              ],
            ),
          ),
          style: const TextStyle(color: Colors.black),
          onChanged: (value) async {
            if (value.isNotEmpty) {
              final suggestions = await _getGooglePlacesSuggestions(value);
              setState(() {
                _pickupSuggestions = suggestions;
              });
            } else {
              setState(() {
                _pickupSuggestions = [];
              });
            }
          },
        ),
        if (_pickupSuggestions.isNotEmpty)
          ..._buildSuggestionList(_pickupSuggestions, true),
      ],
    );
  }

  List<Widget> _buildSuggestionList(List<Map<String, dynamic>> suggestions, bool isPickup) {
    return [
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: suggestions.length,
          itemBuilder: (context, index) {
            final suggestion = suggestions[index];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.location_on, size: 20),
              title: Text(
                suggestion['description'] ?? '',
                style: const TextStyle(fontSize: 14),
              ),
              onTap: () async {
                final placeDetails = await _getPlaceDetails(suggestion['place_id']);
                if (placeDetails != null) {
                  final latLng = ll.LatLng(placeDetails['latitude'], placeDetails['longitude']);
                  if (isPickup) {
                    setState(() {
                      _pickupLocation = latLng;
                      _updateGooglePickupMarker(LatLng(latLng.latitude, latLng.longitude));
                      _pickupController.text = suggestion['description'] ?? '';
                      _pickupSuggestions = [];
                      _editingPickup = false;
                    });
                    _reverseGeocode(_pickupLocation!, _pickupController);
                  } else {
                    setState(() {
                      _dropOffLocation = latLng;
                      _updateGoogleDropOffMarker(LatLng(latLng.latitude, latLng.longitude));
                      _destinationController.text = suggestion['description'] ?? '';
                      _destinationSuggestions = [];
                    });
                    _reverseGeocode(_dropOffLocation!, _destinationController);
                  }
                }
              },
            );
          },
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final locationProvider = Provider.of<LocationProvider>(context);

    if (locationProvider.currentLocation == null && _pickupController.text.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final initialCameraPosition = locationProvider.currentLocation != null
        ? CameraPosition(
            target: LatLng(
              locationProvider.currentLocation!.latitude,
              locationProvider.currentLocation!.longitude,
            ),
            zoom: 15.0,
          )
        : const CameraPosition(target: LatLng(0, 0), zoom: 2);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          GoogleMap(
            key: const PageStorageKey<String>('customerMap'),
            initialCameraPosition: initialCameraPosition,
            onMapCreated: (GoogleMapController controller) async {
              _mapController = controller;
            },
            onTap: _handleMapTapForGoogleMaps,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            markers: _markers,
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.25,
            maxChildSize: 0.9,
            snap: true,
            snapSizes: const [0.35, 0.7, 0.9],
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
                child: CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _editingPickup 
                                ? _buildPickupLocationInput()
                                : _buildPickupLocationDisplay(),

                            const SizedBox(height: 16),
                            
                            const Text(
                              'Where to?',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _destinationController,
                              focusNode: _destinationFocusNode,
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
                              onChanged: (value) async {
                                if (value.isNotEmpty) {
                                  final suggestions = await _getGooglePlacesSuggestions(value);
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
                          ],
                        ),
                      ),
                    ),
                    
                    if (_destinationSuggestions.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: _buildSuggestionList(_destinationSuggestions, false),
                          ),
                        ),
                      ),
                    
                    if (_destinationSuggestions.isEmpty && _destinationController.text.isEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              const Text(
                                'Recent Destinations',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.history, size: 20),
                                title: const Text('Previous Location 1'),
                              ),
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.history, size: 20),
                                title: const Text('Another Place'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    if (_dropOffLocation != null && _pickupLocation != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pickup: ${_pickupController.text}', 
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text('Destination: ${_destinationController.text}', 
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => print('Add stop pressed'),
                                      icon: const Icon(Icons.add_location_alt),
                                      label: const Text('Add Stop'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => print('Schedule ride pressed'),
                                      icon: const Icon(Icons.schedule),
                                      label: const Text('Schedule'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () => print('Requesting ride'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                  ),
                                  child: const Text('Request Ride', style: TextStyle(fontSize: 18)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    if (_dropOffLocation == null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: const Text(
                            'Select your destination to see pickup options and request a ride.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    
                    const SliverToBoxAdapter(child: SizedBox(height: 50)),
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