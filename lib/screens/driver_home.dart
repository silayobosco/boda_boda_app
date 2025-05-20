import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/driver_provider.dart';
import '../services/auth_service.dart';
import '../providers/location_provider.dart'; // Reuse from customer home
import '../utils/map_utils.dart'; // Add this import for MapUtils
import 'package:cloud_firestore/cloud_firestore.dart'; // For fetching user data
import '../utils/ui_utils.dart'; // Import UI Utils for styles and spacing
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
  final Set<Marker> _rideSpecificMarkers = {}; // Markers for current ride (proposed or active)
  String? _currentRouteDistance; // Generic distance for the currently displayed route
  String? _currentRouteDuration; // Generic duration for the currently displayed route
  bool _isLoadingRoute = false;
  String _currentRouteType = ''; // To describe the route (e.g., "Full Ride", "To Pickup", "Main Ride")
  String? _pendingRideCustomerName; // To store fetched customer name
  String? _currentlyDisplayedProposedRideId; // To track the ID of the ride for which a proposed route is shown
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
    final theme = Theme.of(context); // Get the current theme

    return Scaffold(
      body: Stack(
        children: [
          // Base Map (reusing similar logic from CustomerHome)
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: locationProvider.currentLocation is LatLng
                  ? locationProvider.currentLocation as LatLng // Cast to LatLng
                  : const LatLng(0, 0),
              zoom: 17, // Closer zoom for driver view
              bearing: _currentHeading ?? 0,
            ),
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
              _centerMapOnDriver();
            },
            myLocationEnabled: false, // We'll use custom marker
            markers: _isIconLoaded ? _buildDriverMarker(locationProvider) : {},
            onCameraMove: (position) {
              _currentHeading = position.bearing;
            }, // Removed comma here
            polylines: _activeRoutePolylines,
          ),

          // Online Status Toggle (floating button instead of app bar)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: FloatingActionButton(
              mini: true,
              backgroundColor: driverProvider.isOnline ? successColor : theme.colorScheme.onSurface.withOpacity(0.6),
              onPressed: _toggleOnlineStatus,
              child: Icon(
                Icons.offline_bolt,
                color: theme.colorScheme.surface, // Color for icon on FAB
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
              future: _initiateFullProposedRideRouteForSheet(driverProvider.pendingRideRequestDetails!),
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
  final theme = Theme.of(context); // Define theme here
  return SizedBox(
    width: 117, // Square width
    height: 124, // Square height
    child: Card(
    key: ValueKey('online-card'),
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), // Slightly rounded corners
    ),
    color: theme.colorScheme.surfaceVariant, // Use theme color
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Online', 
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: successColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _buildToggleButton(driverProvider),
                ],
              ),
              Padding( // Add padding to ensure it doesn't overlap with the button
                padding: const EdgeInsets.only(bottom: 4.0), // Adjust as needed
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⭐ 4.9', 
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text('\$125.50 today', 
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
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
    backgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
    onPressed: () => driverProvider.toggleOnlineStatus(),
    child: driverProvider.isLoading
        ? CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.surface),
            strokeWidth: 2,
          )
        : Icon(Icons.offline_bolt, color: Theme.of(context).colorScheme.surface),
  );
}

Widget _buildToggleButton(DriverProvider driverProvider) {
  return IconButton(
    icon: driverProvider.isLoading
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.error),
              strokeWidth: 2,
            ),
          )
        : Icon(Icons.power_settings_new, size: 20),
    color: Theme.of(context).colorScheme.error,
    onPressed: () => driverProvider.toggleOnlineStatus(),
  );
}

  Widget _buildActiveRideSheet() {
    final isAtPickup = _currentRide?['status'] == 'arrived';
    final isRideInProgress = _currentRide?['status'] == 'onRide'; // Matched with provider status
    final theme = Theme.of(context);
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
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                blurRadius: 10,
                color: Colors.black.withOpacity(0.1),
                offset: const Offset(0, -2),
              )
            ]
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
                decoration: BoxDecoration(color: theme.colorScheme.outline.withOpacity(0.5), borderRadius: BorderRadius.circular(2)),
              ),

              // Ride info
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer),
                ),
                title: Text(customerName, style: theme.textTheme.titleMedium),
                subtitle: Text('Status: ${_currentRide?['status'] ?? 'Unknown'}', style: theme.textTheme.bodySmall),
              ),

              // Display route to pickup information if available
              if (_currentRouteDistance != null && _currentRouteDuration != null && (_currentRide?['status'] == 'accepted' || _currentRide?['status'] == 'arrived' || _currentRide?['status'] == 'onRide'))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text('$_currentRouteType: $_currentRouteDuration · $_currentRouteDistance', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
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
                          style: theme.elevatedButtonTheme.style?.copyWith(
                            backgroundColor: MaterialStateProperty.all(successColor),
                            foregroundColor: MaterialStateProperty.all(theme.colorScheme.onPrimary),
                          ),
                          child: Text('Arrived'),
                          onPressed: () => _confirmArrival(context), // Pass context
                        ),
                      ),
                    ] else if (isAtPickup) ...[
                      // At pickup state
                      Expanded(
                        child: ElevatedButton(
                          style: theme.elevatedButtonTheme.style?.copyWith(
                            backgroundColor: MaterialStateProperty.all(successColor),
                            foregroundColor: MaterialStateProperty.all(theme.colorScheme.onPrimary),
                          ),
                          child: Text('Start Ride'),
                          onPressed: () => _startRide(context), // Pass context
                        ),
                      ),
                    ] else if (isRideInProgress) ...[
                      // In progress state
                      Expanded(
                        child: ElevatedButton(
                          style: theme.elevatedButtonTheme.style?.copyWith(
                            backgroundColor: MaterialStateProperty.all(successColor),
                            foregroundColor: MaterialStateProperty.all(theme.colorScheme.onPrimary),
                          ),
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
                    side: BorderSide(color: theme.colorScheme.error),
                    foregroundColor: theme.colorScheme.error,
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
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: isCompleted ? successColor : theme.hintColor),
        SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        if (isCompleted) Icon(Icons.check_circle, color: successColor, size: 16),
      ],
    );
  }

  Widget _buildRideRequestSheet(Map<String, dynamic> rideData) {
    final theme = Theme.of(context);
    final String rideRequestId = rideData['rideRequestId'] as String? ?? 'N/A';
    final String customerId = rideData['customerId'] as String? ?? 'N/A';
    final dynamic pickupLatRaw = rideData['pickupLat']; // Extract before acceptRide clears it from provider
    final dynamic pickupLngRaw = rideData['pickupLng']; // Extract before acceptRide clears it from provider

     return Positioned(
      bottom: 0, // Align to bottom
      left: 0,
      right: 0,
      child: Card(
        elevation: 8,
        margin: EdgeInsets.zero, // Remove default card margin
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)), // Rounded top corners
        ),
        color: theme.colorScheme.surface,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer),
                ),
                title: Text(
                  _pendingRideCustomerName != null && _pendingRideCustomerName!.isNotEmpty
                    ? 'Ride from $_pendingRideCustomerName'
                    : 'New Ride Request!'),
                subtitle: Text(_pendingRideCustomerName != null && _pendingRideCustomerName!.isNotEmpty
                    ? 'Customer ID: $customerId'
                    : 'Fetching customer details...'),

              ),

              // Display route to pickup information if available
              if (_currentRouteDistance != null && _currentRouteDuration != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0), // Use verticalSpaceSmall
                  child: Text('Proposed Route: $_currentRouteDuration · $_currentRouteDistance', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondaryContainer)),
                ),
              if (_isLoadingRoute && _activeRoutePolylines.isEmpty) // Show loading if route is being fetched for the sheet
                Padding(padding: const EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator())),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      child: Text('Decline', style: TextStyle(color: theme.colorScheme.error)),
                      onPressed: () => _declineRide(rideRequestId, customerId),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      child: Text('Accept', style: TextStyle(color: theme.colorScheme.onPrimary)),
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
    final customerId = _currentRide?['customerId'] as String?; // Ensure this key exists in _currentRide
    return {'rideId': rideId, 'customerId': customerId};
  }

  Set<Marker> _buildDriverMarker(LocationProvider locationProvider) {
    if (locationProvider.currentLocation == null) return {};

    return {
      Marker(
        markerId: MarkerId('driver'), // Use const if it's always the same
        position: LatLng(
          locationProvider.currentLocation!.latitude,
          locationProvider.currentLocation!.longitude,
        ),
        icon: _bodaIcon ?? BitmapDescriptor.defaultMarker,
        rotation: _currentHeading ?? 0.0, // Ensure it's a double
        anchor: const Offset(0.5, 0.5),
        flat: true,
        zIndex: 1000,
      ),
      ..._rideSpecificMarkers, // Add markers for the current ride context
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

    // Fetches and displays the FULL PROPOSED RIDE route (pickup to destination with stops) for the ride request sheet
  Future<void> _initiateFullProposedRideRouteForSheet(Map<String, dynamic> rideData) async {
    final String? newRideRequestId = rideData['rideRequestId'] as String?;

    if (newRideRequestId == null) {
      debugPrint("DriverHome: Proposed ride has no ID. Cannot fetch/display route.");
      return;
    }

    // If already loading a route, or if the current proposed ride is already displayed for the *same* ride ID, do nothing.
    if (_isLoadingRoute) {
      // debugPrint("DriverHome: Route is currently being loaded. Skipping fetch for $newRideRequestId.");
      return;
    }
    // Check if the same proposed ride's route and markers are already displayed
    if (newRideRequestId == _currentlyDisplayedProposedRideId && _activeRoutePolylines.isNotEmpty && _rideSpecificMarkers.any((m) => m.markerId.value.startsWith('proposed_'))) {
      // debugPrint("DriverHome: Proposed route already displayed for $newRideRequestId. Skipping fetch.");
      return;
    }


    final dynamic pickupLatDynamic = rideData['pickupLat'];
    final dynamic pickupLngDynamic = rideData['pickupLng'];
    final dynamic dropoffLatDynamic = rideData['dropoffLat'];
    final dynamic dropoffLngDynamic = rideData['dropoffLng'];
    // TODO: Parse stops from rideData if they are part of the FCM payload and your model supports it
    // final List<dynamic>? stopsRaw = rideData['stops'] as List<dynamic>?;
    // final List<LatLng> rideWaypoints = stopsRaw?.map((stop) {
    //   final lat = double.tryParse(stop['lat'].toString());
    //   final lng = double.tryParse(stop['lng'].toString());
    //   return (lat != null && lng != null) ? LatLng(lat, lng) : null;
    // }).whereType<LatLng>().toList() ?? [];

    if (pickupLatDynamic == null || pickupLngDynamic == null || dropoffLatDynamic == null || dropoffLngDynamic == null) {
      debugPrint("DriverHome: Insufficient coordinates in rideData to draw full proposed route.");
      return;
    }

    final double? pLat = double.tryParse(pickupLatDynamic.toString());
    final double? pLng = double.tryParse(pickupLngDynamic.toString());
    final double? dLat = double.tryParse(dropoffLatDynamic.toString());
    final double? dLng = double.tryParse(dropoffLngDynamic.toString());

    if (pLat == null || pLng == null || dLat == null || dLng == null) {
      debugPrint("DriverHome: Could not parse coordinates for full proposed route.");
      return;
    }

    final LatLng ridePickupLocation = LatLng(pLat, pLng);
    final LatLng rideDropoffLocation = LatLng(dLat, dLng);

    // Fetch customer name (already part of your existing logic)
    final customerId = rideData['customerId'] as String?;
    if (customerId != null) {
      // ... (customer name fetching logic remains the same as in your current _initiateRouteToPickupForSheet)
      // Ensure customer name is fetched if not already available or if ride ID changed
      if (_pendingRideCustomerName == null || newRideRequestId != _currentlyDisplayedProposedRideId) {
        try {
          DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(customerId).get();
          if (mounted && userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>?; // Explicit cast
            setState(() {
              _pendingRideCustomerName = userData?['name'] as String? ?? 'Customer';
            });
          }
        } catch (e) { debugPrint("Error fetching customer name for sheet: $e"); }
      }
    }


    await _fetchAndDisplayRoute(
        origin: ridePickupLocation,
        destination: rideDropoffLocation,
        // waypoints: rideWaypoints, // Pass parsed stops here
        polylineColor: Colors.deepPurpleAccent, 
        routeType: "Proposed Ride");

    // Add markers for the proposed route
    if (mounted) {
      setState(() {
        _rideSpecificMarkers.clear();
        _rideSpecificMarkers.add(Marker(
          markerId: MarkerId('proposed_pickup'),
          position: ridePickupLocation,
          infoWindow: InfoWindow(title: 'Pickup: ${rideData['pickupAddressName'] ?? 'Customer Pickup'}'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ));
        _rideSpecificMarkers.add(Marker(
          markerId: MarkerId('proposed_dropoff'),
          position: rideDropoffLocation,
          infoWindow: InfoWindow(title: 'Destination: ${rideData['dropoffAddressName'] ?? 'Customer Destination'}'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ));
        // TODO: Add markers for stops if rideWaypoints were parsed
        // rideWaypoints.asMap().forEach((index, stopLatLng) {
        //   _rideSpecificMarkers.add(Marker(
        //     markerId: MarkerId('proposed_stop_$index'),
        //     position: stopLatLng,
        //     infoWindow: InfoWindow(title: 'Stop ${index + 1}'),
        //     icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        //   ));
        // });
      });
    }
    // Update the ID of the currently displayed proposed route
    if (mounted && _activeRoutePolylines.isNotEmpty && !_isLoadingRoute) {
      // Set this regardless of whether markers were added, as long as polyline is there
      _currentlyDisplayedProposedRideId = newRideRequestId;
    }
  }

    // Fetches and displays route from DRIVER'S CURRENT LOCATION to CUSTOMER'S PICKUP
  Future<void> _fetchAndDisplayRouteToPickup(LatLng customerPickupLocation) async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    if (locationProvider.currentLocation == null) {
      debugPrint("Driver location not available to draw route to pickup.");
      await locationProvider.updateLocation(); // Try to get location
      if (locationProvider.currentLocation == null) return; // Still not available
    }

    final driverCurrentLocation = LatLng(
      locationProvider.currentLocation!.latitude,
      locationProvider.currentLocation!.longitude,
    );

    await _fetchAndDisplayRoute(
        origin: driverCurrentLocation,
        destination: customerPickupLocation,
        polylineColor: Colors.blueAccent, // Color for route to pickup
        routeType: "To Pickup");

    // Add marker for customer's pickup when navigating to them
    if (mounted) {
      setState(() {
        _rideSpecificMarkers.clear(); // Clear previous proposed markers
        _rideSpecificMarkers.add(Marker(
          markerId: MarkerId('customer_pickup_active'),
          position: customerPickupLocation,
          infoWindow: InfoWindow(title: 'Customer Pickup'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ));
      });
    }
  }

  // Fetches and displays route from CUSTOMER'S PICKUP to CUSTOMER'S DESTINATION (Main Ride)
  Future<void> _fetchAndDisplayMainRideRoute(LatLng ridePickup, LatLng rideDropoff, List<LatLng>? stops) async {
    if (!mounted) return;

    await _fetchAndDisplayRoute(
      origin: ridePickup,
      destination: rideDropoff,
      waypoints: stops,
      polylineColor: Colors.greenAccent, // Color for the main ride
      routeType: "Main Ride",
    );

    // Add markers for main ride (pickup, destination, stops)
    if (mounted) {
      setState(() {
        _rideSpecificMarkers.clear();
        _rideSpecificMarkers.add(Marker(
          markerId: MarkerId('main_ride_pickup'),
          position: ridePickup,
          infoWindow: InfoWindow(title: 'Ride Pickup'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ));
        _rideSpecificMarkers.add(Marker(
          markerId: MarkerId('main_ride_destination'),
          position: rideDropoff,
          infoWindow: InfoWindow(title: 'Ride Destination'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ));
        stops?.asMap().forEach((index, stopLatLng) {
          _rideSpecificMarkers.add(Marker(
            markerId: MarkerId('main_ride_stop_$index'),
            position: stopLatLng,
            infoWindow: InfoWindow(title: 'Stop ${index + 1}'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          ));
        });
      });
    }
  }

  // Generic method to fetch and display a route
  Future<void> _fetchAndDisplayRoute({
    required LatLng origin,
    required LatLng destination,
    List<LatLng>? waypoints,
    required Color polylineColor,
    required String routeType,
  }) async {
    if (origin.latitude == destination.latitude && origin.longitude == destination.longitude && (waypoints == null || waypoints.isEmpty)) {
      debugPrint("DriverHome: Origin and Destination are the same, and no waypoints. Skipping route draw for $routeType.");
      if (mounted) setState(() => _isLoadingRoute = false);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingRoute = true;
      _activeRoutePolylines.clear(); // Clear previous route polylines
      // _rideSpecificMarkers are managed by the calling functions like _initiateFullProposedRideRouteForSheet, _fetchAndDisplayRouteToPickup, etc.
      _currentRouteDistance = null;
      _currentRouteDuration = null;
    });

    try {
      final List<Map<String, dynamic>>? routeDetailsList = await MapUtils.getRouteDetails(
        origin: origin,
        destination: destination,
        waypoints: waypoints,
        apiKey: _googlePlacesApiKey,
      );

      if (!mounted) return;
      if (routeDetailsList != null && routeDetailsList.isNotEmpty) {
        final Map<String, dynamic> primaryRouteDetails = routeDetailsList.first;
        setState(() {
          final Polyline originalPolyline = primaryRouteDetails['polyline'] as Polyline;
          _activeRoutePolylines.add(originalPolyline.copyWith(
            colorParam: polylineColor,
            widthParam: 6,
          ));
          _currentRouteDistance = primaryRouteDetails['distance'] as String?;
          _currentRouteDuration = primaryRouteDetails['duration'] as String?;
          _isLoadingRoute = false;
          _currentRouteType = routeType;
        });

        final LatLngBounds? bounds = MapUtils.boundsFromLatLngList(primaryRouteDetails['points'] as List<LatLng>);
        if (bounds != null && _mapController != null) {
          _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
        }
      } else {
        setState(() => _isLoadingRoute = false);
      }
    } catch (e) {
      debugPrint('Error in _fetchAndDisplayRoute ($routeType): $e');
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

   void _acceptRide(String rideId, String customerId, dynamic pickupLatRaw, dynamic pickupLngRaw, String? customerName) async {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    try {
      final pendingDetails = driverProvider.pendingRideRequestDetails;
      final String? pickupAddressName = pendingDetails?['pickupAddressName'] as String?;
      final String? dropoffAddressName = pendingDetails?['dropoffAddressName'] as String?;
      final dynamic dropoffLatRaw = pendingDetails?['dropoffLat'];
      final dynamic dropoffLngRaw = pendingDetails?['dropoffLng'];

      await driverProvider.acceptRideRequest(context, rideId, customerId);

      if (!mounted) return;
      setState(() {
        _hasActiveRide = true;
        _currentRide = {
          'rideId': rideId,
          'customerId': customerId,
          'status': 'accepted',
          'customerName': customerName ?? 'Customer',
          'pickupLat': pickupLatRaw,
          'pickupLng': pickupLngRaw,
          'pickupAddressName': pickupAddressName ?? 'Pickup Location',
          'dropoffLat': dropoffLatRaw,
          'dropoffLng': dropoffLngRaw,
          'dropoffAddressName': dropoffAddressName ?? 'Destination',
        };
        _activeRoutePolylines.clear(); // Clear proposed full route polyline
        _rideSpecificMarkers.clear(); // Clear proposed full route markers
        _currentRouteDistance = null;
        _currentlyDisplayedProposedRideId = null; // Clear the proposed ride ID
        _currentRouteDuration = null;
      });

      final double? pLat = double.tryParse(pickupLatRaw.toString());
      final double? pLng = double.tryParse(pickupLngRaw.toString());
      if (pLat != null && pLng != null) {
        await _fetchAndDisplayRouteToPickup(LatLng(pLat, pLng));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride accepted successfully')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to accept ride: ${e.toString()}')),
        );
      }
    }
  }

  void _declineRide(String rideId, String customerId) async {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    try {
      await driverProvider.declineRideRequest(context, rideId, customerId);
      if (!mounted) return;
      setState(() {
        _activeRoutePolylines.clear();
        _rideSpecificMarkers.clear(); // Clear proposed markers
        _currentRouteDistance = null;
        _currentRouteDuration = null;
        _currentlyDisplayedProposedRideId = null; // Clear the proposed ride ID
        _pendingRideCustomerName = null; // Clear customer name for sheet
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ride declined')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to decline ride: ${e.toString()}')),
        );
      }
    }
  }

  void _navigateToPickup() async {
    if (_currentRide == null) return;
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
    final pickupLocation = LatLng(pickupLat, pickupLng);

    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${pickupLocation.latitude},${pickupLocation.longitude}&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not launch navigation')));
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
      if (!mounted) return;
      await driverProvider.confirmArrival(context, rideId, customerId);
      setState(() {
        _currentRide?['status'] = 'arrived';
        _activeRoutePolylines.clear(); // Clear route to pickup
        _rideSpecificMarkers.clear(); // Clear pickup marker
        _currentRouteDistance = null;
        // _currentlyDisplayedProposedRideId is not relevant here as we are past the proposed stage
        _currentRouteDuration = null;
      });

      final dynamic pLatRaw = _currentRide?['pickupLat'];
      final dynamic pLngRaw = _currentRide?['pickupLng'];
      final dynamic dLatRaw = _currentRide?['dropoffLat'];
      final dynamic dLngRaw = _currentRide?['dropoffLng'];
      // TODO: Parse stops from _currentRide if they exist
      // final List<LatLng>? stops = ...

      final double? pLat = pLatRaw != null ? double.tryParse(pLatRaw.toString()) : null;
      final double? pLng = pLngRaw != null ? double.tryParse(pLngRaw.toString()) : null;
      final double? dLat = dLatRaw != null ? double.tryParse(dLatRaw.toString()) : null;
      final double? dLng = dLngRaw != null ? double.tryParse(dLngRaw.toString()) : null;

      if (pLat != null && pLng != null && dLat != null && dLng != null) {
        await _fetchAndDisplayMainRideRoute(LatLng(pLat, pLng), LatLng(dLat, dLng), null /* stops */);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to confirm arrival: ${e.toString()}')));
      }
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
      if (!mounted) return;
      await driverProvider.startRide(context, rideId, customerId);
      setState(() {
        _currentRide?['status'] = 'onRide';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start ride: ${e.toString()}')));
      }
    }
  }

  void _completeRide(BuildContext context, String rideId) async {
    final customerId = _currentRide?['customerId'] as String?;
    if (customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Customer ID not found for this ride.')));
      return;
    }
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    try {
      if (!mounted) return;
      await driverProvider.completeRide(context, rideId, customerId);
      setState(() {
        _hasActiveRide = false;
        _currentRide = null;
        _activeRoutePolylines.clear();
        _rideSpecificMarkers.clear();
        _currentRouteDistance = null;
        // _currentlyDisplayedProposedRideId is not relevant here
        _currentRouteDuration = null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ride completed successfully')));
      if (mounted) {
        _showRateCustomerDialog(rideId, customerId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to complete ride: ${e.toString()}')));
      }
    }
  }

  Future<void> _showRateCustomerDialog(String rideId, String customerId) async {
    double ratingValue = 0; // Renamed to avoid conflict with widget
    final theme = Theme.of(context);
    TextEditingController commentController = TextEditingController();

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Rate Customer', style: theme.textTheme.titleLarge),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    Text('How was your experience with the customer?', style: theme.textTheme.bodyMedium),
                    SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return IconButton(
                          icon: Icon(
                            index < ratingValue ? Icons.star : Icons.star_border,
                            color: accentColor, // From ui_utils
                          ),
                          onPressed: () {
                            setDialogState(() => ratingValue = index + 1.0);
                          },
                        );
                      }),
                    ),
                    SizedBox(height: 10),
                    TextField(
                      controller: commentController,
                      decoration: appInputDecoration(hintText: "Add a comment (optional)"), // Use appInputDecoration
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                ElevatedButton( // Changed to ElevatedButton for primary action
                  child: Text('Submit Rating'),
                  onPressed: () async {
                    if (ratingValue > 0) {
                      try {
                        await Provider.of<DriverProvider>(context, listen: false).rateCustomer(
                          context, // Pass context
                          customerId,
                          ratingValue,
                          rideId,
                          comment: commentController.text.trim().isNotEmpty ? commentController.text.trim() : null,
                        );
                        Navigator.of(dialogContext).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rating submitted!')));
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to submit rating: $e')));
                        }
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please select a star rating.')));
                    }
                  },
                ),
                TextButton(
                  child: Text('Skip', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCancelRideConfirmationDialog() async {
    final theme = Theme.of(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Cancel Ride', style: theme.textTheme.titleLarge),
          content: SingleChildScrollView(
            child: ListBody(children: <Widget>[Text('Are you sure you want to cancel this ride?', style: theme.textTheme.bodyMedium)]),
          ),
          actions: <Widget>[
            TextButton(child: Text('No', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))), onPressed: () => Navigator.of(dialogContext).pop()),
            TextButton(
              child: Text('Yes, Cancel', style: TextStyle(color: theme.colorScheme.error)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _cancelRide();
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
      if (!mounted) return;
      await driverProvider.cancelRide(context, rideId, customerId);
      setState(() {
        _hasActiveRide = false;
        _currentRide = null;
        _activeRoutePolylines.clear();
        _rideSpecificMarkers.clear();
        _currentRouteDistance = null;
        _currentRouteDuration = null;
        // _currentlyDisplayedProposedRideId is not relevant here
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to cancel ride: ${e.toString()}')));
      }
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