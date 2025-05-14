import 'package:boda_boda/models/Ride_Request_Model.dart';
import 'package:boda_boda/providers/ride_request_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart'; // Import GeoPoint from cloud_firestore
import 'dart:convert';
import '../models/stop.dart';
import '../utils/ui_utils.dart'; // Import ui_utils
class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  _CustomerHomeState createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> with AutomaticKeepAliveClientMixin {
  // Map and Location Variables
  GoogleMapController? _mapController;
  String? _routeDistance;
  String? _routeDuration;
  ll.LatLng? _pickupLocation;
  ll.LatLng? _dropOffLocation;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  
  // Search and Suggestions
  List<Map<String, dynamic>> _destinationSuggestions = [];
  List<Map<String, dynamic>> _pickupSuggestions = [];
  List<Map<String, dynamic>> _stopSuggestions = [];
  final String _googlePlacesApiKey = 'AIzaSyCkKD8FP-r9bqi5O-sOjtuksT-0Dr9dgeg';
  final List<String> _searchHistory = [];
  
  // UI State Variables
  bool _selectingPickup = false;
  bool _editingPickup = false;
  bool _editingDestination = false;
  bool _isLoadingRoute = false;
  final FocusNode _destinationFocusNode = FocusNode();
  final FocusNode _pickupFocusNode = FocusNode();
  final FocusNode _stopFocusNode = FocusNode();
  
  // Sheet Control
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  double _currentSheetSize = 0.35;
  bool _isSheetExpanded = false;
  
  // Stops Management
  final List<Stop> _stops = [];
  int? _editingStopIndex;
  bool _routeReady = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializePickupLocation();
    _setupFocusListeners();
    _sheetController.addListener(_onSheetChanged);
    _loadSearchHistory(); 
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_destinationController.text.isEmpty) {
        setState(() {
          _editingDestination = true;
        });
      }
    });
  }

  void _startEditing(String field, {bool requestFocus = true}) {
    setState(() {
      // Clear all editing states first
      _editingPickup = false;
      _editingDestination = false;
      _editingStopIndex = null;
      
      // Set the new editing state
      if (field == 'pickup') {
        _editingPickup = true;
        if (requestFocus) _pickupFocusNode.requestFocus();
      } else if (field == 'destination') {
        _editingDestination = true;
        if (requestFocus) _destinationFocusNode.requestFocus();
      } else if (field.startsWith('stop_')) {
        final index = int.parse(field.split('_')[1]);
        _editingStopIndex = index;
        if (requestFocus) _stopFocusNode.requestFocus();
      }
    });
    _expandSheet();
  }

  // Calculate the visible map area based on sheet position
  LatLngBounds _getVisibleMapArea() {
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetTop = screenHeight * (1 - _currentSheetSize);
    final visibleHeightRatio = sheetTop / screenHeight;
    
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    
    if (_pickupLocation == null && _dropOffLocation == null) {
      return LatLngBounds(
        northeast: LatLng(
          locationProvider.currentLocation?.latitude ?? 0, 
          locationProvider.currentLocation?.longitude ?? 0
        ),
        southwest: LatLng(
          locationProvider.currentLocation?.latitude ?? 0, 
          locationProvider.currentLocation?.longitude ?? 0
        ),
      );
    }

    final points = <LatLng>[
      if (_pickupLocation != null)
        LatLng(_pickupLocation!.latitude, _pickupLocation!.longitude),
      if (_dropOffLocation != null)
        LatLng(_dropOffLocation!.latitude, _dropOffLocation!.longitude),
      ..._stops.where((s) => s.location != null)
               .map((s) => LatLng(s.location!.latitude, s.location!.longitude)),
    ];

    if (points.isEmpty) {
      return LatLngBounds(
        northeast: LatLng(
          locationProvider.currentLocation?.latitude ?? 0, 
          locationProvider.currentLocation?.longitude ?? 0
        ),
        southwest: LatLng(
          locationProvider.currentLocation?.latitude ?? 0, 
          locationProvider.currentLocation?.longitude ?? 0
        ),
      );
    }

    final bounds = _boundsFromLatLngList(points);
    final latDelta = bounds.northeast.latitude - bounds.southwest.latitude;
    final lngDelta = bounds.northeast.longitude - bounds.southwest.longitude;
    
    return LatLngBounds(
      northeast: LatLng(
        bounds.northeast.latitude + (latDelta * 0.2),
        bounds.northeast.longitude + (lngDelta * 0.2),
      ),
      southwest: LatLng(
        bounds.southwest.latitude - (latDelta * 0.2 * (1 - visibleHeightRatio)),
        bounds.southwest.longitude - (lngDelta * 0.2),
      ),
    );
  }

  void _setupFocusListeners() {
    _destinationFocusNode.addListener(_onDestinationFocusChange);
    _pickupFocusNode.addListener(_onPickupFocusChange);
    _stopFocusNode.addListener(_onStopFocusChange);
  }

  void _onDestinationFocusChange() {
    if (_destinationFocusNode.hasFocus) {
      _expandSheet();
      setState(() {
        _selectingPickup = false;
        _editingStopIndex = null;
        _editingDestination = true;
      });
      _adjustMapForExpandedSheet();
    } else if (!_destinationFocusNode.hasFocus && _editingDestination) {
      // Don't automatically turn off editing when losing focus
      // Wait for explicit submission or map tap
    }
  }

  void _onPickupFocusChange() {
    if (_pickupFocusNode.hasFocus) {
      _expandSheet();
      setState(() {
        _selectingPickup = false;
        _editingStopIndex = null;
        _editingPickup = true;
      });
      _adjustMapForExpandedSheet();
    } else if (!_pickupFocusNode.hasFocus && _editingPickup) {
      // Don't automatically turn off editing when losing focus
      // Wait for explicit submission or map tap
    }
  }

  void _onStopFocusChange() {
    if (_stopFocusNode.hasFocus) {
      _expandSheet();
      _adjustMapForExpandedSheet();
    }
  }

  void _adjustMapForExpandedSheet() {
    if (_mapController != null) {
      final bounds = _getVisibleMapArea();
      final padding = 50.0 + (100 * _currentSheetSize);
      
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding),
      );
    }
  }

  void _onSheetChanged() {
    setState(() {
      _currentSheetSize = _sheetController.size;
      _isSheetExpanded = _sheetController.size > 0.6;
      _checkRouteReady();
    });

    // Adjust map view when sheet changes
    _adjustMapForExpandedSheet();
  }

  void _checkRouteReady() {
    setState(() {
      _routeReady = _pickupLocation != null && _dropOffLocation != null;
    });
  }

  void _collapseSheet() {
    _sheetController.animateTo(0.35,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _expandSheet() {
    _sheetController.animateTo(0.9,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  //
  // Load search history from SharedPreferences
  Future<void> _loadSearchHistory() async {
  final prefs = await SharedPreferences.getInstance();
  final List<String>? storedHistory = prefs.getStringList('search_history');
    if (storedHistory != null) {
      setState(() {
        _searchHistory.clear();
        _searchHistory.addAll(storedHistory);
      });
    }
  }

  void _updateSearchHistory(String address) {
    if (address.isNotEmpty && !_searchHistory.contains(address)) {
      setState(() {
        _searchHistory.insert(0, address);
        if (_searchHistory.length > 8) {
          _searchHistory.removeLast(); // Keep max 8 items
        }
      });
      _saveSearchHistory();
    }
  } 

  Future<void> _saveSearchHistory() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('search_history', _searchHistory);
  }


  Future<void> _initializePickupLocation() async {
    final currentLocation = Provider.of<LocationProvider>(context, listen: false).currentLocation;
    if (currentLocation != null) {
      _pickupLocation = currentLocation;
      _updateGooglePickupMarker(LatLng(currentLocation.latitude, currentLocation.longitude));
      await _reverseGeocode(_pickupLocation!, _pickupController);
    }
  }

  Future<void> _reverseGeocode(ll.LatLng location, TextEditingController controller) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty) {
        final Placemark place = placemarks.first;
        String address = _formatAddress(place);
        controller.text = address;
             _updateSearchHistory(address); // <--- CALL saving function here ✅
      } else {
        throw Exception('No placemarks found');
      }
    } catch (e) {
      print('Error reverse geocoding: $e');
      controller.text = _formatFallbackAddress(location);
    }
  }

  String _formatAddress(Placemark place) {
    // Improved address formatting
    List<String> addressParts = [];
    
    if (place.name != null && place.name!.isNotEmpty && place.name != 'Unnamed Road') {
      addressParts.add(place.name!);
    }
    
    if (place.street != null && place.street!.isNotEmpty) {
      if (addressParts.isEmpty || !addressParts.last.contains(place.street!)) {
        addressParts.add(place.street!);
      }
    }
    
    if (place.subLocality != null && place.subLocality!.isNotEmpty) {
      addressParts.add(place.subLocality!);
    } else if (place.locality != null && place.locality!.isNotEmpty) {
      addressParts.add(place.locality!);
    }
    
    if (addressParts.isEmpty) {
      return 'Selected location';
    }
    
    return addressParts.join(', ');
  }

  String _formatFallbackAddress(ll.LatLng location) {
    return 'Location (${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)})';
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
    }
  }
  
  void _updateStopMarker(int index, LatLng location) {
    setState(() {
      _markers.removeWhere((marker) => marker.markerId == MarkerId('stop_$index'));
      _markers.add(
        Marker(
      markerId: MarkerId('stop_$index'),
          position: location,
          infoWindow: InfoWindow(title: 'Stop ${index + 1}'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      zIndex: index.toDouble(),
        ),
    );
    });
  }

  void _handleMapTap(LatLng tappedLatLng) {
    final llTappedLatLng = ll.LatLng(tappedLatLng.latitude, tappedLatLng.longitude);
    
    if (_selectingPickup || _editingPickup) {
      setState(() {
        _pickupLocation = llTappedLatLng;
        _updateGooglePickupMarker(tappedLatLng);
        _reverseGeocode(_pickupLocation!, _pickupController);
        _selectingPickup = false;
        _editingPickup = false;
        _pickupFocusNode.unfocus();
        _collapseSheet();
      });
    } else if (_editingStopIndex != null) {
      setState(() {
        _stops[_editingStopIndex!].location = llTappedLatLng;
        _reverseGeocode(llTappedLatLng, _stops[_editingStopIndex!].controller);
        _updateStopMarker(_editingStopIndex!, tappedLatLng);
        _editingStopIndex = null;
        _stopFocusNode.unfocus();
        _collapseSheet();
      });
    } else if (_editingDestination) {
      setState(() {
        _dropOffLocation = llTappedLatLng;
        _updateGoogleDropOffMarker(tappedLatLng);
        _reverseGeocode(_dropOffLocation!, _destinationController);
        _editingDestination = false;
        _destinationFocusNode.unfocus();
        _drawRoute();
        _collapseSheet();
      });
    } else if (_dropOffLocation == null && !_editingPickup && _editingStopIndex == null) {
      setState(() {
        _dropOffLocation = llTappedLatLng;
        _updateGoogleDropOffMarker(tappedLatLng);
        _reverseGeocode(_dropOffLocation!, _destinationController);
        _drawRoute();
      });
    }
    _checkRouteReady();
  }

  Future<void> _drawRoute() async {
  if (_pickupLocation == null || _dropOffLocation == null) return;

  // Format waypoints for the API
  final waypoints = _stops
      .where((s) => s.location != null)
      .map((s) => '${s.location!.latitude},${s.location!.longitude}')
      .join('|');

  final origin = '${_pickupLocation!.latitude},${_pickupLocation!.longitude}';
  final destination = '${_dropOffLocation!.latitude},${_dropOffLocation!.longitude}';

  // Build the API URL
  final url = Uri.parse(
    'https://maps.googleapis.com/maps/api/directions/json?'
    'origin=$origin&destination=$destination&key=$_googlePlacesApiKey'
    '${waypoints.isNotEmpty ? '&waypoints=$waypoints' : ''}'
    '&alternatives=true', // Request alternative routes
  );

  try {
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        final routes = data['routes'] as List;

        setState(() {
          _polylines.clear(); // Clear existing polylines
          _isLoadingRoute = true;

          // Add all routes to the map
          for (int i = 0; i < routes.length; i++) {
            final route = routes[i];
            final routePoints = _decodePolyline(route['overview_polyline']['points']);
            final leg = route['legs'][0];

            _polylines.add(Polyline(
              polylineId: PolylineId('route_$i'),
              color: i == 0 ? Colors.blue : Colors.grey, // Highlight the first route
              width: i == 0 ? 6 : 4, // Make the primary route thicker
              points: routePoints,
              onTap: () {
                // Handle route selection if needed
                // print('Selected route $i');
                setState(() {
                  // Highlight the selected route
                  _polylines.forEach((polyline) {
                    polyline = polyline.copyWith(
                      colorParam: polyline.polylineId == PolylineId('route_$i') ? Colors.blue : Colors.grey,
                      widthParam: polyline.polylineId == PolylineId('route_$i') ? 6 : 4,
                    );
                  });
                });
              },
            ));

            // Update route distance and duration for the primary route
            if (i == 0) {
              _routeDistance = leg['distance']['text']; // e.g., "4.5 km"
              _routeDuration = leg['duration']['text']; // e.g., "12 mins"
            }
          }

          // Adjust the camera to fit all routes
          final allPoints = routes
              .expand((route) => _decodePolyline(route['overview_polyline']['points']))
              .toList();
          _mapController?.animateCamera(
            CameraUpdate.newLatLngBounds(_boundsFromLatLngList(allPoints), 100),
          );
        });
      } else {
        print('Directions API error: ${data['status']}');
      }
    } else {
      print('Failed to load route');
    }
  } catch (e) {
    print('Error fetching route: $e');
  }
  _checkRouteReady();
  setState(() {
    _isLoadingRoute = false;
  });
}

  // Decode the polyline from the Directions API
 List<LatLng> _decodePolyline(String encoded) {
  List<LatLng> points = [];
  int index = 0, len = encoded.length;
  int lat = 0, lng = 0;

  while (index < len) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1F) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += dlat;

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1F) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += dlng;

    points.add(LatLng(lat / 1E5, lng / 1E5));
  }
  return points;
 }

  LatLngBounds _boundsFromLatLngList(List<LatLng> list) {
    double? x0, x1, y0, y1;
    for (LatLng latLng in list) {
      if (x0 == null) {
        x0 = x1 = latLng.latitude;
        y0 = y1 = latLng.longitude;
      } else {
        if (latLng.latitude > x1!) x1 = latLng.latitude;
        if (latLng.latitude < x0) x0 = latLng.latitude;
        if (latLng.longitude > y1!) y1 = latLng.longitude;
        if (latLng.longitude < y0!) y0 = latLng.longitude;
      }
    }
    return LatLngBounds(
      northeast: LatLng(x1!, y1!),
      southwest: LatLng(x0!, y0!),
    );
  }

  Future<List<Map<String, dynamic>>> _getGooglePlacesSuggestions(String query) async {
    if (query.isEmpty) return [];
    final url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$_googlePlacesApiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          return (data['predictions'] as List).map((p) => {
            'place_id': p['place_id'],
            'description': p['description'],
          }).toList();
        }
      }
      return [];
    } catch (e) {
      print('Error fetching suggestions: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> _getPlaceDetails(String placeId) async {
    final url = 'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_googlePlacesApiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final geometry = data['result']['geometry']['location'];
          return {
            'latitude': geometry['lat'],
            'longitude': geometry['lng'],
          };
        }
      }
      return null;
    } catch (e) {
      print('Error fetching place details: $e');
      return null;
    }
  }

  Future<void> _handleDestinationSelected(Map<String, dynamic> suggestion) async {
    final placeDetails = await _getPlaceDetails(suggestion['place_id']);
    if (placeDetails != null) {
      final latLng = ll.LatLng(placeDetails['latitude'], placeDetails['longitude']);
      final address = suggestion['description'] ?? '';

      setState(() {
        _dropOffLocation = latLng;
        _updateGoogleDropOffMarker(LatLng(latLng.latitude, latLng.longitude));
        _destinationController.text = suggestion['description'] ?? '';
        _destinationSuggestions = [];
        
       // 🔥 Insert into search history if not duplicate
        _updateSearchHistory(address);
        _editingDestination = false;
        _destinationFocusNode.unfocus();
      });
      // Only reverse geocode if no description or too short
      if ((suggestion['description'] != null && (suggestion['description'] as String).length < 5)) {
        await _reverseGeocode(_pickupLocation!, _pickupController);
      }

      _drawRoute();
      _collapseSheet();
    }
      _checkRouteReady();
  }

  // Handle pickup, drop-off, and stop selection
  Future<void> _handlePickupSelected(Map<String, dynamic> suggestion) async {
  final placeDetails = await _getPlaceDetails(suggestion['place_id']);
  if (placeDetails != null) {
    final latLng = ll.LatLng(placeDetails['latitude'], placeDetails['longitude']);
    final address = suggestion['description'] ?? '';
    setState(() {
      _pickupLocation = latLng;
      _updateGooglePickupMarker(LatLng(latLng.latitude, latLng.longitude));
      _pickupController.text = suggestion['description'] ?? '';
      _pickupSuggestions = [];
      
     // 🔥 Insert into search history if not duplicate
        _updateSearchHistory(address);
        _editingPickup = false;
        _pickupFocusNode.unfocus();  
    });

    // Only reverse geocode if no description or too short
    if (((suggestion['description'] as String?)?.length ?? 0) < 5) {
      await _reverseGeocode(_pickupLocation!, _pickupController);
    }

    _drawRoute();
    _collapseSheet();
  }
  _checkRouteReady();
  }


  Future<void> _handleStopSelected(int index, Map<String, dynamic> suggestion) async {
  final placeDetails = await _getPlaceDetails(suggestion['place_id']);
  if (placeDetails != null) {
    final latLng = ll.LatLng(placeDetails['latitude'], placeDetails['longitude']);
    final address = suggestion['description'] ?? '';
    setState(() {
      _stops[index].location = latLng;
      _stops[index].controller.text = suggestion['description'] ?? '';
      _updateStopMarker(index, LatLng(latLng.latitude, latLng.longitude));
      _stopSuggestions = [];
      
       // 🔥 Insert into search history if not duplicate
        _updateSearchHistory(address);
        _editingStopIndex = null;
        _destinationFocusNode.unfocus();
    });

    if (((suggestion['description'] as String?)?.length ?? 0) < 5) {
      await _reverseGeocode(latLng, _stops[index].controller);
    }

    _drawRoute();
    _collapseSheet();
  }
  _checkRouteReady();
  }


  void _swapLocations() {
    setState(() {
      // Swap text
      final tempText = _pickupController.text;
      _pickupController.text = _destinationController.text;
      _destinationController.text = tempText;
      
      // Swap locations
      final tempLoc = _pickupLocation;
      _pickupLocation = _dropOffLocation;
      _dropOffLocation = tempLoc;
      
      // Update markers
      _markers.removeWhere((m) => m.markerId == const MarkerId('pickup'));
      _markers.removeWhere((m) => m.markerId == const MarkerId('dropoff'));
      
      if (_pickupLocation != null) {
        _markers.add(Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(_pickupLocation!.latitude, _pickupLocation!.longitude),
          infoWindow: const InfoWindow(title: 'Pickup'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ));
      }
      
      if (_dropOffLocation != null) {
        _markers.add(Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(_dropOffLocation!.latitude, _dropOffLocation!.longitude),
          infoWindow: const InfoWindow(title: 'Drop-off'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ));
      }
      
      _drawRoute();
    });
    _checkRouteReady();
  }

  void _clearPickup() {
    setState(() {
      _pickupController.clear();
      _pickupLocation = null;
      _routeDistance = null;
      _routeDuration = null;
      _markers.removeWhere((m) => m.markerId == const MarkerId('pickup'));
      _drawRoute();
    });
    _checkRouteReady();
  }

  void _clearDestination() {
    setState(() {
      _destinationController.clear();
      _dropOffLocation = null;
      _routeDistance = null;
      _routeDuration = null;
      _markers.removeWhere((m) => m.markerId == const MarkerId('dropoff'));
      _drawRoute();
    });
    _checkRouteReady();
  }

  void _clearStop(int index) {
    setState(() {
      _stops[index].controller.clear();
      _stops[index].location = null;
      _routeDistance = null;
      _routeDuration = null;
      _markers.removeWhere((m) => m.markerId == MarkerId('stop_$index'));
      _drawRoute();
    });
    _checkRouteReady();
  }

  void _addStop() {
    setState(() {
      _stops.add(Stop(
        name: 'Stop ${_stops.length + 1}',
        address: 'Search or tap on map',
      ));
      _editingStopIndex = _stops.length - 1;
      _expandSheet();
    });
  }

  void _removeStop(int index) {
  setState(() {
    _markers.removeWhere((m) => m.markerId == MarkerId('stop_$index'));
    _stops.removeAt(index);

    // After removing, update the markers of other stops
    for (int i = 0; i < _stops.length; i++) {
      if (_stops[i].location != null) {
        _markers.removeWhere((m) => m.markerId == MarkerId('stop_$i'));
        _updateStopMarker(i, LatLng(_stops[i].location!.latitude, _stops[i].location!.longitude));
      }
    }

    _drawRoute();
    _checkRouteReady();
  });
  }

  void _confirmRideRequest() async {
    final rideRequestProvider = Provider.of<RideRequestProvider>(context, listen: false); // Ensure RideRequestProvider is defined and imported

    if (_pickupLocation == null || _dropOffLocation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select both pickup and drop-off locations')),
        );
      }
      return;
    }

    try {
      final stopsData = _stops
        .where((s) => s.location != null) 
        .map((s) => {
              'name': s.name,
              'location': s.location!, 
            })
        .toList();
        
        

      final rideRequest = RideRequestModel(
        customerId: rideRequestProvider.authService.currentUser?.uid,
        pickup: ll.LatLng(_pickupLocation!.latitude, _pickupLocation!.longitude),
        dropoff: ll.LatLng(_dropOffLocation!.latitude, _dropOffLocation!.longitude),
        stops: stopsData,
        status: 'pending',
        timestamp: DateTime.now(),
      );

      await rideRequestProvider.createRideRequest(rideRequest);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride request created successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create ride request: $e')),
        );
      }
    }
  }

  Future<void> _scheduleRide(
    BuildContext context,
    LatLng pickupLocation,
    LatLng dropOffLocation,
    String pickupAddress,
    String dropOffAddress,
    String customerId, 
    List<Map<String, dynamic>> stops 

    ) async {
  final TextEditingController titleController = TextEditingController();
  DateTime? selectedDate;
  TimeOfDay? selectedTime;

  await showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Schedule Ride'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Enter a title for your ride',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final now = DateTime.now();
                selectedDate = await showDatePicker(
                  context: context,
                  initialDate: now,
                  firstDate: now,
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (selectedDate != null) {
                  selectedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(now),
                  );
                }
              },
              child: const Text('Pick Date & Time'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.isNotEmpty &&
                  selectedDate != null &&
                  selectedTime != null) {
                Navigator.of(context).pop();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Please provide a title, date, and time')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );

  if (titleController.text.isNotEmpty &&
      selectedDate != null &&
      selectedTime != null) {
    final DateTime scheduledDateTime = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
      selectedTime!.hour,
      selectedTime!.minute,
    );

    try {
      final rideData = {
        'customerId': Provider.of<RideRequestProvider>(context, listen: false).authService.currentUser?.uid,   
        'title': titleController.text,
        'scheduledDateTime': scheduledDateTime.toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
        'pickupLocation': GeoPoint(pickupLocation.latitude, pickupLocation.longitude), 
        'dropOffLocation': GeoPoint(dropOffLocation.latitude, dropOffLocation.longitude), 
        //'pickupAddress': pickupAddress, 
        //'dropOffAddress': dropOffAddress,  
        'status': 'scheduled', 
        'stops': stops.map((stop) => {
          'name': stop['name'],
          'location': stop['location'] != null
              ? GeoPoint(stop['location'].latitude, stop['location'].longitude)
              : null,
        }).toList(), 

      };

      await FirebaseFirestore.instance
          .collection('scheduledRides')
          .add(rideData);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride scheduled successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to schedule ride: $e')),
      );
    }
  }
}

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final locationProvider = Provider.of<LocationProvider>(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(
              target: locationProvider.currentLocation != null
                  ? LatLng(
                      locationProvider.currentLocation!.latitude,
                      locationProvider.currentLocation!.longitude,
                    )
                  : const LatLng(0, 0),
              zoom: 15,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _adjustMapForExpandedSheet();
              });
            },
            onTap: _handleMapTap,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            padding: EdgeInsets.only( // Map padding to avoid overlap with sheet
              bottom: MediaQuery.of(context).size.height * _currentSheetSize,
            ),
          ),
          
          _buildRouteSheet(),
        ],
      ),
    );
  }

  Widget _buildFieldContainer(Widget child) {
    return Container(
      height: 56, // Fixed height for all fields
      decoration: BoxDecoration(
        // Use theme color for background
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12), // Use horizontalSpaceMedium?
      child: child,
    );
  }

  Widget _buildRouteSheet() {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.35,
      minChildSize: 0.25,
      maxChildSize: 0.9,
      snap: true,
      snapSizes: const [0.35, 0.7, 0.9],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            // Use theme color for sheet background
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                blurRadius: 10, // Consider adjusting shadow based on theme
                color: Colors.black12,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag Handle
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      // Use theme color for handle
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              
              // Main Scrollable Content
              Expanded(
                child: CustomScrollView(
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title (Your Route)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Use spacing constants?
                            child: Text(
                              'Your route',
                              // Use theme text style
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          
                          // Route Info (Distance and Duration)
                          if (_routeDistance != null && _routeDuration != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), // Use spacing constants?
                            child: Row(
                              children: [
                                Icon(Icons.access_time, size: 20, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7)),
                                horizontalSpaceSmall,
                                Text('$_routeDuration · $_routeDistance',
                                  style: Theme.of(context).textTheme.bodyMedium, // Use theme text style
                                ),
                              ],
                            ),
                          ),

                          // Pickup Field
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Use spacing constants?
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _startEditing('pickup'),
                                    child: _buildFieldContainer(
                                      Row(
                                        children: [
                                          // Use theme icon color or specific color
                                          Icon(Icons.location_on, color: successColor, size: Theme.of(context).iconTheme.size),
                                          horizontalSpaceMedium, // Use spacing constant
                                          Expanded(
                                            child: _pickupController.text.isEmpty
                                                ? Text(
                                                    'Pickup location',
                                                    style: appTextStyle(color: Theme.of(context).hintColor), // Use theme hint color
                                                  )
                                                : Text(
                                                    _pickupController.text,
                                                    style: Theme.of(context).textTheme.bodyLarge, // Use theme text style
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 24),
                                  onPressed: _addStop,
                                ),
                              ],
                            ),
                          ),
                          
                          if (_editingPickup)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16), // Use spacing constants?
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _pickupController,
                                    focusNode: _pickupFocusNode,
                                     // Use theme input decoration
                                    decoration: InputDecoration(
                                      hintText: 'Enter pickup location',
                                      // border: const UnderlineInputBorder(), // Remove, use theme
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_pickupController.text.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.clear, size: 20),
                                              onPressed: _clearPickup,
                                            ),
                                          IconButton(
                                            icon: const Icon(Icons.map), // Uses theme icon color
                                            onPressed: () {
                                              setState(() {
                                                _selectingPickup = true;
                                                _editingPickup = true;
                                              });
                                              _collapseSheet();
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Tap on map to select pickup location')),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    onChanged: (value) async {
                                      if (value.isNotEmpty) {
                                        final suggestions = await _getGooglePlacesSuggestions(value);
                                        setState(() => _pickupSuggestions = suggestions);
                                      } else {
                                        setState(() => _pickupSuggestions = []); // Show search history if empty
                                      }
                                    },
                                    onSubmitted: (_) {
                                      setState(() => _editingPickup = false);
                                      _collapseSheet();
                                    },
                                  ),
                                  ..._buildSuggestionList(_pickupSuggestions, true, null),
                                ],
                              ),
                            ),
                          
                          // Stops Section with + button for each stop
                          if (_stops.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), // Use spacing constants?
                              child: Column(
                                children: _stops.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final stop = entry.value;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _buildStopItem(index, stop),
                                        ),
                                        horizontalSpaceSmall,
                                        IconButton(
                                          icon: const Icon(Icons.add, size: 24),
                                          onPressed: () => _addStopAfter(index),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          
                          // Destination Field
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Use spacing constants?
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _startEditing('destination'),
                                    child: _buildFieldContainer(
                                      Row(
                                        children: [
                                          // Use theme error color
                                          Icon(Icons.flag, color: Theme.of(context).colorScheme.error, size: Theme.of(context).iconTheme.size),
                                          horizontalSpaceMedium, // Use spacing constant
                                          Expanded(
                                            child: _destinationController.text.isEmpty
                                                ? Text(
                                                    'Where to?',
                                                    style: appTextStyle(color: Theme.of(context).hintColor), // Use theme hint color
                                                  )
                                                : Text(
                                                    _destinationController.text,
                                                    style: Theme.of(context).textTheme.bodyLarge, // Use theme text style
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                if (_pickupLocation != null && _dropOffLocation != null)
                                  IconButton(
                                    icon: const Icon(Icons.swap_vert, size: 24),
                                    onPressed: _swapLocations,
                                    tooltip: 'Swap locations',
                                  ),
                              ],
                            ),
                          ),
                          
                          if (_editingDestination)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16), // Use spacing constants?
                              child: Column(
                                children: [
                                  TextField(
                                    controller: _destinationController,
                                    focusNode: _destinationFocusNode,
                                     // Use theme input decoration
                                    decoration: InputDecoration(
                                      hintText: 'Enter destination',
                                      // border: const UnderlineInputBorder(), // Remove, use theme
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_destinationController.text.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.clear, size: 20),
                                              onPressed: _clearDestination,
                                            ),
                                          IconButton(
                                            icon: const Icon(Icons.map), // Uses theme icon color
                                            onPressed: () {
                                              setState(() => _editingDestination = true);
                                              _collapseSheet();
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Tap on map to select destination')),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    onChanged: (value) async {
                                      if (value.isNotEmpty) {
                                        final suggestions = await _getGooglePlacesSuggestions(value);
                                        setState(() => _destinationSuggestions = suggestions);
                                      } else {
                                        setState(() => _pickupSuggestions = []); // Show search history when empty
                                      }
                                    },
                                    onSubmitted: (_) {
                                      setState(() => _editingDestination = false);
                                      _collapseSheet();
                                    },
                                  ),
                                  ..._buildSuggestionList(_destinationSuggestions, false, null),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    SliverToBoxAdapter(
                      // Adjust spacing based on sheet expansion
                      child: SizedBox(height: _isSheetExpanded ? 120 : 80), // Use verticalSpaceLarge?
                    ),
                  ],
                ),
              ),
              
              // Action Buttons (only shown when both pickup and destination are set)
              if (_isLoadingRoute)
                const Center(child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(), // Uses theme primary color
                ))
              else if (_pickupLocation != null && _dropOffLocation != null)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  // Use theme surface color to blend with sheet
                  color: Theme.of(context).colorScheme.surface,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: () => _scheduleRide(
                            context,
                            LatLng(_pickupLocation!.latitude, _pickupLocation!.longitude),
                            LatLng(_dropOffLocation!.latitude, _dropOffLocation!.longitude),
                            _pickupController.text,
                            _destinationController.text,
                            Provider.of<RideRequestProvider>(context, listen: false).authService.currentUser?.uid ?? '',
                            _stops.map((stop) => {
                              'name': stop.name,
                              'location': stop.location != null
                                  ? GeoPoint(stop.location!.latitude, stop.location!.longitude)
                                  : null,
                            }).toList(),
                          ),
                          // Style comes from OutlinedButtonThemeData
                          style: Theme.of(context).outlinedButtonTheme.style?.copyWith(
                                minimumSize: MaterialStateProperty.all(const Size(double.infinity, 50)),
                              ),
                          child: const Text('Schedule'),
                        ),
                      ),
                      horizontalSpaceMedium, // Use spacing constant
                      Expanded(
                        flex: 3,
                        child: ElevatedButton(
                          onPressed: _confirmRideRequest,
                          // Style comes from ElevatedButtonThemeData
                          style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                                minimumSize: MaterialStateProperty.all(const Size(double.infinity, 50)),
                              ),
                          child: const Text(
                            'Confirm Route',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStopItem(int index, Stop stop) {
    final isEditing = _editingStopIndex == index;
    final theme = Theme.of(context); // Get theme
    
    return Column(
      children: [
        Dismissible(
          key: Key('stop_${index}_${_stops[index].controller.text}'),
          direction: DismissDirection.endToStart,
          background: Container(
            decoration: BoxDecoration(
              // Use theme error container color
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: Icon(
              Icons.delete,
              color: theme.colorScheme.onErrorContainer, // Use theme color for icon on error container
            ),
          ),
          onDismissed: (direction) => _removeStop(index),
          child: InkWell(
            onTap: () => _startEditing('stop_$index'),
            child: _buildFieldContainer(
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      // Use theme primary color with opacity
                      color: theme.primaryColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          // Use theme primary color
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  horizontalSpaceMedium, // Use spacing constant
                  Expanded(
                    child: stop.controller.text.isEmpty
                        // Use theme hint color
                        ? Text('Add stop', style: appTextStyle(color: theme.hintColor))
                        : Text(stop.controller.text, style: theme.textTheme.bodyLarge), // Use theme text style
                  ),
                ],
              ),
            ),
          ),
        ),
        
        if (isEditing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              children: [
                TextField(
                  controller: stop.controller,
                  focusNode: _stopFocusNode,
                  // Use theme input decoration
                  decoration: InputDecoration(
                    hintText: 'Enter stop location',
                    // border: const UnderlineInputBorder(), // Remove, use theme
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (stop.controller.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () => _clearStop(index),
                          ),
                        IconButton(
                          icon: const Icon(Icons.map, size: 20), // Uses theme icon color
                          onPressed: () {
                            setState(() => _editingStopIndex = index);
                            _collapseSheet();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Tap on map to select location for Stop ${index + 1}')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  onChanged: (value) async {
                    if (value.isNotEmpty) {
                      final suggestions = await _getGooglePlacesSuggestions(value);
                      setState(() => _stopSuggestions = suggestions);
                    } else {
                      setState(() => _stopSuggestions = []);
                    }
                  },
                  onSubmitted: (_) {
                    setState(() => _editingStopIndex = null);
                    _collapseSheet();
                  },
                ),
                if (_stopSuggestions.isNotEmpty || stop.controller.text.isEmpty)
                  ..._buildSuggestionList(_stopSuggestions, false, index),
              ],
            ),
          ),
      ],
    );
  }

  void _addStopAfter(int index) {
    setState(() {
      _stops.insert(index + 1, Stop(
        name: 'Stop ${_stops.length + 1}',
        address: 'Search or tap on map'
      ));
      _editingStopIndex = index + 1;
    });
    _expandSheet();
  }

  List<Widget> _buildSuggestionList(List<Map<String, dynamic>> suggestions, bool isPickup, int? stopIndex) {
    return [
      if (suggestions.isNotEmpty)
        ...suggestions.map((suggestion) => _buildSuggestionItem(suggestion, isPickup, stopIndex)).toList(),
      if (suggestions.isEmpty && _searchHistory.isNotEmpty)
        ..._searchHistory.map((history) => _buildHistoryItem(history)).toList(),
    ];
  }

  Widget _buildSuggestionItem(Map<String, dynamic> suggestion, bool isPickup, int? stopIndex) {
    final theme = Theme.of(context);
    return ListTile(
      // Use theme icon color
      leading: Icon(isPickup ? Icons.location_on : Icons.flag, color: theme.iconTheme.color),
      title: Text(suggestion['description'] ?? '', style: theme.textTheme.bodyMedium), // Use theme text style
      onTap: () {
        if (stopIndex != null) { // Check if editing a stop
          _handleStopSelected(stopIndex, suggestion);
        } else if (isPickup) {
          _handlePickupSelected(suggestion);
        } else {
          _handleDestinationSelected(suggestion);
        }
      },
    );
  }

  Widget _buildHistoryItem(String historyItem) {
  final theme = Theme.of(context);
  return ListTile(
    // Use theme icon color
    leading: Icon(Icons.history, color: theme.iconTheme.color),
    title: Text(historyItem, style: theme.textTheme.bodyMedium), // Use theme text style
    onTap: () async {
      try {
        final List<Location> locations = await locationFromAddress(historyItem);
        if (locations.isNotEmpty) {
          final location = locations.first;
          final llLatLng = ll.LatLng(location.latitude, location.longitude);

          setState(() {
            if (_pickupFocusNode.hasFocus || _editingPickup) {
              _pickupController.text = historyItem;
              _pickupLocation = llLatLng;
              _updateGooglePickupMarker(LatLng(location.latitude, location.longitude));
              _editingPickup = false;
              _pickupFocusNode.unfocus();
              _pickupSuggestions = [];
            } else if (_destinationFocusNode.hasFocus || _editingDestination) {
              _destinationController.text = historyItem;
              _dropOffLocation = llLatLng;
              _updateGoogleDropOffMarker(LatLng(location.latitude, location.longitude));
              _editingDestination = false;
              _destinationFocusNode.unfocus();
              _destinationSuggestions = [];
            } else if (_stopFocusNode.hasFocus || _editingStopIndex != null) {
              final index = _editingStopIndex!;
              _stops[index].controller.text = historyItem;
              _stops[index].location = llLatLng;
              _updateStopMarker(index, LatLng(location.latitude, location.longitude));
              _editingStopIndex = null;
              _stopFocusNode.unfocus();
              _stopSuggestions = [];
            }
          });

          _drawRoute();
          _checkRouteReady();
          _collapseSheet();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location not found')),
          );
        }
      } catch (e) {
        print('Error geocoding history item: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error finding location')),
        );
      }
    },
  );
 }

  @override
  void dispose() {
    _sheetController.dispose();
    _destinationFocusNode.dispose();
    _pickupFocusNode.dispose();
    _stopFocusNode.dispose();
    super.dispose();
  }
}
//class Stop {
  //final String name;
  //final String address;
  //ll.LatLng? location;
  //final TextEditingController controller = TextEditingController();

 //Stop({
  //required this.name,
  //required this.address,
  //this.location,
  //});
//}