import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/driver_provider.dart';
import '../services/auth_service.dart';
import '../providers/location_provider.dart'; // Reuse from customer home
import '../utils/map_utils.dart'; // Add this import for MapUtils
import 'package:cloud_firestore/cloud_firestore.dart'; // For fetching user data
import '../models/user_model.dart'; // To potentially parse user data

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  GoogleMapController? _mapController;
  // bool _isOnline = false; // Will use DriverProvider.isOnline directly
  bool _hasActiveRide = false;
  Map<String, dynamic>? _currentRide;
  double? _currentHeading;
  BitmapDescriptor? _bodaIcon; // Define _carIcon
  LatLng? _lastPosition; // Define _lastPosition
  bool _isIconLoaded = false; // New 
  
    // Route drawing state
  final Set<Polyline> _activeRoutePolylines = {};
  String? _routeDistanceToPickup;
  String? _routeDurationToPickup;
  bool _isLoadingRoute = false;
  String? _pendingRideCustomerName; // To store fetched customer name
  final String _googlePlacesApiKey = 'AIzaSyCkKD8FP-r9bqi5O-sOjtuksT-0Dr9dgeg'; // TODO: Move to a config file

    // Define the listener method
  void _locationProviderListener() {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    if (mounted && locationProvider.currentLocation != null) { // Check if mounted before calling setState
      _updateDriverLocationAndMap(locationProvider);
    }
  }


  @override
void initState() {
  super.initState();
  _loadCustomMarker().then((_) { // Ensure marker is loaded, then initialize state
    if (mounted) {
      setState(() {
        _isIconLoaded = true;
      });
    }
    _initializeDriverStateAndLocation();
  });
  // Add listener for LocationProvider
  Provider.of<LocationProvider>(context, listen: false).addListener(_locationProviderListener);
}

  Future<void> _loadCustomMarker() async {
    try {
      _bodaIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/boda_marker.png',
      );
    } catch (e) {
      debugPrint("Error loading custom marker: $e");
      // _bodaIcon will remain null, default marker will be used by _buildDriverMarker
    }
  }
  

  Future<void> _initializeDriverStateAndLocation() async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);

    // Load persisted driver data first
    await driverProvider.loadDriverData();

    await locationProvider.updateLocation();
    if (locationProvider.currentLocation != null && _mapController != null) {
      _centerMapOnDriver();
    }
  }

  @override
  Widget build(BuildContext context) {
    final driverProvider = Provider.of<DriverProvider>(context);
    final authService = Provider.of<AuthService>(context);
    final locationProvider = Provider.of<LocationProvider>(context);

    return Scaffold(
      body: Stack(
        children: [
          // Base Map (reusing similar logic from CustomerHome)
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: locationProvider.currentLocation is LatLng
                  ? locationProvider.currentLocation as LatLng
                  : const LatLng(0, 0),
              zoom: 17, // Closer zoom for driver view
              bearing: _currentHeading ?? 0,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _centerMapOnDriver();
            },
            myLocationEnabled: false, // We'll use custom marker
            markers: _isIconLoaded ? _buildDriverMarker(locationProvider) : {},
            onCameraMove: (position) {
              _currentHeading = position.bearing;
            },
            polylines: _activeRoutePolylines,
          ),

          // Online Status Toggle (floating button instead of app bar)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: driverProvider.isOnline ? Colors.green : Colors.grey,
              onPressed: _toggleOnlineStatus,
              child: Icon(
                Icons.offline_bolt,
                color: Colors.white,
              ),
            ),
          ),

          // Driver Info Card
          if (driverProvider.isOnline) // Use provider's state
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16, // Only right alignment needed now
              child: _buildOnlineStatusWidget(),
            ),

          // Bottom Sheet for Ride Control
          if (_hasActiveRide) _buildActiveRideSheet(),
          if (driverProvider.isOnline &&
              driverProvider.pendingRideRequestDetails != null &&
              !_hasActiveRide)
            FutureBuilder<void>(
              future: _initiateRouteToPickupForSheet(driverProvider.pendingRideRequestDetails!),
              builder: (context, snapshot) {
                // The FutureBuilder is mainly to trigger the async call.
                // The actual UI (_buildRideRequestSheet) is built immediately.
                // Loading state for the route can be handled by _isLoadingRoute.
                return _buildRideRequestSheet(driverProvider.pendingRideRequestDetails!);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildOnlineStatusWidget() {
  final driverProvider = Provider.of<DriverProvider>(context);
  
  return AnimatedSwitcher(
    duration: Duration(milliseconds: 300),
    transitionBuilder: (child, animation) {
      return ScaleTransition(scale: animation, child: child);
    },
    child: driverProvider.isOnline
        ? _buildOnlineCardWithToggle(driverProvider)
        : _buildOfflineButton(driverProvider),
  );
}

  Widget _buildOnlineCardWithToggle(DriverProvider driverProvider) {
  return SizedBox(
    width: 117, // Square width
    height: 118, // Square height
    child: Card(
    key: ValueKey('online-card'),
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // Slightly rounded corners
      ),
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween, // Better space distribution
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Online', 
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12, // Slightly smaller font
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _buildToggleButton(driverProvider),
                ],
              ),
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⭐ 4.9', 
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12, // Larger for emphasis
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('\$125.50 today', 
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    ),
    ),
  );
}

Widget _buildOfflineButton(DriverProvider driverProvider) {
  return FloatingActionButton(
    key: ValueKey('offline-button'),
    mini: true,
    backgroundColor: Colors.grey,
    onPressed: () => driverProvider.toggleOnlineStatus(),
    child: driverProvider.isLoading
        ? CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Colors.white),
            strokeWidth: 2,
          )
        : Icon(Icons.offline_bolt, color: Colors.white),
  );
}

Widget _buildToggleButton(DriverProvider driverProvider) {
  return IconButton(
    icon: driverProvider.isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Colors.red),
              strokeWidth: 2,
            ),
          )
        : Icon(Icons.power_settings_new, size: 20),
    color: Colors.red,
    onPressed: () => driverProvider.toggleOnlineStatus(),
  );
}

  Widget _buildActiveRideSheet() {
    final isAtPickup = _currentRide?['status'] == 'arrived';
    final isRideInProgress = _currentRide?['status'] == 'onRide'; // Matched with provider status
    final isGoingToPickup = _currentRide?['status'] == 'accepted' || _currentRide?['status'] == 'goingToPickup';

    final String customerName = _currentRide?['customerName'] as String? ?? 'Customer';
    final String pickupAddress = _currentRide?['pickupAddressName'] as String? ?? 'Pickup Location';
    final String dropoffAddress = _currentRide?['dropoffAddressName'] as String? ?? 'Destination';
    final bool pickupStepCompleted = isAtPickup || isRideInProgress;

    return DraggableScrollableSheet(
      initialChildSize: 0.3,
      minChildSize: 0.25,
      maxChildSize: 0.4,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(  // Add this
          controller: scrollController,  // Connect to the sheet's controller
          child: Column(
            mainAxisSize: MainAxisSize.min,  // Important for scrollable Column
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Ride info
              ListTile(
                leading: CircleAvatar(child: Icon(Icons.person)),
                title: Text(customerName),
                subtitle: Text('Status: ${_currentRide?['status'] ?? 'Unknown'}'),
              ),

              // Display route to pickup information if available
              if (_routeDistanceToPickup != null && _routeDurationToPickup != null && _currentRide?['status'] == 'accepted')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text('To Pickup: $_routeDurationToPickup · $_routeDistanceToPickup', style: TextStyle(color: Colors.blueAccent)),
                ),
              if (_isLoadingRoute && _currentRide?['status'] == 'accepted')
                Padding(padding: const EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator())),

              Divider(),

              // Ride progress
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildRideStep(Icons.pin_drop, 'Pickup: $pickupAddress', pickupStepCompleted),
                    _buildRideStep(Icons.flag, 'Destination: $dropoffAddress', false), // Destination is "completed" when sheet is gone
                  ],
                ),
              ),

              // Action buttons
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (isGoingToPickup) ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.navigation),
                          label: Text('Navigate'),
                          onPressed: () => _navigateToPickup(),
                        ),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          child: Text('Arrived'),
                          onPressed: () => _confirmArrival(context), // Pass context
                        ),
                      ),
                    ] else if (isAtPickup) ...[
                      // At pickup state
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          child: Text('Start Ride'),
                          onPressed: () => _startRide(context), // Pass context
                        ),
                      ),
                    ] else if (isRideInProgress) ...[
                      // In progress state
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                          child: const Text('Complete Ride'),
                          onPressed: () {
                            final rideId = _currentRide?['rideId'] as String?;
                            if (rideId != null) {
                              _completeRide(context, rideId); // Pass context
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Ride ID is missing.')));
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            // Cancel Ride Button - visible if ride is active but not yet completed
            if (_hasActiveRide && !isRideInProgress) // Show if going to pickup or arrived, but not yet 'onRide' or 'completed'
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red),
                    foregroundColor: Colors.red,
                  ),
                  onPressed: _showCancelRideConfirmationDialog, // This is where it's called
                  child: Text('Cancel Ride'),
                ),
              ),
             ),
            ],
          ),
        ),
        // Removed the closing parenthesis for the SingleChildScrollView here
        );
      },
    );
  }

  Widget _buildRideStep(IconData icon, String text, bool isCompleted) {
    return Row(
      children: [
        Icon(icon, color: isCompleted ? Colors.green : Colors.grey),
        SizedBox(width: 12),
        Expanded(child: Text(text)),
        if (isCompleted) Icon(Icons.check_circle, color: Colors.green, size: 16),
      ],
    );
  }

  Widget _buildRideRequestSheet(Map<String, dynamic> rideData) {
    final String rideRequestId = rideData['rideRequestId'] as String? ?? 'N/A';
    final String customerId = rideData['customerId'] as String? ?? 'N/A';
    final dynamic pickupLatRaw = rideData['pickupLat']; // Extract before acceptRide clears it from provider
    final dynamic pickupLngRaw = rideData['pickupLng']; // Extract before acceptRide clears it from provider

     return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(child: Icon(Icons.person)),
                title: Text(_pendingRideCustomerName != null && _pendingRideCustomerName!.isNotEmpty
                    ? 'Ride from $_pendingRideCustomerName'
                    : 'New Ride Request!'),
                subtitle: Text(_pendingRideCustomerName != null && _pendingRideCustomerName!.isNotEmpty
                    ? 'Customer ID: $customerId'
                    : 'Fetching customer details...'),

              ),

              // Display route to pickup information if available
              if (_routeDistanceToPickup != null && _routeDurationToPickup != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('To Pickup: $_routeDurationToPickup · $_routeDistanceToPickup', style: TextStyle(color: Colors.blueAccent)),
                ),
              if (_isLoadingRoute && _activeRoutePolylines.isEmpty) // Show loading if route is being fetched for the sheet
                Padding(padding: const EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator())),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      child: const Text('Decline'),
                      onPressed: () => _declineRide(rideRequestId, customerId),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      child: const Text('Accept'),
                      onPressed: () => _acceptRide(rideRequestId, customerId, pickupLatRaw, pickupLngRaw, _pendingRideCustomerName),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  // Helper method to get current ride details safely
  Map<String, String?> _getCurrentRideDetails() {
    final rideId = _currentRide?['rideId'] as String?;
    final customerId = _currentRide?['customerId'] as String?;
    return {'rideId': rideId, 'customerId': customerId};
  }

  Set<Marker> _buildDriverMarker(LocationProvider locationProvider) {
    if (locationProvider.currentLocation == null) return {};

    return {
      Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(
          locationProvider.currentLocation!.latitude,
          locationProvider.currentLocation!.longitude,
        ),
        icon: _bodaIcon ?? BitmapDescriptor.defaultMarker,
        rotation: _currentHeading ?? 0,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        zIndex: 1000,
      ),
    };
  }
  void _centerMapOnDriver() {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    if (locationProvider.currentLocation == null || _mapController == null) return;

    _mapController?.animateCamera(
      CameraUpdate.newLatLng(
        LatLng(
          locationProvider.currentLocation!.latitude,
          locationProvider.currentLocation!.longitude,
        ),
      ),
    );
  }

  void _toggleOnlineStatus() async {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);

    // Store the current online status before toggling to determine success message
    final bool wasOnline = driverProvider.isOnline;
    final String? errorMessage = await driverProvider.toggleOnlineStatus();

    if (!mounted) return; // Check if widget is still in the tree

    if (errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } else {
      // Success, UI already updated by provider's notifyListeners
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(wasOnline ? 'You are now offline.' : 'You are now online.')),
      );
    }
  }

 // This method will be called by the listener
  void _updateDriverLocationAndMap(LocationProvider locationProvider) {
    if (!mounted) return; // Ensure widget is still mounted

    try {
      setState(() {
        _lastPosition = LatLng(
          locationProvider.currentLocation!.latitude,
          locationProvider.currentLocation!.longitude,
        );
        _currentHeading = locationProvider.heading;
      });

      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      if (driverProvider.isOnline && _mapController != null && _lastPosition != null) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(_lastPosition!),
        );
      }

      if (driverProvider.isOnline && _lastPosition != null) {
        driverProvider.updateDriverPosition(_lastPosition!).catchError((e) {
          // Catch errors from async operation updateDriverPosition
          debugPrint('Error in driverProvider.updateDriverPosition: $e');
        });
      }
    } catch (e) {
      // This catch block is for synchronous errors within this method
      debugPrint('Error in _updateDriverLocationAndMap: $e');
        }
  }

  // Method to trigger fetching route details when the ride request sheet is shown
  Future<void> _initiateRouteToPickupForSheet(Map<String, dynamic> rideData) async {
    final dynamic latDynamic = rideData['pickupLat'];
    final dynamic lngDynamic = rideData['pickupLng'];

    if (latDynamic != null && lngDynamic != null) {
      final double? lat = double.tryParse(latDynamic.toString());
      final double? lng = double.tryParse(lngDynamic.toString());

      if (lat != null && lng != null) {
        final pickupLocation = LatLng(lat, lng);
        // Ensure driver's location is available

        // Fetch customer name
        final customerId = rideData['customerId'] as String?;
        if (customerId != null) {
          try {
            DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(customerId).get();
            if (mounted && userDoc.exists) {
              final userData = userDoc.data() as Map<String, dynamic>?;
              setState(() {
                _pendingRideCustomerName = userData?['name'] as String? ?? 'Customer';
              });
            }
          } catch (e) {
            debugPrint("Error fetching customer name: $e");
            if (mounted) setState(() => _pendingRideCustomerName = null);
          }
        }

        final locationProvider = Provider.of<LocationProvider>(context, listen: false);
        if (locationProvider.currentLocation != null) {
          await _fetchAndDisplayRouteToPickup(pickupLocation);
        } else {
          // Wait for location update if not available
          await locationProvider.updateLocation();
          if (mounted && locationProvider.currentLocation != null) {
            await _fetchAndDisplayRouteToPickup(pickupLocation);
          }
        }
      }
    }
  }

  Future<void> _fetchAndDisplayRouteToPickup(LatLng pickupLocation) async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    if (locationProvider.currentLocation == null) {
      debugPrint("Driver location not available to draw route.");
      return;
    }

    final driverLatLng = LatLng(
      locationProvider.currentLocation!.latitude,
      locationProvider.currentLocation!.longitude,
    );

    if (!mounted) return;
    setState(() {
      _isLoadingRoute = true;
      _activeRoutePolylines.clear(); // Clear previous route
      _routeDistanceToPickup = null;
      _routeDurationToPickup = null;
    });

    try {
      // MapUtils.getRouteDetails now returns a List<Map<String, dynamic>>?
      final List<Map<String, dynamic>>? routeDetailsList = await MapUtils.getRouteDetails(
        origin: driverLatLng,
        destination: pickupLocation,
        apiKey: _googlePlacesApiKey,
      );

      if (!mounted) return;
      // Check if the list is not null and not empty
      if (routeDetailsList != null && routeDetailsList.isNotEmpty) {
        // For the driver's route to pickup, we'll use the first route as the primary.
        final Map<String, dynamic> primaryRouteDetails = routeDetailsList.first;

        setState(() {
          // The 'polyline' key in primaryRouteDetails holds a single Polyline object
          _activeRoutePolylines.add(primaryRouteDetails['polyline'] as Polyline);
          _routeDistanceToPickup = primaryRouteDetails['distance'] as String?;
          _routeDurationToPickup = primaryRouteDetails['duration'] as String?;
          _isLoadingRoute = false;
        });

        final LatLngBounds? bounds = MapUtils.boundsFromLatLngList(primaryRouteDetails['points'] as List<LatLng>);
        if (bounds != null && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 80), // Adjust padding as needed
          );
        }
      } else {
        // Error already printed by MapUtils.getRouteDetails
        setState(() => _isLoadingRoute = false);
      }
    } catch (e) {
      debugPrint('Error in _fetchAndDisplayRouteToPickup: $e');
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  void _acceptRide(String rideId, String customerId, dynamic pickupLatRaw, dynamic pickupLngRaw, String? customerName) async {
  final driverProvider = Provider.of<DriverProvider>(context, listen: false);
  try {
    // Extract necessary details from pendingRideRequestDetails BEFORE it's cleared by acceptRideRequest
    final pendingDetails = driverProvider.pendingRideRequestDetails;
    final String? pickupAddressName = pendingDetails?['pickupAddressName'] as String?;
    final String? dropoffAddressName = pendingDetails?['dropoffAddressName'] as String?;
    final dynamic dropoffLatRaw = pendingDetails?['dropoffLat'];
    final dynamic dropoffLngRaw = pendingDetails?['dropoffLng'];

    // Call acceptRideRequest first. This will clear pendingRideRequestDetails in the provider.
    // Pass context to driverProvider.acceptRideRequest
    await driverProvider.acceptRideRequest(context, rideId, customerId);
    
    // Now, use the pickupLatRaw and pickupLngRaw that were passed in.
    setState(() {
      _hasActiveRide = true;
      _currentRide = {
        'rideId': rideId,
        'customerId': customerId, // Store customerId
        'status': 'accepted', // This status should ideally be driven by provider/backend
        'customerName': customerName ?? 'Customer', // Store fetched customer name
        'pickupLat': pickupLatRaw, // Use the passed-in value
        'pickupLng': pickupLngRaw, // Use the passed-in value
        'pickupAddressName': pickupAddressName ?? 'Pickup Location',
        'dropoffLat': dropoffLatRaw,
        'dropoffLng': dropoffLngRaw,
        'dropoffAddressName': dropoffAddressName ?? 'Destination',
        // Add other relevant details like dropoffLat, dropoffLng if needed for _navigateToPickup
      };
    });
    // If pickup location is available, draw/redraw route to pickup
    // Use the passed-in raw values directly for the check and parsing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ride accepted successfully')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to accept ride: ${e.toString()}')),
    );
  }
    // If pickup location is available, draw/redraw route to pickup
    // Use the passed-in raw values directly for the check and parsing
    if (pickupLatRaw != null && pickupLngRaw != null && double.tryParse(pickupLatRaw.toString()) != null && double.tryParse(pickupLngRaw.toString()) != null) {
      _fetchAndDisplayRouteToPickup(LatLng(double.parse(pickupLatRaw.toString()), double.parse(pickupLngRaw.toString())));
    }
}

void _declineRide(String rideId, String customerId) async {
  final driverProvider = Provider.of<DriverProvider>(context, listen: false);
  try {
    // Pass context to driverProvider.declineRideRequest
    await driverProvider.declineRideRequest(context, rideId, customerId);
    // Clear the route polylines and reset state
    setState(() {
      _activeRoutePolylines.clear();
      _routeDistanceToPickup = null;
      _routeDurationToPickup = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ride declined')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to decline ride: ${e.toString()}')),
    );
  }
}

  void _navigateToPickup() async {
  if (_currentRide == null) return;
  // Get pickup coordinates from _currentRide (which should have been populated from pendingRideRequestDetails)
  final dynamic pickupLatDynamic = _currentRide!['pickupLat'];
  final dynamic pickupLngDynamic = _currentRide!['pickupLng'];

  if (pickupLatDynamic == null || pickupLngDynamic == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pickup location not available.')));
    return;
  }
  final pickupLat = double.tryParse(pickupLatDynamic.toString());
  final pickupLng = double.tryParse(pickupLngDynamic.toString());
  if (pickupLat == null || pickupLng == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid pickup location format.')));
    return;
  }
  final pickupLocation = LatLng(pickupLat as double, pickupLng as double);

  // Open in external maps app
  final uri = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=${pickupLocation.latitude},${pickupLocation.longitude}&travelmode=driving',
  );
  
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not launch navigation')),
    );
  }
}

void _confirmArrival(BuildContext context) async {
  final details = _getCurrentRideDetails();
  final rideId = details['rideId'];
  final customerId = details['customerId'];

  if (rideId == null || customerId == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Ride details missing for arrival confirmation.')));
    return;
  }

  final driverProvider = Provider.of<DriverProvider>(context, listen: false);
  try {
    // Pass context to driverProvider.confirmArrival
    await driverProvider.confirmArrival(context, rideId, customerId);
    setState(() {
      _currentRide?['status'] = 'arrived';
    });
        // Clear route to pickup, as driver has arrived
    setState(() {
      _activeRoutePolylines.clear();
      _routeDistanceToPickup = null;
      _routeDurationToPickup = null;
    });
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to confirm arrival: ${e.toString()}')),
    );
  }
}

  void _startRide(BuildContext context) async {
    final details = _getCurrentRideDetails();
    final rideId = details['rideId'];
    final customerId = details['customerId'];

    if (rideId == null || customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Ride details missing for starting ride.')));
      return;
    }
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    try {
      // Pass context to driverProvider.startRide
      await driverProvider.startRide(context, rideId, customerId);
      setState(() {
        _currentRide?['status'] = 'onRide'; // Correct status to show "Complete Ride" button
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start ride: ${e.toString()}')),
      );
    }
  }

  void _completeRide(BuildContext context, String rideId) async {
  // rideId is passed from the button, ensure customerId is available from _currentRide
  final customerId = _currentRide?['customerId'] as String?;

  if (customerId == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Customer ID not found for this ride.')));
    return;
  }

  final driverProvider = Provider.of<DriverProvider>(context, listen: false);

  try {
    // Pass context to driverProvider.completeRide
    await driverProvider.completeRide(context, rideId, customerId);
    setState(() {
      _hasActiveRide = false;
      _currentRide = null;
      // Clear any active route polylines
      _activeRoutePolylines.clear();
      _routeDistanceToPickup = null;
      _routeDurationToPickup = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ride completed successfully')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to complete ride: ${e.toString()}')),
    );
  }
  // After successfully completing the ride, show rating dialog
  if (mounted) {
    _showRateCustomerDialog(rideId, customerId);
  }
}

Future<void> _showRateCustomerDialog(String rideId, String customerId) async {
  double _rating = 0; // Default rating
  // Potentially fetch customer name if needed for the dialog title
  // For simplicity, we'll use customerId for now.

  return showDialog<void>(
    context: context,
    barrierDismissible: false, // User must tap button!
    builder: (BuildContext context) {
      return StatefulBuilder( // Use StatefulBuilder to update rating within the dialog
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Rate Customer'), // Consider: 'Rate Customer $customerName'
            content: SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text('How was your experience with the customer?'),
                  SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < _rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                        ),
                        onPressed: () {
                          setDialogState(() {
                            _rating = index + 1.0;
                          });
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: Text('Submit Rating'),
                onPressed: () {
                  if (_rating > 0) {
                    // TODO: Implement logic to submit rating to Firestore
                    // e.g., Provider.of<DriverProvider>(context, listen: false).rateCustomer(customerId, _rating, rideId);
                    debugPrint('Rating submitted: $_rating for customer $customerId, ride $rideId');
                    Navigator.of(context).pop();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Please select a rating.')),
                    );
                  }
                },
              ),
              TextButton(
                child: Text('Skip'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    },
  );
}

  Future<void> _showCancelRideConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // User must tap button!
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Ride'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Are you sure you want to cancel this ride?'),
                // TODO: Optionally add a field for cancellation reason
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('No'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Yes, Cancel'),
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close the dialog
                _cancelRide(); // Call the local _cancelRide method
              },
            ),
          ],
        );
      },
    );
  }

  void _cancelRide() async {
    final details = _getCurrentRideDetails();
    final rideId = details['rideId'];
    final customerId = details['customerId'];

    if (rideId == null || customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Ride details missing for cancellation.')));
      return;
    }
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    try {
      // Pass context if DriverProvider.cancelRide needs it for RideRequestProvider
      await driverProvider.cancelRide(context, rideId, customerId); 
      setState(() {
        _hasActiveRide = false;
        _currentRide = null;
        // Clear any active route polylines
        _activeRoutePolylines.clear();
        _routeDistanceToPickup = null;
        _routeDurationToPickup = null;
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel ride: ${e.toString()}')),
      );
    }
  }
  @override
  void dispose() {
    _mapController?.dispose();
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    // Remove the specific listener instance
    locationProvider.removeListener(_locationProviderListener);
    super.dispose();
  }
}