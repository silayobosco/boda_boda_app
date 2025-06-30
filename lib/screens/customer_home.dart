import 'dart:async';
import 'dart:convert';
import 'package:boda_boda/models/Ride_Request_Model.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:boda_boda/providers/ride_request_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Import GeoPoint from cloud_firestore
import '../models/stop.dart';
import '../models/user_model.dart'; // For Driver's UserModel
import '../utils/ui_utils.dart'; // Import ui_utils
import '../utils/map_utils.dart'; // Import the new map utility
import '../services/firestore_service.dart';
import 'chat_screen.dart';
import 'kijiwe_profile_screen.dart'; // Import KijiweProfileScreen
import 'scheduled_rides_list_widget.dart'; // Import ScheduledRidesListWidget
import 'rides_screen.dart'; // Import RidesScreen for ride history

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  _CustomerHomeState createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> with AutomaticKeepAliveClientMixin {
  static const double _kijiweSearchRadiusKm = 10.0; // Increased radius
  // Map and Location Variables
  GoogleMapController? _mapController;
  ll.LatLng? _pickupLocation;
  ll.LatLng? _dropOffLocation;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  
  // Search and Suggestions
  List<Map<String, dynamic>> _destinationSuggestions = [];
  List<Map<String, dynamic>> _pickupSuggestions = [];
  final String _googlePlacesApiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;
  final List<String> _searchHistory = [];
  
  // UI State Variables
  bool _selectingPickup = false;
  bool _editingPickup = false;
  bool _editingDestination = false;
  // bool _isLoadingRoute = false; // Will be replaced by _isFindingDriver or specific loading for route drawing
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
  List<Map<String, dynamic>> _stopSuggestions = [];

  // Route Management
  List<Map<String, dynamic>> _allFetchedRoutes = []; // To store all routes from MapUtils
  int _selectedRouteIndex = 0; // Index of the currently selected route
  String? _selectedRouteDistance;
  String? _selectedRouteDuration;

  // Ride Lifecycle State
  bool _isFindingDriver = false;
  String? _activeRideRequestId;
  RideRequestModel? _activeRideRequestDetails; // This will be updated by the stream
  UserModel? _assignedDriverModel;
  StreamSubscription? _activeRideSubscription;
  StreamSubscription? _driverLocationSubscription;
  BitmapDescriptor? _driverIcon; // For the driver's marker
  bool _isDriverIconLoaded = false;
  StreamSubscription? _kijiweSubscription;
  BitmapDescriptor? _kijiweIcon;
  final Set<Marker> _kijiweMarkers = {};
  // Scheduling limits
  int _maxSchedulingDaysAhead = 30; // Default
  int _minSchedulingMinutesAhead = 5; // Default
  double? _estimatedFare; // Declare _estimatedFare
  Map<String, dynamic>? _fareConfig; // Declare _fareConfig
  final TextEditingController _customerNoteController = TextEditingController(); // For the initial note
  String? _processedCompletedRideId; // Flag to prevent re-processing a completed ride

  bool _kijiweFetchInitiated = false; // Flag to ensure kijiwe fetch happens once per lifecycle
  // To safely access providers in dispose() and listeners
  late final LocationProvider _locationProvider;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _locationProvider = Provider.of<LocationProvider>(context, listen: false);
    _locationProvider.addListener(_onLocationUpdated);

    _setupFocusListeners();
    _sheetController.addListener(_onSheetChanged);
    _loadSearchHistory(); 
    _fetchSchedulingLimits();
    _fetchFareConfig(); 

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupInitialMapState(); // Call the new setup method here
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    _kijiweFetchInitiated = false;
  }

  // New listener function to react to location updates
  void _onLocationUpdated() {
    final newLocation = _locationProvider.currentLocation;

    // Check if we have a location and haven't fetched kijiwes in this session yet.
    // This is more robust against hot reloads where _pickupLocation might persist.
    if (!_kijiweFetchInitiated && newLocation != null) {
      _kijiweFetchInitiated = true; // Set flag to prevent re-fetching on every minor location update
      if (mounted) {
        if (_pickupLocation == null) {
          // This is the initial setup. Set the pickup location automatically.
          setState(() {
            _pickupLocation = newLocation;
            _updateGooglePickupMarker(LatLng(newLocation.latitude, newLocation.longitude));
            // Immediately set destination to editing mode.
            _editingDestination = true;
          });
          _reverseGeocode(newLocation, _pickupController);
        }
        _fetchAndDisplayNearbyKijiwes();
      }
    } 
  }

  // Simplified initial setup
  Future<void> _setupInitialMapState() async {
    if (!mounted) return;
    await _loadMarkerIcons(); // Ensure icons are loaded, then initialize state

    // Ensure location provider attempts to get a location
    await _locationProvider.updateLocation();

    // If location is already available when this runs, the listener won't fire.
    // So, we manually trigger the logic if location is already present.
    if (_locationProvider.currentLocation != null) {
      _onLocationUpdated();
    }
  }

  Future<void> _fetchFareConfig() async {
    debugPrint("CustomerHome: _fetchFareConfig - ENTERED function.");
    try {
      debugPrint("CustomerHome: _fetchFareConfig - Attempting to fetch 'appConfiguration/fareSettings' document...");
      final doc = await FirebaseFirestore.instance
          .collection('appConfiguration')
          .doc('fareSettings')
          .get();

      if (!mounted) {
        debugPrint("CustomerHome: _fetchFareConfig - Widget unmounted after fetch. Aborting setState.");
        return;
      }

      if (doc.exists && doc.data() != null) {
        final newFareConfig = doc.data();
        debugPrint("CustomerHome: _fetchFareConfig - Fare config loaded successfully: $newFareConfig");
        setState(() => _fareConfig = newFareConfig);
        // After loading config, check if route data is already available and calculate fare
        if (_selectedRouteDistance != null && _selectedRouteDuration != null) {
           debugPrint("CustomerHome: _fetchFareConfig - Route data already available after config load. Recalculating fare.");
           _calculateEstimatedFare();
        }
      } else {
        debugPrint("CustomerHome: _fetchFareConfig - 'fareSettings' document does not exist.");
        setState(() => _fareConfig = null); 
        _calculateEstimatedFare(); 
      }
    } catch (e, s) { // Added stack trace to the catch block
      debugPrint("CustomerHome: _fetchFareConfig - ERROR fetching fare config: $e");
      debugPrint("CustomerHome: _fetchFareConfig - StackTrace: $s");
      if (mounted) {
        setState(() => _fareConfig = null); 
        // _calculateEstimatedFare(); // Not strictly needed here as _fareConfig is null
      }
    }
    debugPrint("CustomerHome: _fetchFareConfig - EXITED function.");
  }

  // Helper to parse distance and duration strings into numeric values.
  (double, double) _parseRouteDistanceAndDuration() {
    if (_selectedRouteDistance == null || _selectedRouteDuration == null) {
      return (0.0, 0.0);
    }

    // Parse distance
    double distanceKm = 0;
    final distanceMatch = RegExp(r'([\d\.]+)').firstMatch(_selectedRouteDistance!);
    if (distanceMatch != null) {
      double numericValue = double.tryParse(distanceMatch.group(1) ?? '0') ?? 0;
      if (_selectedRouteDistance!.toLowerCase().contains("km")) {
        distanceKm = numericValue;
      } else if (_selectedRouteDistance!.toLowerCase().contains("m")) {
        distanceKm = numericValue / 1000.0;
      } else {
        distanceKm = numericValue;
      }
    }

    // Parse duration
    double durationMinutes = 0;
    final hourMatch = RegExp(r'(\d+)\s*hr').firstMatch(_selectedRouteDuration!);
    if (hourMatch != null) {
      durationMinutes += (double.tryParse(hourMatch.group(1) ?? '0') ?? 0) * 60;
    }
    final minMatch = RegExp(r'(\d+)\s*min').firstMatch(_selectedRouteDuration!);
    if (minMatch != null) {
      durationMinutes += double.tryParse(minMatch.group(1) ?? '0') ?? 0;
    }
    if (durationMinutes == 0 && _selectedRouteDuration!.contains("min")) {
      final simpleMinMatch = RegExp(r'([\d\.]+)').firstMatch(_selectedRouteDuration!);
      if (simpleMinMatch != null) {
        durationMinutes = double.tryParse(simpleMinMatch.group(1) ?? '0') ?? 0;
      }
    }
    return (distanceKm, durationMinutes);
  }

  Future<void> _fetchSchedulingLimits() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('appConfiguration')
          .doc('schedulingSettings')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            _maxSchedulingDaysAhead = data['maxSchedulingDaysAhead'] as int? ?? _maxSchedulingDaysAhead;
            _minSchedulingMinutesAhead = data['minSchedulingMinutesAhead'] as int? ?? _minSchedulingMinutesAhead;
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching scheduling limits: $e. Using defaults.");
    }
  }
  
  void _calculateEstimatedFare() {
    if (!mounted || _fareConfig == null || _selectedRouteDistance == null || _selectedRouteDuration == null) {
      final bool fareChanged = _estimatedFare != null;
      if (fareChanged) {
        setState(() => _estimatedFare = null);
      }
      return;
    }

    final (distanceKm, durationMinutes) = _parseRouteDistanceAndDuration();

    final double baseFare = (_fareConfig!['startingFare'] as num?)?.toDouble() ?? 0.0;
    final double perKmRate = (_fareConfig!['farePerKilometer'] as num?)?.toDouble() ?? 0.0;
    final double perMinRate = (_fareConfig!['farePerMinuteDriving'] as num?)?.toDouble() ?? 0.0;
    final double minFare = (_fareConfig!['minimumFare'] as num?)?.toDouble() ?? 0.0;
    double calculatedFare = baseFare + (distanceKm * perKmRate) + (durationMinutes * perMinRate);
    calculatedFare = calculatedFare > minFare ? calculatedFare : minFare;
    final double roundingInc = (_fareConfig!['roundingIncrement'] as num?)?.toDouble() ?? 0.0;
    if (roundingInc > 0) calculatedFare = (calculatedFare / roundingInc).ceil() * roundingInc;

    if (_estimatedFare != calculatedFare) {
      setState(() => _estimatedFare = calculatedFare);
    }
    debugPrint("CustomerHome: Parsed Distance for fare: ${distanceKm}km, Parsed Duration: ${durationMinutes}min. Calculated Fare: $_estimatedFare");
  }

  Future<void> _loadMarkerIcons() async {
    try {
      _driverIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)), // Adjust size as needed
        'assets/boda_marker.png', // Use your specific driver icon
      );
      if (mounted) setState(() => _isDriverIconLoaded = true);

      _kijiweIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)), // Smaller size for kijiwe
        'assets/kijiwe_marker.png',
      );
      debugPrint("CustomerHome: Kijiwe marker icon loaded successfully.");
      // No separate loaded flag for kijiwe icon, assume it loads or fails with driver icon
    } catch (e) {
      debugPrint("Error loading marker icons: $e");
    }
  }

  Future<void> _fetchAndDisplayNearbyKijiwes() async {
    // =======================================================================
    print("=======================================================================");
    print("CustomerHome: _fetchAndDisplayNearbyKijiwes - ENTERED");

    if (_pickupLocation == null) {
      print("CustomerHome: EXITING _fetchAndDisplayNearbyKijiwes because _pickupLocation is null.");
      print("=======================================================================");
      return;
    }
    if (_kijiweIcon == null) {
      print("CustomerHome: EXITING _fetchAndDisplayNearbyKijiwes because _kijiweIcon is null.");
      print("=======================================================================");
      return;
    }
    print("CustomerHome: Fetching nearby kijiwes around $_pickupLocation...");

    _kijiweSubscription?.cancel(); // Cancel any existing listener
    final firestoreService = Provider.of<FirestoreService>(context, listen: false); // This is correct

    print("CustomerHome: Subscribing to getNearbyKijiwes stream...");
    _kijiweSubscription = firestoreService.getNearbyKijiwes(_pickupLocation!, _kijiweSearchRadiusKm).listen(
      (kijiweDocs) {
        if (!mounted) {
          print("CustomerHome: Stream emitted but widget is not mounted. Ignoring.");
          return;
        }
        print("=======================================================================");
        print("CustomerHome: SUCCESS - Received ${kijiweDocs.length} kijiwe documents from Firestore.");
        final Set<Marker> newMarkers = {};
        for (var doc in kijiweDocs) {
          final data = doc.data() as Map<String, dynamic>?; // Cast to nullable map

          // Defensive check for the nested GeoPoint to prevent crashes from malformed data.
          final positionField = data?['position'];
          if (positionField is Map) {
            final geoPointField = positionField['geopoint'];
            if (geoPointField is GeoPoint) {
              final kijiweId = doc.id;
              final kijiweLocation = LatLng(geoPointField.latitude, geoPointField.longitude);
              final kijiweName = data?['name'] as String? ?? 'Kijiwe';
              print("  - Found Kijiwe: '$kijiweName' at ${geoPointField.latitude}, ${geoPointField.longitude}");

              newMarkers.add(
                Marker(
                  markerId: MarkerId('kijiwe_${doc.id}'),
                  position: kijiweLocation,
                  icon: _kijiweIcon!,
                  infoWindow: InfoWindow(title: kijiweName, snippet: 'Tap for options'),
                  onTap: () => _showKijiweOptionsDialog(kijiweName, kijiweLocation, kijiweId),
                  alpha: 0.8,
                  zIndex: 1,
                ),
              );
            } else {
              print("CustomerHome: Skipping kijiwe document '${doc.id}' because 'position.geopoint' is not a valid GeoPoint. Value: $geoPointField");
            }
          } else {
            print("CustomerHome: Skipping kijiwe document '${doc.id}' due to missing or invalid 'position.geopoint' field.");
          }
        }
        setState(() {
          _kijiweMarkers.clear();
          _kijiweMarkers.addAll(newMarkers);
          print("CustomerHome: Updated map with ${newMarkers.length} kijiwe markers.");
          print("=======================================================================");
        });
      },
      onError: (error) {
        print("=======================================================================");
        if (mounted && error.toString().contains("type 'Null' is not a subtype of type 'GeoPoint'")) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error loading nearby hubs. Some location data may be invalid.')),
          );
        }
        print("=======================================================================");
      },
      onDone: () {
        print("CustomerHome: getNearbyKijiwes stream is DONE.");
      },
    );
  }

  void _showKijiweOptionsDialog(String kijiweName, LatLng kijiweLocation, String kijiweId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(kijiweName),
          content: const Text('What would you like to do?'),
          actions: <Widget>[
            TextButton(
              child: const Text('View Profile'),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => KijiweProfileScreen(kijiweId: kijiweId),
                  ),
                );
              },
            ),
            TextButton(
              child: const Text('Set as Pickup'),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                _setKijiweAsLocation(kijiweName, kijiweLocation, isPickup: true);
              },
            ),
            TextButton(
              child: const Text('Set as Destination'),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                _setKijiweAsLocation(kijiweName, kijiweLocation, isPickup: false);
              },
            ),
          ],
        );
      },
    );
  }

  void _setKijiweAsLocation(String name, LatLng location, {required bool isPickup}) {
    final llLocation = ll.LatLng(location.latitude, location.longitude);
    setState(() {
      if (isPickup) {
        _pickupLocation = llLocation;
        _pickupController.text = name;
        _updateGooglePickupMarker(location);
      } else {
        _dropOffLocation = llLocation;
        _destinationController.text = name;
        _updateGoogleDropOffMarker(location);
      }
      _updateSearchHistory(name); // Add Kijiwe to search history
    });
    _drawRoute(); // Redraw the route with the new location
    _checkRouteReady();
    _collapseSheet();
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

    final bounds = MapUtils.boundsFromLatLngList(points); // Use MapUtils
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
    _sheetController.animateTo(0.23,
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

  Future<void> _reverseGeocode(ll.LatLng location, TextEditingController controller) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty) {
        if (!mounted) return;
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
        _selectingPickup = false;
        _editingPickup = false;
        _editingDestination = true; // Set destination to editing mode
        _pickupFocusNode.unfocus();
        _collapseSheet();
      });
      _reverseGeocode(_pickupLocation!, _pickupController); // Can be outside setState
    } else if (_editingStopIndex != null) {
      setState(() {
        _stops[_editingStopIndex!].location = llTappedLatLng;
        _reverseGeocode(llTappedLatLng, _stops[_editingStopIndex!].controller);
        _updateStopMarker(_editingStopIndex!, tappedLatLng);
        _editingStopIndex = null;
        _stopFocusNode.unfocus();
        _collapseSheet();
        _drawRoute(); // Redraw route if a stop location changes
      });
    } else if (_editingDestination) {
      setState(() {
        _dropOffLocation = llTappedLatLng;
        _updateGoogleDropOffMarker(tappedLatLng);
        _reverseGeocode(_dropOffLocation!, _destinationController);
        _editingDestination = false;
        _destinationFocusNode.unfocus();
        _collapseSheet();
      });
      _drawRoute(); // Draw route after setting destination
    } else if (_dropOffLocation == null && !_editingPickup && _editingStopIndex == null) {
      setState(() {
        _dropOffLocation = llTappedLatLng;
        _updateGoogleDropOffMarker(tappedLatLng);
        _reverseGeocode(_dropOffLocation!, _destinationController);
      });
    }
    _checkRouteReady();
  }

  Future<void> _drawRoute() async {
  if (_pickupLocation == null || _dropOffLocation == null) return;
  
  setState(() {
    // _isLoadingRoute = true; // This is for drawing the customer's proposed route
    _polylines.clear();
    _allFetchedRoutes.clear();
    _selectedRouteIndex = 0;
    _selectedRouteDistance = null;
    _selectedRouteDuration = null;
  });
  
  try {
    final List<ll.LatLng>? waypointsLatLng = _stops
        .where((s) => s.location != null)
        .map((s) => s.location!)
        .toList();

    final List<Map<String, dynamic>>? routes = await MapUtils.getRouteDetails(
      origin: LatLng(_pickupLocation!.latitude, _pickupLocation!.longitude),
      destination: LatLng(_dropOffLocation!.latitude, _dropOffLocation!.longitude),
      apiKey: _googlePlacesApiKey,
      waypoints: waypointsLatLng?.map((ll) => LatLng(ll.latitude, ll.longitude)).toList(),
    );

    if (!mounted) return;

    if (routes != null && routes.isNotEmpty) {
      setState(() {
        _allFetchedRoutes = routes; // Store all fetched routes
        _selectRoute(0); // Select and display the first route by default
      });

      // Adjust camera to fit all points of the first (primary) route initially
      if (_allFetchedRoutes.isNotEmpty) {
        final List<LatLng> primaryRoutePoints = _allFetchedRoutes[0]['points'] as List<LatLng>;
        _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(MapUtils.boundsFromLatLngList(primaryRoutePoints), 100),
        );
      }
    } else {
      // Handle no routes found or API error
      if (mounted) {
        setState(() {
          _polylines.clear();
          _selectedRouteDistance = null;
          _selectedRouteDuration = null;
          _estimatedFare = null; // Explicitly set fare to null
        });
      }
    }
  } catch (e) {
    debugPrint('Error in _drawRoute (CustomerHome): $e');
    if (mounted) {
      setState(() {
        _polylines.clear(); // Also clear polylines on error
        _selectedRouteDistance = null;
        _selectedRouteDuration = null;
        _estimatedFare = null;
        // Inform the user about the failure
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to get route details: $e. Please check your internet connection.')),
          );
        }
      });
    }
    _checkRouteReady();
  }
}

  void _selectRoute(int index) {
    // This method updates all state related to the selected route.
    // It should be called from within a setState() block.
    if (_allFetchedRoutes.isEmpty) return;

    _selectedRouteIndex = index;
    _polylines.clear();
    for (int i = 0; i < _allFetchedRoutes.length; i++) {
      final routeData = _allFetchedRoutes[i];
      final Polyline originalPolyline = routeData['polyline'] as Polyline;

      _polylines.add(originalPolyline.copyWith(
        colorParam: i == _selectedRouteIndex ? Colors.blueAccent : Colors.grey,
        widthParam: i == _selectedRouteIndex ? 6 : 4,
        onTapParam: () => setState(() => _selectRoute(i)), // Cleanly update state on tap
      ));
    }
    _selectedRouteDistance = _allFetchedRoutes[_selectedRouteIndex]['distance'] as String?;
    _selectedRouteDuration = _allFetchedRoutes[_selectedRouteIndex]['duration'] as String?;
    _calculateEstimatedFare(); // Recalculate fare for the newly selected route
  }

  void _listenToActiveRide(String rideId) {
    _stopListeningToActiveRide(); // Cancel any previous subscription first
    final rideRequestProvider = Provider.of<RideRequestProvider>(context, listen: false);

    _activeRideSubscription = rideRequestProvider.getRideStream(rideId).listen((rideDetails) {
      if (!mounted) return;

      // Update the main ride details state
      setState(() {
        _activeRideRequestDetails = rideDetails;
      });

      if (rideDetails == null) {
        // Ride document was deleted or an error occurred.
        _resetUIForNewTrip();
        return;
      }

      final driverId = rideDetails.driverId;
      final rideStatus = rideDetails.status;

      // Handle driver assignment and location tracking
      if (driverId != null) {
        if (['accepted', 'goingToPickup', 'arrivedAtPickup', 'onRide'].contains(rideStatus)) {
          if (_isFindingDriver) setState(() => _isFindingDriver = false);
          if (_driverLocationSubscription == null || _assignedDriverModel?.uid != driverId) {
            setState(() => _assignedDriverModel = UserModel(uid: driverId));
            _startListeningToDriverLocation(driverId);
          }
        }
      } else {
        if (_driverLocationSubscription != null) {
          _stopListeningToDriverLocation();
          setState(() => _assignedDriverModel = null);
        }
      }

      // Handle ride completion flow
      if ((rideStatus == 'completed' || rideStatus.contains('cancelled') || rideStatus == 'no_drivers_available') &&
          rideId == _activeRideRequestId && rideId != _processedCompletedRideId) {
        _processedCompletedRideId = rideId;
        final endMessage = _getRideEndMessage(rideStatus);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(endMessage)));
        if (rideStatus == 'completed' && rideDetails.driverId != null) {
          _showRateDriverDialog(rideId, rideDetails.driverId!);
        } else {
          _resetUIForNewTrip();
        }
      }
    });
  }

  // Update polylines based on selected route
  void _startListeningToDriverLocation(String driverId) {
    _driverLocationSubscription?.cancel(); // Cancel any previous subscription
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    _driverLocationSubscription = firestoreService.getUserDocumentStream(driverId).listen((driverDoc) {
      if (driverDoc.exists && driverDoc.data() != null) {
        final data = driverDoc.data() as Map<String, dynamic>;
        final driverProfile = data['driverProfile'] as Map<String, dynamic>?;
        if (driverProfile != null && driverProfile['currentLocation'] is GeoPoint) {
          final GeoPoint driverGeoPoint = driverProfile['currentLocation'] as GeoPoint;
          final LatLng driverLatLng = LatLng(driverGeoPoint.latitude, driverGeoPoint.longitude);
          final double driverHeading = (driverProfile['currentHeading'] as num?)?.toDouble() ?? 0.0;          

          if (mounted) {
            setState(() {
              _markers.removeWhere((m) => m.markerId.value == 'driver_active_location');
              _markers.add(
                Marker(
                  markerId: const MarkerId('driver_active_location'),
                  position: driverLatLng,
                  icon: _isDriverIconLoaded && _driverIcon != null ? _driverIcon! : BitmapDescriptor.defaultMarker, // Use default if custom not loaded
                  rotation: driverHeading,
                  anchor: const Offset(0.5, 0.5),
                  flat: true,
                  zIndex: 10, // Ensure driver marker is prominent
                ),
              );
              // Zoom to show both driver and pickup location
              if (_pickupLocation != null) {
                final LatLng pickupLatLng = LatLng(_pickupLocation!.latitude, _pickupLocation!.longitude);
                final bounds = MapUtils.boundsFromLatLngList([driverLatLng, pickupLatLng]);
                _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100)); // 100 is padding
              } else {
                // Fallback to just centering on the driver if pickup location is somehow null
                _mapController?.animateCamera(CameraUpdate.newLatLng(driverLatLng));
              }
            });
          }
        }
      }
    }, onError: (error) {
      debugPrint("Error listening to driver location: $error");
    });
  }

  void _stopListeningToDriverLocation() {
    _driverLocationSubscription?.cancel();
    _driverLocationSubscription = null;
    _markers.removeWhere((m) => m.markerId.value == 'driver_active_location');
    // No need to call setState here if the marker removal is part of a larger state reset
  }

  Future<List<Map<String, dynamic>>> _getGooglePlacesSuggestions(String query) async {
    if (query.isEmpty) return [];
    final url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$_googlePlacesApiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body); // Keep json.decode for Google Places API
        if (data['status'] == 'OK') {
          return (data['predictions'] as List).map((p) => {
            'place_id': p['place_id'],
            'description': p['description'],
          }).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching suggestions: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> _getPlaceDetails(String placeId) async {
    final url = 'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_googlePlacesApiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body); // Keep json.decode for Google Places API
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
      debugPrint('Error fetching place details: $e');
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
        //await _reverseGeocode(_pickupLocation!, _pickupController);
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
      
      // _drawRoute(); // REMOVED: This will be called by the dialog's onPressed handler.
    });
    _checkRouteReady();
  }

  void _clearPickup() {
    setState(() {
      _pickupController.clear();
      _pickupLocation = null;
      _selectedRouteDistance = null;
      _selectedRouteDuration = null;
      _markers.removeWhere((m) => m.markerId == const MarkerId('pickup'));
      _drawRoute();
    });
    _checkRouteReady();
  }

  void _clearDestination() {
    setState(() {
      _destinationController.clear();
      _dropOffLocation = null;
      _selectedRouteDistance = null;
      _selectedRouteDuration = null;
      _markers.removeWhere((m) => m.markerId == const MarkerId('dropoff'));
      _drawRoute();
    });
    _checkRouteReady();
  }

  void _clearStop(int index) {
    setState(() {
      _stops[index].controller.clear();
      _stops[index].location = null;
      _selectedRouteDistance = null;
      _selectedRouteDuration = null;
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
    _stops[index].dispose(); // Dispose the stop's controller and focus node
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
    if (_isFindingDriver) return; // Prevent multiple requests

    // Set _isFindingDriver = true HERE, immediately before async work
    if (mounted) {
      // We will set _isFindingDriver and _activeRideRequestId after the ride request is created
      // to ensure _activeRideRequestId is available when _isFindingDriver is true.
      // For now, just show a generic loading state if needed, or rely on button press feedback.
      // setState(() {
      //   _isFindingDriver = true; // Temporarily set to true to show loading
      // });
    }
    final rideRequestProvider = Provider.of<RideRequestProvider>(context, listen: false); // Ensure RideRequestProvider is defined and imported

    if (!mounted || _pickupLocation == null || _dropOffLocation == null) { // Add !mounted check
      // Check mounted BEFORE using context
      if (mounted) { 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select both pickup and drop-off locations')),
        );
        // setState(() => _isFindingDriver = false); // No longer needed here
      }
      return;
    }
    final currentUserId = rideRequestProvider.currentUserId;
    if (!mounted || currentUserId == null) { // Add !mounted check
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not authenticated. Cannot create ride request.')),
        );
        // if (mounted) setState(() => _isFindingDriver = false); // No longer needed here
      }
      return;
    }

    try {        
      // Create a ride request model
      if (mounted) { // Set finding driver true just before the async call
        setState(() => _isFindingDriver = true);
      }
      _processedCompletedRideId = null; // Reset the flag for a new ride
 // Unused variable

      String rideId = await rideRequestProvider.createRideRequest(
        pickup: _pickupLocation!, // _pickupLocation is already ll.LatLng (latlong2.LatLng)
        pickupAddressName: _pickupController.text,
        dropoff: _dropOffLocation!, // _dropOffLocation is already ll.LatLng (latlong2.LatLng)
        estimatedDistanceText: _selectedRouteDistance, // Pass the selected route distance string
        estimatedFare: _estimatedFare, // Pass the calculated estimated fare
        estimatedDurationText: _selectedRouteDuration, // Pass the selected route duration string
        dropoffAddressName: _destinationController.text,
        customerNote: _customerNoteController.text.trim(), // Pass the note
        stops: _stops.map((s) => {
          'name': s.name,
          // s.location is ll.LatLng (latlong2.LatLng), which is what createRideRequest expects for stops' location
          'location': s.location!, 
          'addressName': s.controller.text, // Assuming controller holds the address name
        }).toList(),
      );

      // After await, check if the widget is still mounted before using context or calling setState.
      if (mounted) { 
        setState(() {
          _activeRideRequestId = rideId;
          _isFindingDriver = true;
        });
        // Start listening to the ride document for real-time updates.
        _listenToActiveRide(rideId);
      }
    } catch (e) {
      // After await (in catch), check if the widget is still mounted.
      if (mounted) { 
        // Use the initially captured context for the SnackBar.
        ScaffoldMessenger.of(context).showSnackBar( // Using the current context here, assuming it's still valid if mounted.
          SnackBar(content: Text('Failed to create ride request: $e')),
        );
        // If creation fails, reset both
        setState(() {
          _isFindingDriver = false; _activeRideRequestId = null;}); 
      }
    }
  }

  Future<void> _showAddNoteDialog(String rideId, String? currentNote) async {
    final noteController = TextEditingController(text: currentNote);
    final rideRequestProvider = Provider.of<RideRequestProvider>(context, listen: false);

    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Note to Driver'),
        content: TextField(
          controller: noteController,
          decoration: appInputDecoration(hintText: 'e.g., I am wearing a red shirt'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          ElevatedButton(onPressed: () async {
            await rideRequestProvider.updateCustomerNote(rideId, noteController.text.trim());
            Navigator.pop(dialogContext);
          }, child: const Text('Save Note')),
        ],
      ),
    );
  }

  Future<void> _scheduleRide(
    BuildContext context,
    LatLng pickupLocation,
    LatLng dropOffLocation,
    String pickupAddress,
    String dropOffAddress,
    List<Map<String, dynamic>> stops 
    ) async {
  final TextEditingController titleController = TextEditingController(text: "Scheduled Ride to ${dropOffAddress.isNotEmpty ? dropOffAddress : 'Destination'}");
  DateTime? selectedDate = DateTime.now(); // Default to today
  TimeOfDay? selectedTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))); // Default to one hour from now
  // Recurrence state variables
  bool _isRecurring = false;
  String _recurrenceType = 'None'; // 'None', 'Daily', 'Weekly'
  List<bool> _selectedRecurrenceDays = List.filled(7, false); // For weekly: Mon, Tue, Wed, Thu, Fri, Sat, Sun
  DateTime? _recurrenceEndDate;
  final List<String> _dayAbbreviations = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final theme = Theme.of(context); // Get theme for styling
 
   await showDialog(
      context: context,
      builder: (dialogContext) { // Renamed context to avoid conflict
        return StatefulBuilder( // Use StatefulBuilder to update dialog content
          builder: (stfContext, stfSetState) {
            return AlertDialog(
              title: const Text('Schedule New Ride'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: appInputDecoration(
                      labelText: 'Title',
                      hintText: 'Enter a title for your ride',
                    ),
                  ),
                  verticalSpaceMedium,
                  Text("Select Date & Time:", style: theme.textTheme.titleSmall),
                  verticalSpaceSmall,
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.calendar_today),
                          label: Text(selectedDate != null ? "${selectedDate!.toLocal()}".split(' ')[0] : 'Pick Date'),
                          onPressed: () async {
                            final now = DateTime.now();
                            final DateTime? pickedDate = await showDatePicker(
                              context: stfContext, // Use StatefulBuilder context
                              initialDate: selectedDate ?? now,
                              firstDate: now,
                              lastDate: now.add(Duration(days: _maxSchedulingDaysAhead)),
                            );
                            if (pickedDate != null) {
                              stfSetState(() {
                                selectedDate = pickedDate;
                                // If date changed to today, ensure time is valid
                                if (selectedDate!.isAtSameMomentAs(DateTime(now.year, now.month, now.day))) {
                                  final minTimeToday = now.add(Duration(minutes: _minSchedulingMinutesAhead));
                                  if (selectedTime != null) {
                                    final currentSelectedDateTime = DateTime(selectedDate!.year, selectedDate!.month, selectedDate!.day, selectedTime!.hour, selectedTime!.minute);
                                    if (currentSelectedDateTime.isBefore(minTimeToday)) {
                                      selectedTime = TimeOfDay.fromDateTime(minTimeToday);
                                    }
                                  } else {
                                    selectedTime = TimeOfDay.fromDateTime(minTimeToday);
                                  }
                                }
                              });
                            }
                          },
                        ),
                      ),
                      horizontalSpaceSmall,
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.access_time),
                          label: Text(selectedTime != null ? selectedTime!.format(stfContext) : 'Pick Time'),
                          onPressed: () async {
                            final now = DateTime.now();
                            TimeOfDay initialTime = selectedTime ?? TimeOfDay.fromDateTime(now.add(Duration(minutes: _minSchedulingMinutesAhead + 5))); // Default with a small buffer

                            if (selectedDate != null && selectedDate!.year == now.year && selectedDate!.month == now.month && selectedDate!.day == now.day) {
                              final minTimeToday = now.add(Duration(minutes: _minSchedulingMinutesAhead));
                              if (initialTime.hour < minTimeToday.hour || (initialTime.hour == minTimeToday.hour && initialTime.minute < minTimeToday.minute)) {
                                initialTime = TimeOfDay.fromDateTime(minTimeToday);
                              }
                            }

                            final TimeOfDay? pickedTime = await showTimePicker(
                              context: stfContext, // Use StatefulBuilder context
                              initialTime: initialTime,
                            );
                            if (pickedTime != null) {
                              stfSetState(() => selectedTime = pickedTime);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  verticalSpaceMedium,
                  // --- Recurrence Section ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Repeat this ride?", style: theme.textTheme.titleSmall),
                      Switch(
                        value: _isRecurring,
                        onChanged: (value) {
                          stfSetState(() {
                            _isRecurring = value;
                            if (!_isRecurring) {
                              _recurrenceType = 'None';
                              _selectedRecurrenceDays = List.filled(7, false);
                              _recurrenceEndDate = null;
                            } else {
                              _recurrenceType = 'Daily'; // Default to Daily when enabled
                              _recurrenceEndDate = selectedDate?.add(const Duration(days: 30)); // Default end date
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  if (_isRecurring) ...[
                    verticalSpaceSmall,
                    DropdownButtonFormField<String>(
                      value: _recurrenceType,
                      decoration: appInputDecoration(labelText: 'Frequency'),
                      items: ['Daily', 'Weekly']
                          .map((label) => DropdownMenuItem(
                                value: label,
                                child: Text(label),
                              ))
                          .toList(),
                      onChanged: (value) {
                        stfSetState(() {
                          _recurrenceType = value!;
                          if (_recurrenceType != 'Weekly') {
                            _selectedRecurrenceDays = List.filled(7, false);
                          }
                        });
                      },
                    ),
                    if (_recurrenceType == 'Weekly') ...[
                      verticalSpaceSmall,
                      Text("Repeat on:", style: theme.textTheme.bodyMedium),
                      Wrap( // Using Wrap for days of the week
                        spacing: 6.0,
                        runSpacing: 0.0,
                        children: List<Widget>.generate(7, (index) {
                          return FilterChip(
                            label: Text(_dayAbbreviations[index]),
                            selected: _selectedRecurrenceDays[index],
                            onSelected: (bool selected) {
                              stfSetState(() {
                                _selectedRecurrenceDays[index] = selected;
                              });
                            },
                          );
                        }),
                      ),
                    ],
                    verticalSpaceSmall,
                    ElevatedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(_recurrenceEndDate != null ? "Repeat until: ${_recurrenceEndDate!.toLocal()}".split(' ')[0] : 'Set End Date'),
                      onPressed: () async {
                        final DateTime? pickedEndDate = await showDatePicker(
                          context: stfContext,
                          initialDate: _recurrenceEndDate ?? selectedDate!.add(const Duration(days: 30)),
                          firstDate: selectedDate!.add(const Duration(days: 1)), // End date must be after selectedDate
                          lastDate: DateTime.now().add(const Duration(days: 365 * 2)), // Max 2 years for recurrence
                        );
                        if (pickedEndDate != null) stfSetState(() => _recurrenceEndDate = pickedEndDate);
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (titleController.text.isNotEmpty && selectedDate != null && selectedTime != null) {
                      final DateTime scheduledDateTime = DateTime(
                        selectedDate!.year, selectedDate!.month, selectedDate!.day,
                        selectedTime!.hour, selectedTime!.minute,
                      );
                      final DateTime now = DateTime.now();
                      final DateTime minValidDateTime = now.add(Duration(minutes: _minSchedulingMinutesAhead));

                      if (_isRecurring && _recurrenceType == 'Weekly' && !_selectedRecurrenceDays.contains(true)) {
                        ScaffoldMessenger.of(stfContext).showSnackBar(
                          const SnackBar(content: Text('Please select at least one day for weekly recurrence.')),
                        );
                        return;
                      }
                      if (_isRecurring && _recurrenceEndDate == null) {
                        ScaffoldMessenger.of(stfContext).showSnackBar(
                          const SnackBar(content: Text('Please set an end date for the recurring ride.')),
                        );
                        return;
                      }

                      if (scheduledDateTime.isBefore(minValidDateTime)) {
                        ScaffoldMessenger.of(stfContext).showSnackBar(
                          SnackBar(content: Text('Scheduled time must be at least $_minSchedulingMinutesAhead minutes from now.')),
                        );
                        return;
                      }
                      Navigator.of(dialogContext).pop(true); // Return true for save
                    } else {
                      ScaffoldMessenger.of(stfContext).showSnackBar(
                        const SnackBar(content: Text('Please provide a title, date, and time')),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    ).then((saved) async { // Handle the result of the dialog
  if (saved == true && titleController.text.isNotEmpty && selectedDate != null && selectedTime != null) {
    final DateTime scheduledDateTime = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
      selectedTime!.hour,
      selectedTime!.minute,
    );
    final rideRequestProvider = Provider.of<RideRequestProvider>(context, listen: false);
    final String? customerId = rideRequestProvider.authService.currentUser?.uid;

    if (customerId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: User not authenticated.')));
      return;
    }
    try {
      final rideData = {
        'customerId': customerId, // Use the passed customerId
        'title': titleController.text,
        'scheduledDateTime': Timestamp.fromDate(scheduledDateTime), // Store as Timestamp
        'createdAt': FieldValue.serverTimestamp(), // Use server timestamp
        'pickup': GeoPoint(pickupLocation.latitude, pickupLocation.longitude), // Use 'pickup'
        'dropoff': GeoPoint(dropOffLocation.latitude, dropOffLocation.longitude), // Use 'dropoff'
        'pickupAddressName': pickupAddress,
        'dropoffAddressName': dropOffAddress,
        'status': 'scheduled',
          'isRecurring': _isRecurring,
          'recurrenceType': _isRecurring ? _recurrenceType : null,
          'recurrenceDaysOfWeek': _isRecurring && _recurrenceType == 'Weekly'
              ? _selectedRecurrenceDays.asMap().entries.where((e) => e.value).map((e) => _dayAbbreviations[e.key]).toList()
              : null,
          'recurrenceEndDate': _isRecurring && _recurrenceEndDate != null ? Timestamp.fromDate(_recurrenceEndDate!) : null,
        'stops': stops.map((stop) => { // 'stops' is already List<Map<String, dynamic>>
          'name': stop['name'],
          'location': stop['location'], // This is already GeoPoint? from the argument
          'addressName': stop['addressName'], // This is String? from the argument
        }).toList(),
      };

      await FirebaseFirestore.instance.collection('scheduledRides').add(rideData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride scheduled successfully!')),
        );
        debugPrint("CustomerHome: Attempting to show post-scheduling dialog."); // <--- ADD THIS
        _showPostSchedulingDialog(); // Show the new dialog
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to schedule ride: $e')),
        );
      }
    }
  }});
}
  void _showPostSchedulingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // User must choose an option
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Ride Scheduled!'),
          content: const Text('What would you like to do next?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Plan Another Ride'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _resetUIForNewTrip();
              },
            ),
            TextButton(
              child: const Text('View Scheduled Rides'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ScheduledRidesListWidget()),
                );
                _resetUIForNewTrip(); // Also clear form after navigating
              },
            ),
            TextButton(
              child: const Text('Continue Editing'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                // Do nothing, user stays on the current screen with the route
              },
            ),
          ],
        );
      },
    );
  }

  void _resetUIForNewTrip() {
    setState(() {
      _pickupController.clear();
      _destinationController.clear();
      _stops.forEach((stop) => stop.controller.clear());
      _stops.clear();

      _pickupLocation = null;
      _dropOffLocation = null;

      _markers.clear();
      _polylines.clear();

      _selectedRouteDistance = null;
      _selectedRouteDuration = null;
      _estimatedFare = null;
      _routeReady = false;

      // Clear suggestion lists so history can be shown
      _pickupSuggestions = [];
      _destinationSuggestions = [];
      _stopSuggestions = [];
      // _processedCompletedRideId = null; // DO NOT reset this here. It's reset when a new ride is created.

      // Reset editing states
      _editingPickup = false;
      _editingDestination = true; // Set to false, user will tap to edit
      _editingStopIndex = null;

      _pickupFocusNode.unfocus();
      _destinationFocusNode.unfocus();
      _stopFocusNode.unfocus();

      // Also reset the active ride state
      _activeRideRequestId = null;
      _activeRideRequestDetails = null;
      _assignedDriverModel = null;
      _isFindingDriver = false;
      _stopListeningToActiveRide(); // Cancel the active ride subscription
      _stopListeningToDriverLocation();

      // Reset the flag to allow initial location setup to run again.
      _kijiweFetchInitiated = false;
    });
    // Re-initialize pickup location and collapse sheet to default
      _setupInitialMapState(); // Call the new setup method here
  }

  Widget _buildLocationField({
    required Key key, // Add key
    required TextEditingController controller,
    String? legDistance, // New parameter for leg-specific distance
    String? legDuration, // New parameter for leg-specific duration
    required String labelText,
    required String hintText,
    required IconData iconData,
    required Color iconColor,
    required bool isEditing,
    required FocusNode focusNode,
    required VoidCallback onTapWhenNotEditing, // For InkWell
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
    required VoidCallback onMapIconTap,
  }) {
    final theme = Theme.of(context);
    List<String> labelParts = [labelText];
    if (legDuration != null && legDistance != null && legDuration.isNotEmpty && legDistance.isNotEmpty) {
      labelParts.add('($legDuration · $legDistance)');
    }
    final String displayLabel = labelParts.join(' ');

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(displayLabel, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary.withOpacity(0.8))),
        verticalSpaceSmall,
        if (isEditing)
          TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: appInputDecoration( // Using appInputDecoration
                hintText: hintText,
                prefixIcon: Icon(iconData, color: iconColor),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (controller.text.isNotEmpty) IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: onClear),
                    IconButton(icon: const Icon(Icons.map_outlined, size: 20), onPressed: onMapIconTap),
                  ],
                )),
            onChanged: onChanged,
            onTap: _expandSheet, // Expand sheet when text field is tapped
            onSubmitted: (_) => _collapseSheet(), // Collapse sheet on submit
          )
        else
          InkWell(onTap: onTapWhenNotEditing, child: _buildFieldContainer(Row(children: [Icon(iconData, color: iconColor), horizontalSpaceMedium, Expanded(child: controller.text.isEmpty ? Text(hintText, style: appTextStyle(color: theme.hintColor)) : Text(controller.text, style: theme.textTheme.bodyLarge))]))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final locationProvider = Provider.of<LocationProvider>(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          if (locationProvider.currentLocation == null)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  verticalSpaceMedium,
                  Text('Fetching your location...'),
                ],
              ),
            )
          else
            GoogleMap(
              mapType: MapType.normal,
              initialCameraPosition: CameraPosition(
                target: LatLng(
                  locationProvider.currentLocation!.latitude,
                  locationProvider.currentLocation!.longitude,
                ),
                zoom: 15, // Start with a more zoomed-in view
              ),
              onMapCreated: (controller) {
                _mapController = controller;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _adjustMapForExpandedSheet();
                });
              },
              onTap: _handleMapTap,
              markers: {..._markers, ..._kijiweMarkers},
              polylines: _polylines,
              zoomControlsEnabled: false,
              myLocationEnabled: true,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).size.height * _currentSheetSize,
              ),
            ),
          // The DraggableScrollableSheet is now built directly, using the state
          // variables (_activeRideRequestDetails, _isFindingDriver) that are
          // updated by our new _listenToActiveRide subscription.
          _buildRouteSheet(key: const ValueKey('main_sheet')),

      // Custom Map Controls (Recenter and Zoom) - only show when not in an active ride
      if (_activeRideRequestDetails == null)
          Positioned(
            bottom: MediaQuery.of(context).size.height * _currentSheetSize + 20, // Position above the sheet
            right: 16,
            child: Column(
              children: [
                // Recenter Button
                FloatingActionButton.small(
              heroTag: 'customer_recenter_button',
                  onPressed: _centerMapOnCurrentLocation,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 16),
                // Zoom Buttons
                FloatingActionButton.small(
              heroTag: 'customer_zoom_in_button', // Unique heroTag
                  onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 2),
                FloatingActionButton.small(
              heroTag: 'customer_zoom_out_button', // Unique heroTag
                  onPressed: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getRideEndMessage(String? status) {
    switch (status) {
      case 'completed':
        return 'Ride completed!';
      case 'cancelled_by_customer':
        return 'Ride cancelled by you.';
      case 'cancelled_by_driver':
        return 'Ride cancelled by driver.';
      case 'no_drivers_available':
        return 'No drivers available at the moment. Please try again later.';
      case 'matching_error_missing_pickup':
      case 'matching_error_kijiwe_fetch':
        return 'There was an error matching your ride. Please check your pickup or try again.';
      default:
        return 'Ride has ended.';
    }
  }

  Future<void> _centerMapOnCurrentLocation() async {
    if (_mapController == null) return;

    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    // Prioritize centering on the selected pickup location, otherwise use the user's current location.
    final targetLocation = _pickupLocation ?? locationProvider.currentLocation;

    if (targetLocation == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Current location not available.')),
        );
      }
      return;
    }

    final currentZoom = await _mapController!.getZoomLevel();

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(targetLocation.latitude, targetLocation.longitude), zoom: currentZoom, bearing: 0),
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

  Widget _buildRouteSheet({Key? key}) { // Removed Key parameter as it's managed by the parent IndexedStack
    // If a driver is assigned, show driver info and ride progress
    final rideDetails = _activeRideRequestDetails;
    if (rideDetails != null) {
      final status = rideDetails.status;
      final driverId = rideDetails.driverId;

      // Active ride with an assigned driver
      if (driverId != null && ['pending_driver_acceptance', 'accepted', 'goingToPickup', 'arrivedAtPickup', 'onRide'].contains(status)) {
        debugPrint("CustomerHome: _buildRouteSheet -> Showing DriverAssignedSheet. Status: $status");
        return _buildDriverAssignedSheet();
      }

      // Ride was declined or no drivers found
      if (status == 'declined_by_driver' || status == 'no_drivers_available') {
        debugPrint("CustomerHome: _buildRouteSheet -> Showing RideFailedSheet. Status: $status");
        return _buildRideFailedSheet(status);
      }

      // Still finding a driver
      if (_isFindingDriver || status == 'pending_match' || status == 'pending_driver_acceptance') {
        debugPrint("CustomerHome: _buildRouteSheet -> Showing FindingDriverSheet. Status: $status");
        return _buildFindingDriverSheet();
      }
    } else if (_isFindingDriver) { // Handle case where rideDetails is momentarily null but we are finding
      return _buildFindingDriverSheet();
    }
    // Default: Show route planning sheet
    debugPrint("CustomerHome: _buildRouteSheet -> Showing default route planning sheet. Estimated Fare: $_estimatedFare");
    final bool showActionButtons = _pickupLocation != null && _dropOffLocation != null && !_isFindingDriver && _activeRideRequestId == null;
     // Revert to static sheet sizes
    const double initialSheetSize = 0.55;
    const List<double> snapSizes = [0.23, 0.35, 0.45, 0.55, 0.7, 0.8, 0.9]; // Added 0.23 as a snap point
    const double minSheetSize = 0.2;
 
    return DraggableScrollableSheet( // This is the route planning sheet
      key: key, // Apply the key here
      controller: _sheetController,
      initialChildSize: initialSheetSize, // Use the static initial size
      minChildSize: minSheetSize,
      maxChildSize: 1.0,
      snap: true,
      snapSizes: snapSizes, // Use the dynamic snapSizes variable
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
                            child: Row(
                              children: [
                                Text(
                                  'Your route',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const Spacer(),
                                // Swap button (only show if both pickup and destination are set)
                                if (_pickupLocation != null && _dropOffLocation != null)
                                  IconButton(
                                    icon: const Icon(Icons.swap_vert, size: 24),
                                    tooltip: 'Swap locations',
                                    onPressed: _swapLocations,
                                  ),
                                // Add Stop button (only show if pickup and destination are set)
                                if (_pickupLocation != null && _dropOffLocation != null) 
                                  IconButton(
                                    icon: const Icon(Icons.add_location_alt_outlined),
                                    tooltip: 'Add Stop',
                                    onPressed: _addStop,
                                  ),
                                // Expand/Collapse toggle
                                IconButton(
                                  icon: Icon(_isSheetExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
                                  tooltip: _isSheetExpanded ? 'Collapse Sheet' : 'Expand Sheet',
                                  onPressed: () {
                                    if (_isSheetExpanded) {
                                      _collapseSheet();
                                    } else {
                                      _expandSheet();
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          
                          // Route Info (Distance and Duration)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), // Use spacing constants?
                            child: Row(
                              children: [
                                Icon(Icons.access_time, size: 20, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7)),
                                horizontalSpaceSmall,
                                Expanded( // Allow text to take available space
                                  child: Text(
                                    _selectedRouteDistance != null && _selectedRouteDuration != null
                                        ? '$_selectedRouteDuration · $_selectedRouteDistance'
                                        : 'Calculating route...', // Placeholder if distance/duration not ready
                                    style: Theme.of(context).textTheme.bodyMedium,
                                    overflow: TextOverflow.ellipsis, // Handle long text
                                  ),
                                ),
                                horizontalSpaceSmall, // Space before fare
                                // Fare display part
                                Builder(builder: (context) {
                                  final currentFare = _estimatedFare;
                                  // This log will now always execute when this part of the sheet is built
                                  debugPrint("CustomerHome: DraggableSheet Builder - RENDERING FARE. CurrentFare: $currentFare, Distance: $_selectedRouteDistance, Duration: $_selectedRouteDuration");
                                  if (currentFare != null && _selectedRouteDistance != null && _selectedRouteDuration != null) {
                                    return Text(
                                      'Fare: TZS ${currentFare == currentFare.roundToDouble() ? currentFare.toStringAsFixed(0) : currentFare.toStringAsFixed(2)}',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                                    );
                                  } else if (_selectedRouteDistance != null && _selectedRouteDuration != null) {
                                      return Text(
                                        'Fare: Calculating...',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: Theme.of(context).hintColor),
                                      );
                                  }
                                  return const SizedBox.shrink(); // If no distance/duration, don't show fare text yet
                                }),
                                ],
                              ),
                            ),
                          
                          // Pickup Field (conditionally shown)
                          // Show if pickup is not set (needs input) OR if action buttons are visible (for review/edit)
                          if (_pickupLocation == null || showActionButtons)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
                              child: Row( // Wrap _buildLocationField and Add Stop button in a Row
                                children: [
                                  Expanded(
                                    child: _buildLocationField(
                                      key: const ValueKey('pickup_field'),
                                      controller: _pickupController,
                                      labelText: 'Pickup Location',
                                      hintText: 'Enter pickup location',
                                      iconData: Icons.my_location,
                                      iconColor: successColor,
                                      isEditing: _editingPickup,
                                      focusNode: _pickupFocusNode,
                                      onTapWhenNotEditing: () => _startEditing('pickup'),
                                      onChanged: (value) async { if (value.isNotEmpty) { final suggestions = await _getGooglePlacesSuggestions(value); setState(() => _pickupSuggestions = suggestions); } else { setState(() => _pickupSuggestions = []); } },
                                      onClear: _clearPickup,
                                      onMapIconTap: () { setState(() { _selectingPickup = true; _editingPickup = true; }); _collapseSheet(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tap on map to select pickup location'))); },
                                    ),
                                  ),
                                // X button to clear pickup
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  tooltip: 'Clear Pickup',
                                  onPressed: () {
                                      _clearPickup();
                                      setState(() {
                                        _editingPickup = true;
                                        _pickupFocusNode.requestFocus();
                                      });
                                    },
                                  ),                                ],
                              ),
                            ),
                          if (_editingPickup) // Suggestions list for pickup
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16), 
                              child: Column(
                                children: _buildSuggestionList(_pickupSuggestions, true, null),
                              ),
                            ),
                          
                          // Stops Section with + button for each stop
                          if (_stops.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), 
                              child: Column(
                                children: _stops.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final stop = entry.value;
                                  return _buildStopItem(index, stop); // _buildStopItem will now use _buildLocationField
                                }).toList(),
                              ),
                            ),
                          
                          // Destination Field
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _buildLocationField(
                                    key: const ValueKey('destination_field'),
                                    controller: _destinationController,
                                    labelText: 'Destination',
                                    legDistance: () { // Calculate leg distance for destination
                                      if (_allFetchedRoutes.isNotEmpty &&
                                          _selectedRouteIndex < _allFetchedRoutes.length &&
                                          _allFetchedRoutes[_selectedRouteIndex]['legs'] is List) {
                                        final legs = _allFetchedRoutes[_selectedRouteIndex]['legs'] as List<dynamic>;
                                        final destLegIndex = _stops.length; // The leg leading to destination
                                        if (destLegIndex < legs.length && legs[destLegIndex] is Map<String, dynamic>) {
                                          final legData = legs[destLegIndex] as Map<String, dynamic>;
                                          if (legData['distance'] is Map<String, dynamic>) {
                                            return (legData['distance'] as Map<String, dynamic>)['text'] as String?;
                                          } // Removed the direct cast fallback as it was causing the error
                                        }
                                      }
                                      return null;
                                    }(),
                                    legDuration: () { // Calculate leg duration for destination
                                       if (_allFetchedRoutes.isNotEmpty &&
                                          _selectedRouteIndex < _allFetchedRoutes.length &&
                                          _allFetchedRoutes[_selectedRouteIndex]['legs'] is List) {
                                        final legs = _allFetchedRoutes[_selectedRouteIndex]['legs'] as List<dynamic>;
                                        final destLegIndex = _stops.length; // The leg leading to destination
                                        if (destLegIndex < legs.length && legs[destLegIndex] is Map<String, dynamic>) {
                                          final legData = legs[destLegIndex] as Map<String, dynamic>;
                                          if (legData['duration'] is Map<String, dynamic>) {
                                            return (legData['duration'] as Map<String, dynamic>)['text'] as String?;
                                          }
                                        }
                                      }
                                      return null;
                                    }(),
                                    hintText: 'Where to?',
                                    iconData: Icons.flag_outlined,
                                    iconColor: Theme.of(context).colorScheme.error,
                                    isEditing: _editingDestination,
                                    focusNode: _destinationFocusNode,
                                    onTapWhenNotEditing: () => _startEditing('destination'),
                                    onChanged: (value) async { if (value.isNotEmpty) { final suggestions = await _getGooglePlacesSuggestions(value); setState(() => _destinationSuggestions = suggestions); } else { setState(() => _destinationSuggestions = []); } },
                                    onClear: _clearDestination,
                                    onMapIconTap: () { setState(() => _editingDestination = true); _collapseSheet(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tap on map to select destination'))); },
                                  ),
                                ),
                                if (_pickupLocation != null && _dropOffLocation != null) // Show swap button if both are set
                                  IconButton(
                                    icon: const Icon(Icons.clear),
                                    tooltip: 'Clear Destination',
                                    onPressed: () {
                                        _clearDestination();
                                        setState(() {
                                          _editingDestination = true;
                                          _destinationFocusNode.requestFocus();
                                        });
                                      },                                 
                              ),
                              ],
                            ),
                          ),
                          
                          if (_editingDestination) // Suggestions list for destination
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                children: _buildSuggestionList(_destinationSuggestions, false, null),
                              ),
                            ),
                          
                          // "Add Note to Driver" field - moved here
                          if (showActionButtons)
                            Padding(
                              key: const ValueKey('customer_note_field_padding'), // Add key
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: TextField(
                                key: const ValueKey('customer_note_textfield'), // Add key
                                controller: _customerNoteController,
                                decoration: appInputDecoration( // Use appInputDecoration
                                  labelText: 'Note to Driver (Optional)', // Added labelText
                                  hintText: 'e.g., I am at the main gate',
                                  prefixIcon: Icon(Icons.note_add_outlined, color: Theme.of(context).hintColor),
                                ),
                                maxLines: 2,
                                onTap: () { // Ensure sheet expands when note field is tapped
                                  _expandSheet();
                                  _startEditing('note'); // A generic field name, or handle focus differently
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    
                    SliverToBoxAdapter(
                      // Adjust spacing based on sheet expansion
                      child: SizedBox(height: _isSheetExpanded ? 120 : 80), 
                    ),
                  ],
                ),
              ),
              
              // Action Buttons (only shown when both pickup and destination are set)
              if (showActionButtons) // Use the boolean flag
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
                            _stops.map((stop) => {
                              'name': stop.name,
                              'location': stop.location != null
                                  ? GeoPoint(stop.location!.latitude, stop.location!.longitude)
                                  : null,
                              'addressName': stop.controller.text, // Pass addressName
                            }).toList(),
                          ),
                          // Style comes from OutlinedButtonThemeData
                          style: Theme.of(context).outlinedButtonTheme.style?.copyWith(
                                minimumSize: MaterialStateProperty.all(const Size(double.infinity, 50)),
                              ),
                          child: const Text('Schedule'),
                        ),
                      ),
                      horizontalSpaceMedium,
                      Expanded(
                        flex: 3, // Confirm Route button larger
                        child: ElevatedButton(
                          onPressed: _estimatedFare != null ? _confirmRideRequest : null, // Disable if no fare
                          style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                                minimumSize: MaterialStateProperty.all(const Size(double.infinity, 50)),
                              ),
                          child: Text(_estimatedFare != null ? 'Confirm Route' : 'Calculating Fare...', style: const TextStyle(color: Colors.white)),
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

  Widget _buildFindingDriverSheet() {
    final theme = Theme.of(context);
    return Positioned( // Use Positioned to overlay or place at bottom
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, -2)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: theme.colorScheme.primary),
            verticalSpaceMedium,
            Text(
              'Finding a driver for you...',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            verticalSpaceMedium,
            OutlinedButton( // Changed to OutlinedButton for better visibility
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
              ),
              onPressed: () async { // Make this async
                if (_activeRideRequestId != null) {
                  // Capture context-dependent items BEFORE await
                  final rideProvider = Provider.of<RideRequestProvider>(context, listen: false);
                  final scaffoldMessenger = ScaffoldMessenger.of(context); // Capture ScaffoldMessenger
                  final bool isMounted = mounted; // Capture mounted state

                  try {
                    await rideProvider.cancelRideByCustomer(_activeRideRequestId!);
                    // StreamBuilder will handle UI reset when status changes to cancelled
                  } catch (e) {
                    if (isMounted) { // Use captured mounted state
                      scaffoldMessenger.showSnackBar( // Use captured ScaffoldMessenger
                        SnackBar(content: Text('Failed to cancel ride: $e')),
                      );
                    } else {
                      debugPrint("Cancel ride failed, but widget was unmounted: $e");
                    }
                  }
                } else {
                  debugPrint("Cancel Search pressed, but _activeRideRequestId is null.");
                  if (mounted) { // Check mounted before showing SnackBar
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot cancel: Ride request not fully processed.')));
                  }
                }
              },
              child: Text('Cancel Search', style: TextStyle(color: theme.colorScheme.error)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRideFailedSheet(String status) {
    final theme = Theme.of(context);
    final message = status == 'declined_by_driver'
        ? 'The driver is unavailable. Would you like to find another?'
        : 'No drivers were found nearby. Please try again.';

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('😪', style: TextStyle(fontSize: 40)), // Replaced icon with emoji
            verticalSpaceMedium,
            Text(message, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            verticalSpaceMedium,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _activeRideRequestId = null;
                      _isFindingDriver = false;
                    }),
                    child: const Text('Cancel'),
                  ),
                ),
                horizontalSpaceMedium,
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirmRideRequest, // Re-run the ride request logic
                    child: const Text('Find Another Driver'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverAssignedSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.4, // Adjust initial size as needed
      minChildSize: 0.25,
      maxChildSize: 0.6, // Adjust max size
      builder: (BuildContext context, ScrollController scrollController) {
        final theme = Theme.of(context);
        final rideDetails = _activeRideRequestDetails;

        if (rideDetails == null) {
          return Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, -2))],
            ),
            child: const Center(child: Text("Waiting for ride details..."))
          );
        }

        final rideStatus = rideDetails.status;

        // Loading/waiting state
        if (rideStatus == 'pending_driver_acceptance' || (rideDetails.driverId != null && rideDetails.driverName == null)) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, -2))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Make column take minimum space
              mainAxisAlignment: MainAxisAlignment.center, // Center content
              children: [
                CircularProgressIndicator(color: theme.colorScheme.primary),
                verticalSpaceMedium,
                Text(
                  rideStatus == 'pending_driver_acceptance' ? 'Waiting for driver to accept...' : 'Driver assigned. Loading details...',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                verticalSpaceSmall,
                if (rideStatus == 'pending_driver_acceptance')
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error, side: BorderSide(color: theme.colorScheme.error)),
                    onPressed: () async {
                      if (_activeRideRequestId != null) {
                        final rideProvider = Provider.of<RideRequestProvider>(context, listen: false);
                        try { await rideProvider.cancelRideByCustomer(_activeRideRequestId!); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to cancel: $e'))); }
                      }
                    },
                    child: const Text('Cancel Ride'),
                  ),
              ],
            ),
          );
        }

        // Main content for assigned driver
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12, offset: Offset(0, -2))],
          ),
          child: ListView( // Changed to ListView for scrolling
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Center( // Drag handle
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: theme.colorScheme.outline.withOpacity(0.5), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              if (rideDetails.driverProfileImageUrl != null && rideDetails.driverProfileImageUrl!.isNotEmpty)
                Center(child: CircleAvatar(radius: 30, backgroundImage: NetworkImage(rideDetails.driverProfileImageUrl!)))
              else
                Center(child: CircleAvatar(radius: 30, backgroundColor: theme.colorScheme.primaryContainer, child: Icon(Icons.drive_eta, size: 30, color: theme.colorScheme.onPrimaryContainer))),
              verticalSpaceSmall,
              Center(child: Text(rideDetails.driverName ?? 'Driver', style: theme.textTheme.titleLarge)),
              if (rideDetails.driverVehicleType != null && rideDetails.driverVehicleType != "N/A")
                Center(child: Text('Vehicle: ${rideDetails.driverVehicleType}', style: theme.textTheme.bodySmall)),
              
              Builder(builder: (context) {
                final gender = rideDetails.driverGender;
                final ageGroup = rideDetails.driverAgeGroup;
                List<String> details = [];
                if (gender != null && gender.isNotEmpty && gender != "Unknown") details.add(gender); 
                if (ageGroup != null && ageGroup.isNotEmpty && ageGroup != "Unknown") details.add(ageGroup);
                if (details.isNotEmpty) {
                  return Center(child: Text(details.join(', '), style: theme.textTheme.bodySmall));
                }
                return const SizedBox.shrink();
              }),
              verticalSpaceSmall,
              if (rideDetails.driverAverageRating != null && rideDetails.driverAverageRating! > 0)
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, color: accentColor, size: 16),
                      horizontalSpaceSmall,
                      Text(rideDetails.driverAverageRating!.toStringAsFixed(1), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                      if (rideDetails.driverCompletedRidesCount != null && rideDetails.driverCompletedRidesCount! > 0)
                        Padding(padding: const EdgeInsets.only(left: 8.0), child: Text("(${rideDetails.driverCompletedRidesCount} rides)", style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor))),
                    ],
                  ),
                ),
              // License number - now visible if content scrolls
              if (rideDetails.driverLicenseNumber != null && rideDetails.driverLicenseNumber!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Center(child: Text('License: ${rideDetails.driverLicenseNumber}', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor))),
                ),
              verticalSpaceSmall,
              Center(
                child: Chip(
                  label: Text('Status: $rideStatus', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
                  backgroundColor: theme.colorScheme.secondaryContainer,
                ),
              ),
              verticalSpaceMedium,
              // Chat with Driver Button
              if (rideDetails.driverId != null && (rideStatus == 'accepted' || rideStatus == 'goingToPickup' || rideStatus == 'arrivedAtPickup' || rideStatus == 'onRide'))
                TextButton.icon(
                  icon: Icon(Icons.chat_bubble_outline, color: theme.colorScheme.primary),
                  label: Text('Chat with Driver', style: TextStyle(color: theme.colorScheme.primary)),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(
                      rideRequestId: rideDetails.id!,
                      recipientId: rideDetails.driverId!,
                      recipientName: rideDetails.driverName ?? "Driver",
                    ),
                    ));
                  },
                ),
              // Add/Edit Note Button
              if (rideStatus == 'accepted' || rideStatus == 'goingToPickup')
                TextButton.icon(
                  icon: Icon(Icons.edit_note_outlined, color: theme.colorScheme.secondary),
                  label: Text(rideDetails.customerNoteToDriver != null && rideDetails.customerNoteToDriver!.isNotEmpty ? 'Edit Note' : 'Add Note for Driver', style: TextStyle(color: theme.colorScheme.secondary)),
                  onPressed: () => _showAddNoteDialog(rideDetails.id!, rideDetails.customerNoteToDriver),
                ),
              // Cancel Ride Button
              if (rideStatus != 'onRide' && rideStatus != 'completed' && !rideStatus.contains('cancelled'))
                Padding(
                  padding: const EdgeInsets.only(top: 8.0), // Add some space above
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error, side: BorderSide(color: theme.colorScheme.error)),
                    onPressed: () async {
                      if (_activeRideRequestId != null) {
                        try { await Provider.of<RideRequestProvider>(context, listen: false).cancelRideByCustomer(_activeRideRequestId!); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to cancel ride: $e'))); }
                      }
                    },
                    child: const Text('Cancel Ride'),
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
    String? legDistanceText;
    String? legDurationText;

    // Safely access and parse leg data for this stop
    if (_allFetchedRoutes.isNotEmpty &&
        _selectedRouteIndex < _allFetchedRoutes.length &&
        _allFetchedRoutes[_selectedRouteIndex]['legs'] is List) {
      final legs = _allFetchedRoutes[_selectedRouteIndex]['legs'] as List<dynamic>;
      // The leg at 'index' leads TO this stop 'index'.
      if (index < legs.length && legs[index] is Map<String, dynamic>) {
        final legData = legs[index] as Map<String, dynamic>;
        if (legData['distance'] is Map<String, dynamic>) {
          legDistanceText = (legData['distance'] as Map<String, dynamic>)['text'] as String?;
        }
        if (legData['duration'] is Map<String, dynamic>) {
          legDurationText = (legData['duration'] as Map<String, dynamic>)['text'] as String?;
        }
      }
    }
    
    return Padding( // Added Padding around the stop item
      key: ObjectKey(_stops[index]), // Key for the Padding, helps with list updates
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start, // Align items to the top
            children: [
              Expanded(
                child: Dismissible(
                  key: ValueKey('stop_dismissible_$index'), // Unique key for Dismissible
                  direction: DismissDirection.endToStart,
                  background: Container(
                    decoration: BoxDecoration(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(Icons.delete, color: theme.colorScheme.onErrorContainer),
                  ),
                  onDismissed: (direction) => _removeStop(index),
                  child: _buildLocationField( // Use the new _buildLocationField
                    key: ValueKey('stop_field_$index'), // Key for the location field itself
                    controller: stop.controller,
                    labelText: 'Stop ${index + 1}',
                    legDistance: legDistanceText, // Pass calculated leg distance
                    legDuration: legDurationText, // Pass calculated leg duration
                    hintText: 'Add stop location',
                    iconData: Icons.location_on_outlined, // Or a numbered icon
                    iconColor: theme.primaryColor.withOpacity(0.7),
                    isEditing: isEditing,
                    focusNode: stop.focusNode, // Use stop's own focus node
                    onTapWhenNotEditing: () => _startEditing('stop_$index'),
                    onChanged: (value) async { if (value.isNotEmpty) { final suggestions = await _getGooglePlacesSuggestions(value); setState(() => _stopSuggestions = suggestions); } else { setState(() => _stopSuggestions = []); } },
                    onClear: () => _clearStop(index),
                    onMapIconTap: () { setState(() { _editingStopIndex = index; _selectingPickup = false; _editingPickup = false; _editingDestination = false; }); _collapseSheet(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tap on map to select location for Stop ${index + 1}'))); },
                  ),
                ),
              ),
              horizontalSpaceSmall,
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 24),
                color: theme.colorScheme.secondary,
                onPressed: () => _addStopAfter(index),
                tooltip: 'Add stop after this one',
              ),
            ],
          ),
          if (isEditing) // Suggestions list for the stop
            Padding(
              padding: const EdgeInsets.only(top: 0, left: 0, right: 40), // Adjust padding to align under text field
              child: Column(
                children: _buildSuggestionList(_stopSuggestions, false, index),
              ),
            ),
        ],
      ),
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

  Future<void> _showRateDriverDialog(String rideId, String driverId) async {
    double ratingValue = 0;
    final theme = Theme.of(context);
    TextEditingController commentController = TextEditingController();

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must explicitly submit or skip
      builder: (BuildContext dialogContext) {
        return StatefulBuilder( // To update stars in the dialog
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Rate Your Driver', style: theme.textTheme.titleLarge),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    Text('How was your ride?', style: theme.textTheme.bodyMedium),
                    verticalSpaceMedium,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return IconButton(
                          icon: Icon(
                            index < ratingValue ? Icons.star : Icons.star_border,
                            color: accentColor, // From ui_utils
                            size: 30,
                          ),
                          onPressed: () {
                            setDialogState(() => ratingValue = index + 1.0);
                          },
                        );
                      }),
                    ),
                    verticalSpaceSmall,
                    TextField(
                      controller: commentController,
                      decoration: appInputDecoration(hintText: "Add a comment (optional)"),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text('Skip', style: TextStyle(color: theme.hintColor)),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                ElevatedButton(
                  child: const Text('Submit Rating'),
                  onPressed: () async {
                    final rideProvider = Provider.of<RideRequestProvider>(context, listen: false);
                    final navigator = Navigator.of(dialogContext);
                    final scaffoldMessenger = ScaffoldMessenger.of(context);

                    if (ratingValue > 0) {
                      try {
                        await rideProvider.rateUser(
                          rideId: rideId,
                          ratedUserId: driverId,
                          ratedUserRole: 'Driver',
                          rating: ratingValue,
                          comment: commentController.text.trim().isNotEmpty ? commentController.text.trim() : null,
                        );
                        
                        if (!mounted) return;

                        // Pop the dialog before showing other UI
                        if (navigator.canPop()) {
                           navigator.pop();
                        }

                        scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Rating submitted! Thank you.')));
                        _showPostRideCompletionDialog();
                      } catch (e) {
                        if (!mounted) return;

                        if (navigator.canPop()) { 
                           navigator.pop();
                        }
                        scaffoldMessenger.showSnackBar(SnackBar(content: Text('Failed to submit rating: $e')));
                      }
                    } else {
                      scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Please select a star rating.')));
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
  
  void _showPostRideCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Ride Completed!'),
          content: const Text('Thank you for riding with us.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Return Trip'),
              onPressed: () async { // Make onPressed async
                Navigator.of(dialogContext).pop();
                _resetActiveRideStateOnly(); // Reset the ride state but keep locations
                if (_stops.isNotEmpty) {
                  // Show another dialog to ask about stops
                  bool? clearStops = await showDialog<bool>(
                    context: context, // Use the main screen's context
                    builder: (BuildContext stopsDialogContext) {
                      return AlertDialog(
                        title: const Text('Keep Stops?'),
                        content: const Text('Do you want to keep the current stops for your return trip?'),
                        actions: <Widget>[
                          TextButton(
                            child: const Text('Clear Stops'),
                            onPressed: () => Navigator.of(stopsDialogContext).pop(true),
                          ),
                          TextButton(
                            child: const Text('Keep Stops'),
                            onPressed: () => Navigator.of(stopsDialogContext).pop(false),
                          ),
                        ],
                      );
                    },
                  );
                  if (clearStops == true) {
                    setState(() {
                      _stops.clear();
                      _markers.removeWhere((m) => m.markerId.value.startsWith('stop_'));
                    });
                  }
                }
                _swapLocations(); // Swaps pickup and destination
                _drawRoute(); // Redraw route after potential changes
              },
            ),
            TextButton(
              child: const Text('View Ride History'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _resetUIForNewTrip(); // Reset the form before navigating
                Navigator.push(context, MaterialPageRoute(builder: (context) => const RidesScreen(role: 'Customer')));
              },
            ),
            TextButton(
              child: const Text('Thanks'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _resetUIForNewTrip(); // Reset the form
              },
            ),
          ],
        );
      },
    );
  }

  void _stopListeningToActiveRide() {
    _activeRideSubscription?.cancel();
    _activeRideSubscription = null;
  }

  // Resets only the active ride state, keeping locations for a return trip.
  void _resetActiveRideStateOnly() {
    setState(() {
      _activeRideRequestId = null;
      _activeRideRequestDetails = null;
      _assignedDriverModel = null;
      _isFindingDriver = false;
      _stopListeningToActiveRide();
      _stopListeningToDriverLocation();
      _polylines.clear();
      _markers.removeWhere((m) => m.markerId.value == 'driver_active_location');
      _routeReady = false;
      _estimatedFare = null;
    });
  }

@override
  void dispose() {
    _mapController?.dispose();
    _locationProvider.removeListener(_onLocationUpdated);
    _sheetController.dispose();
    _destinationFocusNode.dispose();
    _pickupFocusNode.dispose();
    _customerNoteController.dispose(); // Dispose the new controller
    _stopFocusNode.dispose();
    _driverLocationSubscription?.cancel();
    _kijiweSubscription?.cancel();
    _stopListeningToActiveRide(); // Ensure subscription is cancelled on dispose
    for (var stop in _stops) { // Dispose resources for each stop
      stop.dispose();
    }
    super.dispose();
  }
}
