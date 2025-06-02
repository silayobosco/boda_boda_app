import 'dart:async';
import 'dart:convert'; // Added for jsonDecode
import '/utils/map_utils.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/driver_provider.dart';
import '../providers/location_provider.dart'; // Reuse from customer home
import 'package:cloud_firestore/cloud_firestore.dart'; // For fetching user data
import '../services/firestore_service.dart'; // Import FirestoreService
import '../services/auth_service.dart'; // Import AuthService to get current user ID
import '../models/Ride_Request_Model.dart'; // Import RideRequestModel
import '../utils/ui_utils.dart'; // Import UI Utils for styles and spacing

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Add this to keep the state alive


  GoogleMapController? _mapController;
  // bool _isOnline = false; // Will use DriverProvider.isOnline directly
  // bool _hasActiveRide = false; // This will be determined by _activeRideDetails != null
  RideRequestModel? _activeRideDetails; // Changed from Map<String, dynamic> to RideRequestModel
  double? _currentHeading;
  BitmapDescriptor? _bodaIcon; // Define _carIcon
  LatLng? _lastPosition; // Define _lastPosition
  bool _isIconLoaded = false; // New 
  
    // Route drawing state
  final Set<Polyline> _activeRoutePolylines = {};
  final Set<Marker> _rideSpecificMarkers = {}; // Markers for current ride (proposed or active)
  List<LatLng> _fullProposedRoutePoints = []; // Points for the customer's journey (pickup -> destination)
  List<LatLng> _driverToPickupRoutePoints = []; // Points for driver to customer's pickup
  List<LatLng> _entireActiveRidePoints = []; // Points for the complete journey: Driver -> Cust.Pickup -> Cust.Dest
  StreamSubscription? _activeRideSubscription; // To listen to the active ride document
  bool _isLoadingRoute = false;
  // String _currentRouteType = ''; // No longer needed, specific variables will be used

  String? _proposedRideDistance;
  String? _proposedRideDuration;
  String? _driverToPickupDistance;
  String? _driverToPickupDuration;
  String? _mainRideDistance;
  String? _mainRideDuration;
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
  final locationProvider = Provider.of<LocationProvider>(context, listen: false);
  locationProvider.addListener(_locationProviderListener);

  // Listen to DriverProvider's pendingRideRequestDetails
  // to initiate route drawing when a new ride is offered.
  final driverProvider = Provider.of<DriverProvider>(context, listen: false);
  driverProvider.addListener(_onDriverProviderChange);
}

@override
void dispose() {
  debugPrint("DriverHome: dispose() called");
  _mapController?.dispose();
  final locationProvider = Provider.of<LocationProvider>(context, listen: false);
  locationProvider.removeListener(_locationProviderListener);
  final driverProvider = Provider.of<DriverProvider>(context, listen: false);
  driverProvider.removeListener(_onDriverProviderChange);
  _activeRideSubscription?.cancel();
  super.dispose();
}

void _onDriverProviderChange() {
  if (!mounted) {
    debugPrint("DriverHome: _onDriverProviderChange called but widget not mounted.");
    return;
  }
  debugPrint("DriverHome: _onDriverProviderChange triggered.");
  final driverProvider = Provider.of<DriverProvider>(context, listen: false);

  if (driverProvider.pendingRideRequestDetails != null && _activeRideDetails == null) {
    final newRideId = driverProvider.pendingRideRequestDetails!['rideRequestId'] as String?;
    // Only initiate if not already loading a route AND the new ride ID is different from the one currently being proposed (or if no route is proposed)
    if (!_isLoadingRoute && (newRideId != _currentlyDisplayedProposedRideId || _activeRoutePolylines.isEmpty)) {
      debugPrint("DriverHome: New pending ride detected. ID: $newRideId. Active ride is null. Initiating full proposed route for sheet.");
      _initiateFullProposedRideRouteForSheet(driverProvider.pendingRideRequestDetails!);
    } else {
      debugPrint("DriverHome: New pending ride detected (ID: $newRideId), but either already loading a route or this route is already proposed/displayed. Skipping initiation.");
    }
  } else if (driverProvider.pendingRideRequestDetails == null && _activeRideDetails == null) {
    if (_currentlyDisplayedProposedRideId != null || _activeRoutePolylines.isNotEmpty || _rideSpecificMarkers.isNotEmpty) {
      debugPrint("DriverHome: No pending ride and no active ride. Clearing proposed route visuals.");
    }
    // No pending ride and no active ride, clear any proposed route visuals if mounted.
    if (mounted) {
      setState(() {
        _activeRoutePolylines.clear();
        _rideSpecificMarkers.clear();
        _currentlyDisplayedProposedRideId = null;
      });
    }
  }
  // If pendingRideRequestDetails is null but _activeRideDetails is NOT null, we do nothing here,
  // as the active ride sheet (_buildActiveRideSheet) will be shown.
}

  void _updateDynamicPolylineForProgress(LatLng driverCurrentLocation) {
    if (!mounted || _activeRideDetails == null) return;

    final status = _activeRideDetails!.status;
    List<LatLng> basePathPoints;
    Color polylineColor;
    String polylineIdSuffix;

    if (status == 'accepted' || status == 'goingToPickup') {
      basePathPoints = _driverToPickupRoutePoints;
      polylineColor = Colors.blueAccent; // Color for route to pickup
      polylineIdSuffix = 'active_dynamic_segment';
    } else if (status == 'arrived' || status == 'onRide') {
      basePathPoints = _fullProposedRoutePoints; // This is customer pickup to destination
      polylineColor = Colors.greenAccent; // Color for main ride
      polylineIdSuffix = 'active_dynamic_segment';
    } else {
      return; // No active segment to redraw
    }

    if (basePathPoints.isEmpty) return;

    // Find closest point on path and redraw
    int closestPointIndex = MapUtils.findClosestPointIndex(driverCurrentLocation, basePathPoints);
    if (closestPointIndex == -1 || closestPointIndex >= basePathPoints.length) return;

    List<LatLng> remainingPath = [driverCurrentLocation, ...basePathPoints.sublist(closestPointIndex)];

    setState(() {
      _activeRoutePolylines.clear(); // Clear previous dynamic polyline
      _activeRoutePolylines.add(Polyline(
        polylineId: PolylineId('dynamic_route_$polylineIdSuffix'),
        points: remainingPath,
        color: polylineColor,
        width: 6,
      ));
    });
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
    super.build(context); // Add this line
    final driverProvider = Provider.of<DriverProvider>(context);
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
          if (driverProvider.isOnline && _activeRideDetails == null && driverProvider.pendingRideRequestDetails == null && driverProvider.currentKijiweId != null)
            _buildIdleOnlineDriverView(context, driverProvider),
          if (_activeRideDetails != null) 
            _buildActiveRideSheet(), // Show if there's an active ride
          if (driverProvider.isOnline && // This condition was fine
              driverProvider.pendingRideRequestDetails != null && // Data for the sheet exists
              _activeRideDetails == null) // And no other ride is active
            _buildRideRequestSheet(driverProvider.pendingRideRequestDetails!),
          
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
    final isAtPickup = _activeRideDetails?.status == 'arrivedAtPickup'; // Corrected status
    final isRideInProgress = _activeRideDetails?.status == 'onRide';
    final theme = Theme.of(context);
    final isGoingToPickup = _activeRideDetails?.status == 'accepted' || _activeRideDetails?.status == 'goingToPickup';

    final String customerName = _activeRideDetails?.customerName ?? 'Customer';
    final String pickupAddress = _activeRideDetails?.pickupAddressName ?? 'Pickup Location';
    final String dropoffAddress = _activeRideDetails?.dropoffAddressName ?? 'Destination';
    final bool pickupStepCompleted = isAtPickup || isRideInProgress;
    final bool canNavigate = isGoingToPickup || isRideInProgress || isAtPickup; 
    final bool mainRideStarted = isRideInProgress;
    final List<Map<String, dynamic>> stops = _activeRideDetails?.stops ?? [];

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
              // Navigation FAB - Positioned within the sheet's content area
              if (canNavigate)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8.0, right: 16.0),
                    child: FloatingActionButton.small(heroTag: 'navigateSheetButton', onPressed: _navigateToNextPoint, child: Icon(Icons.navigation)),
                  ),
                ),
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
                  // TODO: Use customer profile image if available in _currentRide
                  backgroundColor: theme.colorScheme.primaryContainer, // Fallback color
                  child: Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer), // Fallback icon
                 ),
                title: Text(customerName, style: theme.textTheme.titleMedium),
                // Display customer details here
                subtitle: Text(
                  _activeRideDetails?.customerDetails ?? 'Customer details not available',
                  style: theme.textTheme.bodySmall,
                ),
                // subtitle: Text('Status: ${_currentRide?['status'] ?? 'Unknown'}', style: theme.textTheme.bodySmall), // Status is shown in Chip below
              ),

              // Display route to pickup or main ride information if available
              if ((_activeRideDetails?.status == 'accepted' && _driverToPickupDistance != null && _driverToPickupDuration != null) ||
                  ((_activeRideDetails?.status == 'arrivedAtPickup' || _activeRideDetails?.status == 'onRide') && _mainRideDistance != null && _mainRideDuration != null))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    _activeRideDetails?.status == 'accepted'
                        ? 'To Pickup: $_driverToPickupDuration · $_driverToPickupDistance'
                        : 'Ride: $_mainRideDuration · $_mainRideDistance',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary),
                  ),
                ),

              if (_isLoadingRoute && _activeRideDetails?.status == 'accepted')
                Padding(padding: const EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator())),

              Divider(),

              // Ride progress
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildRideStep(
                        Icons.pin_drop,
                        'Pickup: $pickupAddress ${(_driverToPickupDuration != null && isGoingToPickup) ? "($_driverToPickupDuration)" : ""}',
                        pickupStepCompleted
                    ),
                                        // Stops Steps
                    if (stops.isNotEmpty)
                      ...stops.asMap().entries.map((entry) {
                        final index = entry.key;
                        final stop = entry.value;
                        final stopAddress = stop['addressName'] as String? ?? 'Stop ${index + 1}'; // Cast for 'addressName' might still be needed depending on how 'stops' is populated upstream
                        // TODO: Calculate distance/duration to this stop if needed
                        return _buildRideStep(Icons.location_on, 'Stop ${index + 1}: $stopAddress', mainRideStarted); // Stops are "completed" when main ride starts
                      }).toList(),
                    // Destination Step
                    _buildRideStep(Icons.flag, 'Destination: $dropoffAddress', false), // Destination is "completed" when sheet is gone
                  ],
                ),
              ),

              // Action buttons
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (isGoingToPickup)
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
                    if (isAtPickup) ...[
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
                    ],
                    if (isRideInProgress) ...[
                        // In progress state
                        Expanded(
                        child: ElevatedButton(
                          style: theme.elevatedButtonTheme.style?.copyWith(
                            backgroundColor: MaterialStateProperty.all(successColor),
                            foregroundColor: MaterialStateProperty.all(Colors.white), // Explicit white for better contrast
                          ),
                          child: const Text('Complete Ride'),
                          onPressed: () {
                            final rideId = _activeRideDetails?.id;
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
            if (_activeRideDetails != null && !isRideInProgress && _activeRideDetails?.status != 'completed' && _activeRideDetails?.status != 'cancelled_by_driver' && _activeRideDetails?.status != 'cancelled_by_customer')
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
    final String rideRequestId = rideData['rideRequestId'] as String? ?? 'N/A'; // Corrected key
    final String customerId = rideData['customerId'] as String? ?? 'N/A';
    final dynamic pickupLatRaw = rideData['pickupLat']; // Extract before acceptRide clears it from provider
    final dynamic pickupLngRaw = rideData['pickupLng']; // Extract before acceptRide clears it from provider

    List<Map<String, dynamic>> stopsToDisplay = [];
    final dynamic stopsDataFromFCM = rideData['stops'];
    if (stopsDataFromFCM is String && stopsDataFromFCM.isNotEmpty) {
      try {
        final List<dynamic> decodedStopsList = jsonDecode(stopsDataFromFCM);
        stopsToDisplay = decodedStopsList.map((stopMapDynamic) {
          if (stopMapDynamic is Map<String, dynamic>) {
            return stopMapDynamic; // Already a map
          }
          return <String, dynamic>{}; // Return empty map or handle error
        }).where((map) => map.isNotEmpty).toList();
      } catch (e) {
        debugPrint("DriverHome (_buildRideRequestSheet): Error parsing stops from FCM: $e. Stops data: $stopsDataFromFCM");
      }
    }

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
                    rideData['customerName'] != null && rideData['customerName'].isNotEmpty
                      ? 'Ride from ${rideData['customerName']}'
                      : 'New Ride Request!'),
                subtitle: Text(
                    rideData['customerDetails'] ?? 'Customer details not available',
                    style: theme.textTheme.bodySmall, // Ensure consistent styling
                  ),
              ),
              // Display Pickup Address Name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: successColor, size: 20),
                    horizontalSpaceSmall,
                    Expanded(
                      child: Text('Pickup: ${rideData['pickupAddressName'] ?? 'Pickup Location'}', style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
              // Display Stops (if any)
              if (stopsToDisplay.isNotEmpty)
                ...stopsToDisplay.map((stopMap) {
                  final stopAddress = stopMap['addressName'] as String? ?? (stopMap['name'] as String? ?? 'Stop');
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, color: successColor, size: 20),
                        horizontalSpaceSmall,
                        Expanded(
                          child: Text(stopAddress, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  );
                }).toList(),

              // Display route to pickup information if available
              if (_proposedRideDistance != null && _proposedRideDuration != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0), // Use verticalSpaceSmall
                  child: Text(
                    'Proposed Route: $_proposedRideDuration · $_proposedRideDistance',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary),
                  ),
                ),
              // Show loading indicator if the proposed route is being fetched for the sheet
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
    final rideId = _activeRideDetails?.id;
    final customerId = _activeRideDetails?.customerId;
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

    if (errorMessage != null) {
      if (!mounted) return; // Check if widget is still in the tree BEFORE showing SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } else {
      // Success, UI already updated by provider's notifyListeners
      if (!mounted) return; // Check if widget is still in the tree BEFORE showing SnackBar
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
      // Only center map on driver if online AND not on an active or pending ride
      if (driverProvider.isOnline && _mapController != null && _lastPosition != null && _activeRideDetails == null && driverProvider.pendingRideRequestDetails == null) {
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(_lastPosition!),
        );
      }

      if (driverProvider.isOnline && _lastPosition != null) {
        driverProvider.updateDriverPosition(_lastPosition!, _currentHeading).catchError((e) {
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
    final String? newRideRequestId = rideData['rideRequestId'] as String?; // Corrected key

    if (newRideRequestId == null) {
      debugPrint("DriverHome: Proposed ride has no ID. Cannot fetch/display route.");
      return;
    }

    // If already loading a route, or if the current proposed ride is already displayed for the *same* ride ID, do nothing.
    if (_isLoadingRoute) {
      debugPrint("DriverHome: _initiateFullProposedRideRouteForSheet - Already loading route for ID: $newRideRequestId. Skipping.");
      // debugPrint("DriverHome: Route is currently being loaded. Skipping fetch for $newRideRequestId.");
      return;
    }
    // Check if the same proposed ride's route and markers are already displayed
    if (newRideRequestId == _currentlyDisplayedProposedRideId && _activeRoutePolylines.isNotEmpty && _rideSpecificMarkers.any((m) => m.markerId.value.startsWith('proposed_'))) {
      // debugPrint("DriverHome: Proposed route already displayed for $newRideRequestId. Skipping fetch.");
      // If already displayed, ensure map is zoomed correctly to the full view
      debugPrint("DriverHome: _initiateFullProposedRideRouteForSheet - Proposed route already displayed for ID: $newRideRequestId. Skipping fetch.");
      return;
    }


    final dynamic pickupLatDynamic = rideData['pickupLat'];
    final dynamic pickupLngDynamic = rideData['pickupLng'];
    final dynamic dropoffLatDynamic = rideData['dropoffLat'];
    debugPrint("DriverHome: _initiateFullProposedRideRouteForSheet - Starting route fetch for ID: $newRideRequestId");
    final dynamic dropoffLngDynamic = rideData['dropoffLng'];
    
    List<LatLng> customerStops = [];
    final dynamic stopsDataFromFCM = rideData['stops'];

    if (stopsDataFromFCM is String && stopsDataFromFCM.isNotEmpty) {
      try {
        final List<dynamic> decodedStopsList = jsonDecode(stopsDataFromFCM);
        customerStops = decodedStopsList.map((stopMapDynamic) {
          if (stopMapDynamic is Map<String, dynamic>) {
            final stopMap = stopMapDynamic; // Already a map
            final locationString = stopMap['location'] as String?;
            if (locationString != null) {
              final parts = locationString.split(',');
              if (parts.length == 2) {
                final lat = double.tryParse(parts[0]);
                final lng = double.tryParse(parts[1]);
                if (lat != null && lng != null) {
                  return LatLng(lat, lng);
                }
              }
            }
          }
          return null; // Or throw an error for invalid stop format
        }).whereType<LatLng>().toList();
      } catch (e) {
        debugPrint("DriverHome: Error parsing stops from FCM: $e. Stops data: $stopsDataFromFCM");
      }
    }

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

    // Build waypoints list for the API: pickup first, then stops (if any)
    final List<LatLng> waypointsForApi = [ridePickupLocation, ...customerStops];

    // Get driver's current location
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    if (locationProvider.currentLocation == null) {
      await locationProvider.updateLocation(); // Try to get location
      if (locationProvider.currentLocation == null) return; // Still not available
    }
    final driverCurrentLocation = LatLng(locationProvider.currentLocation!.latitude, locationProvider.currentLocation!.longitude);

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
        origin: driverCurrentLocation, // Origin is now driver's current location
        destination: rideDropoffLocation, // Destination is customer's final drop-off
        waypoints: waypointsForApi, // Customer pickup is the first waypoint
        polylineColor: Colors.deepPurpleAccent,
        onRouteFetched: (distance, duration, points) {
          if (!mounted) return; // Guard setState in callback
          if (mounted && points != null && points.isNotEmpty) {
            setState(() {
              // These now represent the ENTIRE journey from driver to customer's final destination
              _proposedRideDistance = distance;
              _proposedRideDuration = duration;
              _entireActiveRidePoints = points;
              _activeRoutePolylines.clear();
              _activeRoutePolylines.add(Polyline(polylineId: const PolylineId('full_initial_route'), points: _entireActiveRidePoints, color: Colors.deepPurpleAccent, width: 6));

              // Segment the points for later use
              int pickupIndexInEntireRoute = MapUtils.findClosestPointIndex(ridePickupLocation, _entireActiveRidePoints);
              if (pickupIndexInEntireRoute != -1) {
                _driverToPickupRoutePoints = _entireActiveRidePoints.sublist(0, pickupIndexInEntireRoute + 1);
                _fullProposedRoutePoints = _entireActiveRidePoints.sublist(pickupIndexInEntireRoute);
              } else {
                _driverToPickupRoutePoints = [];
                _fullProposedRoutePoints = List.from(_entireActiveRidePoints); // Fallback
              }

              // Draw two polylines for the proposed route view
              _activeRoutePolylines.clear();
              if (_driverToPickupRoutePoints.isNotEmpty) {
                _activeRoutePolylines.add(Polyline(polylineId: const PolylineId('proposed_driver_to_pickup'), points: _driverToPickupRoutePoints, color: Colors.blueAccent, width: 6));
              }
              if (_fullProposedRoutePoints.isNotEmpty) {
                _activeRoutePolylines.add(Polyline(polylineId: const PolylineId('proposed_customer_journey'), points: _fullProposedRoutePoints, color: Colors.deepPurpleAccent, width: 6));
              }
              // Zoom to fit the entire initially proposed route
              final LatLngBounds? bounds = MapUtils.boundsFromLatLngList(_entireActiveRidePoints);
              if (_mapController != null) _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds!, 60)); // Removed redundant bounds != null check
            });
          }
        });

    if (mounted) {
      debugPrint("DriverHome: _initiateFullProposedRideRouteForSheet - Setting markers for proposed ride ID: $newRideRequestId");
      setState(() {
        _rideSpecificMarkers.clear();
        _rideSpecificMarkers.add(Marker(
          markerId: MarkerId('proposed_pickup'),
          position: ridePickupLocation, // Customer's pickup
          infoWindow: InfoWindow(title: 'Pickup: ${rideData['pickupAddressName'] as String? ?? 'Customer Pickup'}'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ));
        _rideSpecificMarkers.add(Marker(
          markerId: MarkerId('proposed_dropoff'),
          position: rideDropoffLocation,
          infoWindow: InfoWindow(title: 'Destination: ${rideData['dropoffAddressName'] ?? 'Customer Destination'}'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ));
                customerStops.asMap().forEach((index, stopLatLng) {
          _rideSpecificMarkers.add(Marker(
            markerId: MarkerId('proposed_stop_$index'),
            position: stopLatLng,
            infoWindow: InfoWindow(title: 'Stop ${index + 1}'), // You might need stop names from rideData
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          ));
        });
      });
    }
    // Update the ID of the currently displayed proposed route
    if (mounted && _activeRoutePolylines.isNotEmpty && !_isLoadingRoute) {
      // Set this regardless of whether markers were added, as long as polyline is there
      debugPrint("DriverHome: _initiateFullProposedRideRouteForSheet - Setting _currentlyDisplayedProposedRideId to: $newRideRequestId");
      _currentlyDisplayedProposedRideId = newRideRequestId;
    }
  }

  // Modified to use pre-fetched segment points and handle zoom/dynamic polyline.
  Future<void> _fetchAndDisplayRouteToPickup(BuildContext context, LatLng customerPickupLocation) async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    if (locationProvider.currentLocation == null) return;
    final driverCurrentLocation = LatLng(locationProvider.currentLocation!.latitude, locationProvider.currentLocation!.longitude);

    // Use the pre-calculated segment points
    if (mounted && _driverToPickupRoutePoints.isNotEmpty) {
      setState(() {
        _activeRoutePolylines.clear();
        _activeRoutePolylines.add(Polyline(polylineId: const PolylineId('driver_to_pickup_active'), points: _driverToPickupRoutePoints, color: Colors.blueAccent, width: 6));
        // Distance and duration for this segment are not re-fetched here.
        // They could be calculated manually or parsed from the initial full route response if available.
      });
      _zoomToDriverToPickupSegment(driverCurrentLocation, customerPickupLocation);
      _updateDynamicPolylineForProgress(driverCurrentLocation);
    } else {
       debugPrint("DriverHome: _driverToPickupRoutePoints is empty. Cannot display route to pickup.");
       // Fallback: Maybe zoom to driver and pickup location without polyline?
       _zoomToDriverToPickupSegment(driverCurrentLocation, customerPickupLocation);
    }

    // Add marker for customer's pickup when navigating to them
    if (mounted) {
      setState(() {
        _rideSpecificMarkers.clear(); // Clear previous proposed markers
        _rideSpecificMarkers.add(Marker(
          markerId: MarkerId('customer_pickup_active'),
          position: customerPickupLocation,
          infoWindow: InfoWindow(title: 'Pickup: ${_activeRideDetails?.pickupAddressName ?? 'Customer Pickup'}'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ));
      });
    }
  }

  // Fetches and displays route from CUSTOMER'S PICKUP to CUSTOMER'S DESTINATION (Main Ride)
  // Modified to use pre-fetched segment points and handle zoom/dynamic polyline.
  Future<void> _fetchAndDisplayMainRideRoute(LatLng ridePickup, LatLng rideDropoff, List<LatLng>? stops) async {
    if (!mounted) return;

    // Use the pre-calculated segment points
    if (mounted && _fullProposedRoutePoints.isNotEmpty) {
      setState(() {
        _activeRoutePolylines.clear();
        _activeRoutePolylines.add(Polyline(polylineId: const PolylineId('main_ride_active'), points: _fullProposedRoutePoints, color: Colors.greenAccent, width: 6));
        // Distance and duration for this segment are not re-fetched here.
        // They could be calculated manually or parsed from the initial full route response if available.
      });
      _zoomToMainRideSegment(ridePickup, rideDropoff, stops);
      _updateDynamicPolylineForProgress(ridePickup); // Start dynamic polyline from pickup
    } else {
      debugPrint("DriverHome: _fullProposedRoutePoints is empty. Cannot display main ride route.");
      // Fallback: Maybe zoom to pickup, destination, and stops without polyline?
      _zoomToMainRideSegment(ridePickup, rideDropoff, stops);
    }

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
    required Function(String? distance, String? duration, List<LatLng>? points) onRouteFetched,
  }) async {
    if (origin.latitude == destination.latitude && origin.longitude == destination.longitude && (waypoints == null || waypoints.isEmpty)) {
      debugPrint("DriverHome: Origin and Destination are the same, and no waypoints. Skipping route draw.");
      if (mounted) setState(() => _isLoadingRoute = false);
      if (!mounted) return; // Check before calling callback
      onRouteFetched(null, null, null); // Call with nulls as no route is drawn
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingRoute = true;
      // _activeRoutePolylines.clear(); // Let the caller manage clearing polylines
      // _rideSpecificMarkers are managed by the calling functions like _initiateFullProposedRideRouteForSheet, _fetchAndDisplayRouteToPickup, etc.
      // Clear all specific route details before fetching a new one
      _proposedRideDistance = null; _proposedRideDuration = null;
      _driverToPickupDistance = null; _driverToPickupDuration = null;
      _mainRideDistance = null; _mainRideDuration = null;
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
        // Call the onRouteFetched callback with the data.
        // The caller will handle setState, polyline creation, and zooming.
        onRouteFetched(
          primaryRouteDetails['distance'] as String?,
          primaryRouteDetails['duration'] as String?,
          primaryRouteDetails['points'] as List<LatLng>?,
        );
        // No need to check mounted again here as onRouteFetched should handle it
        if (mounted) setState(() => _isLoadingRoute = false);
      } else {
        if (mounted) setState(() => _isLoadingRoute = false);
        if (!mounted) return; // Check before calling callback
        onRouteFetched(null, null, null);
      }
    } catch (e) {
      debugPrint('Error in _fetchAndDisplayRoute: $e');
      if (mounted) setState(() { _isLoadingRoute = false;});
      if (!mounted) return; // Check before calling callback
      onRouteFetched(null, null, null);    }
  }

  void _zoomToDriverToPickupSegment(LatLng driverLocation, LatLng customerPickup) {
    if (_mapController == null) return;
    final bounds = MapUtils.boundsFromLatLngList([driverLocation, customerPickup]);
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  void _zoomToMainRideSegment(LatLng customerPickup, LatLng customerDestination, List<LatLng>? stops) {
    if (_mapController == null) return;
    List<LatLng> pointsForBounds = [customerPickup, customerDestination];
    if (stops != null && stops.isNotEmpty) {
      pointsForBounds.addAll(stops);
    }
    final bounds = MapUtils.boundsFromLatLngList(pointsForBounds);
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  void _clearAllRouteData() {
    _activeRoutePolylines.clear();
    _fullProposedRoutePoints.clear();
    _driverToPickupRoutePoints.clear();
    _entireActiveRidePoints.clear();
  }
   void _acceptRide(String rideId, String customerId, dynamic pickupLatRaw, dynamic pickupLngRaw, String? customerName) async {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    debugPrint("DriverHome: _acceptRide called for ride ID: $rideId");
    try {
      final pendingDetails = driverProvider.pendingRideRequestDetails;
      final String? pickupAddressName = pendingDetails?['pickupAddressName'] as String?;
      final String? dropoffAddressName = pendingDetails?['dropoffAddressName'] as String?;
      final dynamic dropoffLatRaw = pendingDetails?['dropoffLat'];
      final dynamic dropoffLngRaw = pendingDetails?['dropoffLng'];

      await driverProvider.acceptRideRequest(context, rideId, customerId);

      if (!mounted) return;
      debugPrint("DriverHome: _acceptRide - Ride accepted in provider. Updating local state.");
      setState(() {
        // Create a basic RideRequestModel instance.
        // The full details will come from the Firestore stream.
        _activeRideDetails = RideRequestModel(
          id: rideId,
          customerId: customerId,
          status: 'accepted', // Initial status after acceptance
          customerName: customerName ?? 'Customer',
          pickup: LatLng(double.parse(pickupLatRaw.toString()), double.parse(pickupLngRaw.toString())),
          dropoff: LatLng(double.parse(dropoffLatRaw.toString()), double.parse(dropoffLngRaw.toString())),
          pickupAddressName: pickupAddressName ?? 'Pickup Location',
          dropoffAddressName: dropoffAddressName ?? 'Destination',
          stops: [], // Initialize with empty stops, will be populated by stream if they exist
          // Other fields will be null or default initially
        );
        _activeRoutePolylines.clear(); // Clear proposed full route polyline
        _rideSpecificMarkers.clear(); // Clear proposed full route markers
        _proposedRideDistance = null; _proposedRideDuration = null; // Clear proposed route info
        _clearAllRouteData(); // Clears _entireActiveRidePoints, _fullProposedRoutePoints, _driverToPickupRoutePoints
        _currentlyDisplayedProposedRideId = null; // Clear the proposed ride ID
      });

      // Start listening to the active ride document
      _listenToActiveRide(rideId);
      
      // After setting state, call _fetchAndDisplayRouteToPickup which will handle zoom and initial dynamic polyline
      if (pickupLatRaw != null && pickupLngRaw != null) {
        final LatLng customerPickupLoc = LatLng(double.parse(pickupLatRaw.toString()), double.parse(pickupLngRaw.toString()));
        await _fetchAndDisplayRouteToPickup(context, customerPickupLoc);
        if (!mounted) return; // Check after await
      }
      debugPrint("DriverHome: _acceptRide - UI state updated, snackbar shown.");
      // Ensure context is still valid before showing SnackBar
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

  void _listenToActiveRide(String rideId) {
    _activeRideSubscription?.cancel(); // Cancel any existing subscription
    debugPrint("DriverHome: _listenToActiveRide - Subscribing to ride ID: $rideId");
    // FirestoreService is not a Provider, so we instantiate it or get it from a Provider if it was set up as one.
    // Assuming you have a way to access FirestoreService instance, e.g., if it's a singleton or passed around.
    final firestoreService = FirestoreService(); // Or however you access your FirestoreService instance
    _activeRideSubscription = firestoreService.getRideRequestDocumentStream(rideId).listen(
      (DocumentSnapshot rideSnapshot) {
        if (mounted && rideSnapshot.exists && rideSnapshot.data() != null) {
          final newRideDetails = RideRequestModel.fromJson(rideSnapshot.data() as Map<String, dynamic>, rideSnapshot.id);
          debugPrint("DriverHome: _listenToActiveRide - Received update for ride ID: ${newRideDetails.id}, Status: ${newRideDetails.status}");
          setState(() {
            _activeRideDetails = newRideDetails;
            // Potentially update map/route based on new status if needed here,
            // though specific actions like _confirmArrival already handle this.
            if (newRideDetails.status == 'completed' ||
                newRideDetails.status == 'cancelled_by_customer' ||
                newRideDetails.status == 'cancelled_by_driver') {
              debugPrint("DriverHome: _listenToActiveRide - Ride ${newRideDetails.id} ended. Resetting active ride state.");
              _resetActiveRideState();
            }
          });
        } else if (mounted && !rideSnapshot.exists) {
          debugPrint("DriverHome: _listenToActiveRide - Ride document $rideId no longer exists. Resetting active ride state.");
          // Ride document was deleted or doesn't exist anymore
          _resetActiveRideState();
        }
      },
      onError: (error) {
        debugPrint("Error listening to active ride $rideId: $error");
        if (mounted) {
          // Optionally show an error to the user or attempt to re-subscribe
          // For now, just reset the state if an error occurs
          _resetActiveRideState();
        }
      }
    );
  }


  void _declineRide(String rideId, String customerId) async {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    debugPrint("DriverHome: _declineRide called for ride ID: $rideId");
    try {
      await driverProvider.declineRideRequest(context, rideId, customerId);
      if (!mounted) return;
      debugPrint("DriverHome: _declineRide - Ride declined in provider. Clearing local proposed ride state.");
      setState(() {
        _rideSpecificMarkers.clear(); // Clear proposed markers
        _proposedRideDistance = null; _proposedRideDuration = null;
        _driverToPickupDistance = null; _driverToPickupDuration = null; // Also clear this if it was somehow set
        _currentlyDisplayedProposedRideId = null; // Clear the proposed ride ID
        _clearAllRouteData();
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

  Future<void> _navigateToNextPoint() async {
    if (_activeRideDetails == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No active ride.')));
      return;
    }

    final String status = _activeRideDetails!.status;
    LatLng? destinationLatLng;
    String destinationName = "Next Destination";

    if (status == 'accepted' || status == 'goingToPickup') {
      destinationLatLng = _activeRideDetails!.pickup;
      destinationName = _activeRideDetails!.pickupAddressName ?? "Pickup";
    } else if (status == 'onRide' || status == 'arrivedAtPickup') { // 'arrivedAtPickup' implies next point is start of main ride or first stop
      final List<Map<String, dynamic>> stops = _activeRideDetails!.stops;
      // For simplicity, we'll assume stops are ordered and we navigate to the first one if not yet "completed"
      // A more robust solution would track completed stops.
      if (stops.isNotEmpty) {
        // Find the first "unvisited" stop. This is a simplified logic.
        final firstStop = stops.first; // Assuming stops are ordered
        destinationLatLng = firstStop['location'] as LatLng?;
        destinationName = firstStop['addressName'] as String? ?? "Next Stop";
      }

      // If no stops or all stops visited, navigate to final destination
      if (destinationLatLng == null) {
        destinationLatLng = _activeRideDetails!.dropoff;
        destinationName = _activeRideDetails!.dropoffAddressName ?? "Final Destination";
      }
    }

    if (destinationLatLng != null) {
      final uri = Uri.parse('google.navigation:q=${destinationLatLng.latitude},${destinationLatLng.longitude}&mode=d');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not launch navigation to $destinationName')));
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Next destination not available.')));
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
    debugPrint("DriverHome: _confirmArrival called for ride ID: $rideId");

    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    try {
      if (!mounted) return;
      await driverProvider.confirmArrival(context, rideId, customerId);
      setState(() {
        // _activeRideDetails will be updated by the stream listener
        //_activeRoutePolylines.clear(); // Clear route to pickup
        _rideSpecificMarkers.clear(); // Clear pickup marker for "to pickup" route
        _driverToPickupDistance = null; _driverToPickupDuration = null; // Clear "to pickup" route info
      });

      // The stream listener for _activeRideDetails will update its status.
      // We can then react to the 'arrivedAtPickup' status to draw the main ride route.
      // This logic might be better placed within the stream listener's setState block.
      if (_activeRideDetails?.status == 'arrivedAtPickup') {
        final LatLng? pickup = _activeRideDetails?.pickup;
        final LatLng? dropoff = _activeRideDetails?.dropoff;
        final List<LatLng> stops = _activeRideDetails?.stops.map((s) => s['location'] as LatLng).toList() ?? [];
        if (pickup != null && dropoff != null) {
          await _fetchAndDisplayMainRideRoute(pickup, dropoff, stops);
          _zoomToMainRideSegment(pickup, dropoff, stops);
        }
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
    debugPrint("DriverHome: _startRide called for ride ID: $rideId");
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    try {
      if (!mounted) return;
      await driverProvider.startRide(context, rideId, customerId);
      setState(() {
        // _activeRideDetails will be updated by the stream listener
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start ride: ${e.toString()}')));
      }
    }
  }

  void _completeRide(BuildContext context, String rideId) async {
    final customerId = _activeRideDetails?.customerId;
    if (customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Customer ID not found for this ride.')));
      return;
    }
    debugPrint("DriverHome: _completeRide called for ride ID: $rideId");
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    try {
      if (!mounted) return;
      await driverProvider.completeRide(context, rideId, customerId);
      // UI update handled by stream listener or _resetActiveRideState.
      // We'll call _resetActiveRideState after attempting to show the dialog.

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ride completed successfully')));

      // Schedule the dialog and state reset to occur after the current frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showRateCustomerDialog(rideId, customerId);
          _resetActiveRideState(); // Reset state after dialog is queued or shown
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to complete ride: ${e.toString()}')));
      }
    }
  }

  void _resetActiveRideState() {
    if (mounted) {
      debugPrint("DriverHome: _resetActiveRideState called.");
      setState(() {
        _activeRideDetails = null;
        _activeRideSubscription?.cancel();
        _activeRideSubscription = null;
        _clearAllRouteData();
        _rideSpecificMarkers.clear();
        _mainRideDistance = null; _mainRideDuration = null;
        _driverToPickupDistance = null; _driverToPickupDuration = null;
      });
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
    debugPrint("DriverHome: _cancelRide called for ride ID: $rideId");
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    try {
      if (!mounted) return;
      await driverProvider.cancelRide(context, rideId, customerId);
      _resetActiveRideState(); // UI update handled by stream listener or this reset
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to cancel ride: ${e.toString()}')));
      }
    }
  }

  Widget _buildIdleOnlineDriverView(BuildContext context, DriverProvider driverProvider) {
    final theme = Theme.of(context);
    final firestoreService = FirestoreService(); // Assuming you have a way to access this
    final authService = AuthService(); // To get current driver's ID
    final String? currentDriverId = authService.currentUser?.uid;

    // Achievements from DriverProvider
    final achievements = driverProvider.driverProfileData;
    final completedRides = achievements?['completedRidesCount']?.toString() ?? '0';
    final averageRating = (achievements?['averageRating'] as num?)?.toStringAsFixed(1) ?? 'N/A';

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Card(
        elevation: 8,
        margin: const EdgeInsets.all(8), // Add some margin
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Waiting for Ride...", style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary)),
              verticalSpaceSmall,
              if (driverProvider.currentKijiweId != null)
                StreamBuilder<DocumentSnapshot>(
                  stream: firestoreService.getKijiweQueueStream(driverProvider.currentKijiweId!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Row(children: [Text("Kijiwe: ", style: theme.textTheme.bodyMedium), CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary))]);
                    }
                    if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                      return Text("Kijiwe: Not Found", style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error));
                    }
                    final kijiweData = snapshot.data!.data() as Map<String, dynamic>;
                    final kijiweName = kijiweData['name'] as String? ?? 'Unnamed Kijiwe';
                    final List<dynamic> queue = kijiweData['queue'] as List<dynamic>? ?? [];
                    final queuePosition = currentDriverId != null ? queue.indexOf(currentDriverId) : -1;
                    final positionText = queuePosition != -1 ? "${queuePosition + 1}/${queue.length}" : "Not in queue";

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Kijiwe: $kijiweName", style: theme.textTheme.titleMedium),
                        Text("Your Position: $positionText", style: theme.textTheme.bodyMedium),
                      ],
                    );
                  },
                )
              else
                Text("Not associated with a Kijiwe.", style: theme.textTheme.bodyMedium),
              
              verticalSpaceMedium,
              Text("Your Stats:", style: theme.textTheme.titleMedium),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatItem(theme, Icons.motorcycle, "Rides", completedRides),
                  _buildStatItem(theme, Icons.star, "Rating", averageRating),
                  // Add more stats if needed
                ],
              ),
              verticalSpaceSmall,
              // You could add a "Refresh" button or other actions here if needed
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(ThemeData theme, IconData icon, String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: theme.colorScheme.secondary, size: 28),
        verticalSpaceSmall,
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }


  }
  