import 'dart:async';
import 'dart:convert'; // Added for jsonDecode
import 'manual_ride_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '/utils/map_utils.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmf; // Hide LatLng to avoid conflict with latlong2
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/driver_provider.dart';
import '../providers/location_provider.dart'; // Reuse from customer home
import 'package:cloud_firestore/cloud_firestore.dart'; // For fetching user data
import '../services/firestore_service.dart'; // Import FirestoreService
import '../services/auth_service.dart'; // Import AuthService to get current user ID
import '../models/Ride_Request_Model.dart'; // Import RideRequestModel
import 'package:latlong2/latlong.dart' as ll; // Use latlong2 for calculations
import '../utils/ui_utils.dart'; // Import UI Utils for styles and spacing
import 'package:flutter_localization/flutter_localization.dart';
import '../localization/locales.dart';
import 'chat_screen.dart'; // Import ChatScreen

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Add this to keep the state alive


  gmf.GoogleMapController? _mapController;
  // bool _isOnline = false; // Will use DriverProvider.isOnline directly
  // bool _hasActiveRide = false; // This will be determined by _activeRideDetails != null
  RideRequestModel? _activeRideDetails; // Changed from Map<String, dynamic> to RideRequestModel
  gmf.Marker? _currentKijiweMarker;
  double? _currentHeading;
  gmf.BitmapDescriptor? _bodaIcon; // Define _carIcon
  ll.LatLng? _lastPosition; // Define _lastPosition using latlong2
  bool _isIconLoaded = false; // New 
  double _dailyEarnings = 0.0; // New field for daily earnings
  
    // Route drawing state
  final Set<gmf.Polyline> _activeRoutePolylines = {};
  final Set<gmf.Marker> _rideSpecificMarkers = {}; // Markers for current ride (proposed or active)
  List<gmf.LatLng> _fullProposedRoutePoints = []; // Points for the customer's journey (pickup -> destination)
  List<gmf.LatLng> _driverToPickupRoutePoints = []; // Points for driver to customer's pickup
  List<gmf.LatLng> _entireActiveRidePoints = []; // Points for the complete journey: Driver -> Cust.Pickup -> Cust.Dest
  StreamSubscription? _activeRideSubscription; // To listen to the active ride document
  StreamSubscription? _kijiweSubscription;
  bool _isLoadingRoute = false;
  // String _currentRouteType = ''; // No longer needed, specific variables will be used

  String? _proposedRideDistance;
  String? _proposedRideDuration;
  String? _driverToPickupDistance;
  List<Map<String, dynamic>>? _proposedRouteLegsData; // To store legs of the proposed route
  String? _driverToPickupDuration;
  String? _mainRideDistance;
  String? _mainRideDuration;
  String? _pendingRideCustomerName;
  String? _currentlyDisplayedProposedRideId; // To track the ID of the ride for which a proposed route is shown
  final String _googlePlacesApiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;
  
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  double _currentSheetSize = 0.0; // For map padding
 
  final GlobalKey _rideRequestSheetKey = GlobalKey();
  double _rideRequestSheetHeight = 0.0;

  Timer? _declineTimer;
  int _countdownSeconds = 30; // Countdown duration in seconds

  // Ride Tracking Variables
  DateTime? _rideTrackingStartTime;
  ll.LatLng? _rideTrackingLastLocation;
  double _trackedDistanceKm = 0.0;
  int _trackedDrivingDurationSeconds = 0; 

  // To safely access providers in dispose() and listeners
  late final LocationProvider _locationProvider;
  late final DriverProvider _driverProvider;
  // Helper to get leg details
  String? getLegInfo(int legIndex) {
    // debugPrint("getLegInfo called for index: $legIndex. _proposedRouteLegsData has ${_proposedRouteLegsData?.length ?? 0} items.");
    if (_proposedRouteLegsData != null && legIndex >= 0 && legIndex < _proposedRouteLegsData!.length) {
      final leg = _proposedRouteLegsData![legIndex];
      final distance = leg['distance']?['text'] as String?;
      final duration = leg['duration']?['text'] as String?;
      // debugPrint("getLegInfo($legIndex): distance=$distance, duration=$duration");
      if (distance != null && duration != null) {
        return '$duration · $distance';
      }
    }
    // debugPrint("getLegInfo($legIndex): No data found.");
    return null;
  }

    // Define the listener method
  void _locationProviderListener() {
    debugPrint("DriverHome: _locationProviderListener invoked. Mounted: $mounted, Location: ${_locationProvider.currentLocation}");
    if (mounted && _locationProvider.currentLocation != null) { // Mounted check within the listener
      _updateDriverLocationAndMap(_locationProvider);
    }
  }


  @override
void initState() {
  super.initState();
  // Initialize providers here to safely access them in dispose() and listeners.
  _locationProvider = Provider.of<LocationProvider>(context, listen: false);
  _driverProvider = Provider.of<DriverProvider>(context, listen: false);

  _loadCustomMarker().then((_) { // Ensure marker is loaded, then initialize state
    if (mounted) {
      setState(() {
        _isIconLoaded = true;
      });
    }
    _initializeDriverStateAndLocation();
  });
  // Add listener for LocationProvider
  debugPrint("DriverHome: initState - Adding LocationProvider listener.");
  _sheetController.addListener(_onSheetChanged);
  _locationProvider.addListener(_locationProviderListener);

  // Listen to DriverProvider's pendingRideRequestDetails
  // to initiate route drawing when a new ride is offered.
  _driverProvider.addListener(_onDriverProviderChange);
}

@override
void dispose() {
  debugPrint("DriverHome: dispose() called");
  _mapController?.dispose();
  _sheetController.removeListener(_onSheetChanged);
  _sheetController.dispose();
  _locationProvider.removeListener(_locationProviderListener);
  _driverProvider.removeListener(_onDriverProviderChange);
  _activeRideSubscription?.cancel();
  _kijiweSubscription?.cancel();
  _declineTimer?.cancel(); // Cancel timer on dispose
  super.dispose();
  debugPrint("DriverHome: dispose() completed.");
}

void _onSheetChanged() {
  if (!mounted) return;
  // Only update the size if the active ride sheet is the one being shown
  if (_activeRideDetails != null) {
    setState(() {
      _currentSheetSize = _sheetController.size;
    });
  }
  }

void _onDriverProviderChange() {
  if (!mounted) {
    debugPrint("DriverHome: _onDriverProviderChange called but widget not mounted.");
    return;
  }
  final driverProvider = Provider.of<DriverProvider>(context, listen: false);
  // Add this debug print
  debugPrint("DriverHome: _onDriverProviderChange triggered. PendingDetails: ${(driverProvider.pendingRideRequestDetails != null) ? driverProvider.pendingRideRequestDetails!['rideRequestId'] : null}, ActiveRide: ${_activeRideDetails?.id}");

  if (driverProvider.pendingRideRequestDetails != null && _activeRideDetails == null) {
    final newRideId = driverProvider.pendingRideRequestDetails!['rideRequestId'] as String?;
     // Add this debug print
    debugPrint("DriverHome: Condition met for new pending ride. NewRideID: $newRideId, isLoadingRoute: $_isLoadingRoute, currentProposedID: $_currentlyDisplayedProposedRideId, polylinesEmpty: ${_activeRoutePolylines.isEmpty}");

    // Only initiate if not already loading a route AND the new ride ID is different from the one currently being proposed (or if no route is proposed) AND the sheet is not already showing an active ride
    if (!_isLoadingRoute && (newRideId != _currentlyDisplayedProposedRideId || _activeRoutePolylines.isEmpty)) {
      debugPrint("DriverHome: Initiating full proposed route for sheet for ride ID: $newRideId.");
      _startDeclineTimer(); // Start the countdown timer
      _measureRideRequestSheet(); // Measure the sheet when it's about to be displayed
      _initiateFullProposedRideRouteForSheet(driverProvider.pendingRideRequestDetails!);
    } else {
      debugPrint("DriverHome: New pending ride detected (ID: $newRideId), but either already loading a route or this route is already proposed/displayed. Skipping initiation.");
    }
  } else if (driverProvider.pendingRideRequestDetails == null && _activeRideDetails == null) {
    
    // No pending ride and no active ride, clear any proposed route visuals if mounted.
    // Add this debug print
    debugPrint("DriverHome: No pending ride and no active ride. CurrentProposedID: $_currentlyDisplayedProposedRideId, polylinesEmpty: ${_activeRoutePolylines.isEmpty}");
    if (_currentlyDisplayedProposedRideId != null || _activeRoutePolylines.isNotEmpty || _rideSpecificMarkers.isNotEmpty) {
      _cancelDeclineTimer(); // Cancel timer if request is cleared
      debugPrint("DriverHome: Clearing proposed route visuals.");
    }
    _rideRequestSheetHeight = 0.0; // Reset sheet height when no pending ride
    if (mounted) {
      setState(() {
        _activeRoutePolylines.clear();
        _rideSpecificMarkers.clear();
        _currentlyDisplayedProposedRideId = null;
        // Also clear distance/duration for proposed route
        _proposedRideDistance = null;
        _proposedRideDuration = null;
        _proposedRouteLegsData = null; // Clear legs data
      });
    }
  } else {
    // Add this debug print
    debugPrint("DriverHome: _onDriverProviderChange - Neither condition met. PendingDetails: ${(driverProvider.pendingRideRequestDetails?['rideRequestId'])}, ActiveRide: ${_activeRideDetails?.id}");

  }
  // If pendingRideRequestDetails is null but _activeRideDetails is NOT null, we do nothing here,
  // as the active ride sheet (_buildActiveRideSheet) will be shown.
}

void _startDeclineTimer() {
  _cancelDeclineTimer(); // Ensure no other timer is running
  if (mounted) {
    setState(() => _countdownSeconds = 30); // Reset countdown
  }
  _declineTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (!mounted) {
      timer.cancel();
      return;
    }
    if (_countdownSeconds > 0) {
      setState(() => _countdownSeconds--);
    } else {
      timer.cancel();
      final rideData = Provider.of<DriverProvider>(context, listen: false).pendingRideRequestDetails;
      if (rideData != null) {
        debugPrint("Auto-declining ride due to timeout: ${rideData['rideRequestId']}");
        _declineRide(rideData['rideRequestId'], rideData['customerId']);
      }
    }
  });
}

void _cancelDeclineTimer() {
  _declineTimer?.cancel();
}

void _measureRideRequestSheet() {
  // This function is called when we know the sheet is about to be built.
  // We use a post-frame callback to ensure the widget has been laid out.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || _rideRequestSheetKey.currentContext == null) return;
    
    final RenderBox? renderBox = _rideRequestSheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final newHeight = renderBox.size.height;
      if (_rideRequestSheetHeight != newHeight) {
        setState(() => _rideRequestSheetHeight = newHeight);
      }
    }
  });
}
  // This method is called by the LocationProvider listener
  void _updateDynamicPolylineForProgress(gmf.LatLng driverCurrentLocation) { // This is correct
    if (!mounted || _activeRideDetails == null) return;

    final status = _activeRideDetails!.status;
    List<gmf.LatLng> basePathPoints;
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

    List<gmf.LatLng> remainingPath = [driverCurrentLocation, ...basePathPoints.sublist(closestPointIndex)];
    // You might want to log the closest point index and segment length here for debugging.
    //debugPrint("Dynamic Polyline Update - Closest Point Index: $closestPointIndex, Segment Length: ${remainingPath.length}");

    if (mounted) {
      setState(() {
      _activeRoutePolylines.clear(); // Clear previous dynamic polyline
      _activeRoutePolylines.add(gmf.Polyline(
        polylineId: gmf.PolylineId('dynamic_route_$polylineIdSuffix'),
        points: remainingPath,
        color: polylineColor,
        width: 6,
      ));
    });
    }
  }

  Future<void> _loadCustomMarker() async {
    try {
      _bodaIcon = await gmf.BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/boda_marker.png',
      );
      _kijiweIcon = await gmf.BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/home_kijiwe_marker.png',
      );
    } catch (e) { // This is correct
      debugPrint("Error loading custom marker: $e");
      // _bodaIcon will remain null, default marker will be used by _buildDriverMarker
    }
  }
  gmf.BitmapDescriptor? _kijiweIcon;
  

  Future<void> _initializeDriverStateAndLocation() async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);

    // Load persisted driver data first
    await driverProvider.loadDriverData();

    // After loading, check for Kijiwe ID and start listening
    if (driverProvider.currentKijiweId != null) {
      _listenToCurrentKijiwe(driverProvider.currentKijiweId!);
    }

    await locationProvider.updateLocation();
    if (locationProvider.currentLocation != null && _mapController != null) {
      _centerMapOnDriver();
    }
    _fetchDriverStats(); // Fetch stats after loading driver data
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!mounted) return SizedBox.shrink(); // Return an empty widget if not mounted

    final driverProvider = Provider.of<DriverProvider>(context);
    final locationProvider = Provider.of<LocationProvider>(context);
    final theme = Theme.of(context); // Get the current theme

    double bottomPadding = 0;
    if (_activeRideDetails != null) {
      bottomPadding = MediaQuery.of(context).size.height * _currentSheetSize;
    } else if (driverProvider.pendingRideRequestDetails != null) {
      // Use the measured height of the ride request sheet for padding
      bottomPadding = _rideRequestSheetHeight;
    }

    return Scaffold(
      body: Stack(
        children: [
          // Base Map (reusing similar logic from CustomerHome)
          gmf.GoogleMap(
            initialCameraPosition: gmf.CameraPosition(
              target: locationProvider.currentLocation is gmf.LatLng
                  ? locationProvider.currentLocation as gmf.LatLng
                  : const gmf.LatLng(0, 0), // Default if no location
              zoom: 17, // Keep zoom level
              bearing: 0, // Always keep North up
            ),
            onMapCreated: (gmf.GoogleMapController controller) {
              _mapController = controller;
              _centerMapOnDriver();
            },
            myLocationEnabled: false,
            zoomControlsEnabled: false, // Disable default zoom controls
            markers: _buildDriverMarker(locationProvider),
            onCameraMove: (position) {
              // _currentHeading = position.bearing; // This can cause jerky rotations, location provider heading is better
            },
            polylines: _activeRoutePolylines,
            padding: EdgeInsets.only(bottom: bottomPadding, top: MediaQuery.of(context).padding.top + 70),
          ),

          // Online Status Toggle / Card
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: _buildOnlineStatusWidget(),
          ),

          // Add this debug print
          // Positioned(top: 100, left: 10, child: Text("DEBUG: Active: ${_activeRideDetails?.id}, Pending: ${driverProvider.pendingRideRequestDetails?['rideRequestId']}", style: TextStyle(backgroundColor: Colors.yellow, color: Colors.black))),

          // Bottom Sheet for Ride Control
          // Add this debug print inside the build method, right before the sheet conditions
          // Text("DEBUG: isOnline: ${driverProvider.isOnline}, activeRideDetails: ${_activeRideDetails?.id}, pendingRideDetails: ${driverProvider.pendingRideRequestDetails?['rideRequestId']}, currentKijiweId: ${driverProvider.currentKijiweId}", style: TextStyle(backgroundColor: Colors.white)),
          if (driverProvider.isOnline && _activeRideDetails == null && driverProvider.pendingRideRequestDetails == null && driverProvider.currentKijiweId != null)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _buildIdleOnlineDriverView(context, driverProvider),
            ),
          if (_activeRideDetails != null) 
            _buildActiveRideSheet(), // Show if there's an active ride
          // This is the crucial condition for the accept/decline sheet
          if (driverProvider.isOnline &&
              driverProvider.pendingRideRequestDetails != null && // Data for the sheet exists
              _activeRideDetails == null) // And no other ride is active
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _buildRideRequestSheet(driverProvider.pendingRideRequestDetails!),
            ),

          // Custom Map Controls (Relocation and Zoom) - Placed last to be drawn on top
          Positioned(
            bottom: bottomPadding + 20, // Position above the sheet
            right: 16,
            child: Column(
              children: [
                // Relocation Button
                FloatingActionButton.small(
                  heroTag: 'recenter_button', // Unique heroTag
                  onPressed: _centerMapOnDriver,
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.onSurface,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 16),
                // Zoom Buttons
                FloatingActionButton.small(
                  heroTag: 'zoom_in_button',
                  onPressed: () => _mapController?.animateCamera(gmf.CameraUpdate.zoomIn()),
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.onSurface,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 2),
                FloatingActionButton.small(
                  heroTag: 'zoom_out_button',
                  onPressed: () => _mapController?.animateCamera(gmf.CameraUpdate.zoomOut()),
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.onSurface,
                  child: const Icon(Icons.remove),
                ),
              ],
            ),
          ),
          
        ],
      ),
    );
  }

  Widget _buildOnlineStatusWidget() {
  final driverProvider = Provider.of<DriverProvider>(context);
  
  return AnimatedSwitcher(
    key: ValueKey('online-status-switcher'), // Add a key for AnimatedSwitcher
    duration: Duration(milliseconds: 300),
    transitionBuilder: (child, animation) {
      return ScaleTransition(scale: animation, child: child);
    },
    child: driverProvider.isOnline
        ? _buildOnlineCardWithToggle(driverProvider)
        : _buildOfflineButton(driverProvider),
  );
}

  Future<void> _fetchDriverStats() async {
    final firestoreService = FirestoreService();
    final userId = AuthService().currentUser?.uid; // Use AuthService to get current user ID
    if (userId != null) {
      _dailyEarnings = await firestoreService.getDriverDailyEarnings(userId);
    }
  }  
  Widget _buildOnlineCardWithToggle(DriverProvider driverProvider) {
  final theme = Theme.of(context); // Define theme here
  return SizedBox(
    width: 117, // Square width
    height: 128, // Square height
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
                  Text(AppLocale.online.getString(context), 
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: successColor, // successColor is defined in ui_utils.dart
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    _buildToggleButton(driverProvider),
                ],
              ),
              Padding( // Add padding to ensure it doesn't overlap with the button
                padding: const EdgeInsets.only(bottom: 4.0), // Adjust as needed
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center, // Center text in column
                  children: [
                    Text('⭐ ${(driverProvider.driverProfileData?['averageRating'] as num?)?.toStringAsFixed(1) ?? AppLocale.not_applicable.getString(context)}', // Display actual rating
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    verticalSpaceSmall, // Use spacing constant
                    Text('TZS ${driverProvider.dailyEarnings.toStringAsFixed(0)} ${AppLocale.today.getString(context)}', // Display actual earnings
                      style: theme.textTheme.bodySmall?.copyWith( // You missed the theme in previous edits
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
    onPressed: _toggleOnlineStatus,
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
    onPressed: _toggleOnlineStatus,
  );
}

  Widget _buildActiveRideSheet() {
    final isAtPickup = _activeRideDetails?.status == 'arrivedAtPickup'; // Corrected status
    final isRideInProgress = _activeRideDetails?.status == 'onRide';
    final theme = Theme.of(context);
    final isGoingToPickup = _activeRideDetails?.status == 'accepted' || _activeRideDetails?.status == 'goingToPickup';

    final String customerName = _activeRideDetails?.customerName ?? AppLocale.customer.getString(context);
    final String pickupAddress = _activeRideDetails?.pickupAddressName ?? AppLocale.pickup_location.getString(context);
    final String dropoffAddress = _activeRideDetails?.dropoffAddressName ?? AppLocale.destination_location.getString(context);
    final bool pickupStepCompleted = isAtPickup || isRideInProgress;
    final bool canNavigate = isGoingToPickup || isRideInProgress || isAtPickup; 
    final bool mainRideStarted = isRideInProgress;
    final List<Map<String, dynamic>> stops = _activeRideDetails?.stops ?? [];
    final String? imageUrl = _activeRideDetails?.customerProfileImageUrl;

    return DraggableScrollableSheet(
      controller: _sheetController,
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
                key: ValueKey('active-ride-handle'), // Add key
                width: 40,
                height: 4,
                margin: EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: theme.colorScheme.outline.withOpacity(0.5), borderRadius: BorderRadius.circular(2)),
              ),

              // Ride info
              ListTile(
                leading: CircleAvatar( // Use CircleAvatar for a nice circular image
                  key: const ValueKey('active-ride-customer-avatar'),
                  radius: 25, // Adjust size as needed
                  backgroundColor: theme.colorScheme.primaryContainer, // Fallback color
                  backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                      ? NetworkImage(imageUrl)
                      : null, // Use NetworkImage if URL exists
                  child: (imageUrl == null || imageUrl.isEmpty)
                      ? Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer)
                      : null, // Show icon only if no image
                ),
                title: Text(customerName, style: theme.textTheme.titleMedium),
                // Display customer details here
                subtitle: Text(
                  _activeRideDetails?.customerDetails ?? AppLocale.customer_details_not_available.getString(context),
                  style: theme.textTheme.bodySmall,
                ),
                // subtitle: Text('Status: ${_currentRide?['status'] ?? 'Unknown'}', style: theme.textTheme.bodySmall), // Status is shown in Chip below
              ),
              // Display Estimated Fare (if available and status is before start)
              if (_activeRideDetails?.fare == null && (_activeRideDetails?.status == 'accepted' || _activeRideDetails?.status == 'goingToPickup' || _activeRideDetails?.status == 'arrivedAtPickup'))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Text('${AppLocale.estimated_fare_prefix.getString(context)} TZS ${_activeRideDetails?.estimatedFare?.toStringAsFixed(0) ?? AppLocale.not_applicable.getString(context)}', // Display estimated fare from model
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                ),

              // Chat with Customer Button
              if (_activeRideDetails?.customerId != null && (_activeRideDetails?.status == 'accepted' || _activeRideDetails?.status == 'goingToPickup' || _activeRideDetails?.status == 'arrivedAtPickup' || _activeRideDetails?.status == 'onRide')) ...[
                verticalSpaceSmall,
                TextButton.icon(
                  icon: Icon(Icons.chat_bubble_outline, color: theme.colorScheme.primary, size: 20),
                  label: Text(AppLocale.chat_with_customer.getString(context), style: TextStyle(color: theme.colorScheme.primary)),
                  onPressed: () {
                    debugPrint("DriverHome: Chat button pressed for ride ID: ${_activeRideDetails!.id} with customer ID: ${_activeRideDetails!.customerId}");
                    Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(
                      rideRequestId: _activeRideDetails!.id,
                      recipientId: _activeRideDetails!.customerId,
                      recipientName: _activeRideDetails!.customerName ?? "Customer",
                    )));
                  },
                ),
              ],
              // Display Customer Note if available
              if (_activeRideDetails?.customerNoteToDriver != null && _activeRideDetails!.customerNoteToDriver!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), // Use spacing constants?
                child: Text("${AppLocale.note_from_customer_prefix.getString(context)} ${_activeRideDetails!.customerNoteToDriver}", style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.secondary)),
              ),

              // Display route to pickup or main ride information if available
              if ((_activeRideDetails?.status == 'accepted' && _driverToPickupDistance != null && _driverToPickupDuration != null) ||
                  ((_activeRideDetails?.status == 'arrivedAtPickup' || _activeRideDetails?.status == 'onRide') && _mainRideDistance != null && _mainRideDuration != null))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    _activeRideDetails?.status == 'accepted' || _activeRideDetails?.status == 'goingToPickup'
                        ? '${AppLocale.to_pickup_prefix.getString(context)} ${_driverToPickupDuration ?? AppLocale.calculating_dots.getString(context)} · ${_driverToPickupDistance ?? AppLocale.calculating_dots.getString(context)}' // Add null checks
                        : '${AppLocale.ride_prefix.getString(context)} $_mainRideDuration · $_mainRideDistance',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary),
                  ),
                ),

              if (_isLoadingRoute && _activeRideDetails?.status == 'accepted')
                Padding(padding: const EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator())),

              Divider(),

              // Ride progress
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column( // Use Column
                  children: [
                    _buildRideStep(
                        Icons.my_location, // Using getLegInfo(0) for consistency
                        '${AppLocale.pickup.getString(context)}: $pickupAddress ${(isGoingToPickup && getLegInfo(0) != null) ? "(${getLegInfo(0)})" : ""}',
                        pickupStepCompleted
                    ),
                    // Stops Steps
                    if (stops.isNotEmpty)
                      ...stops.asMap().entries.map((entry) {
                        final index = entry.key;
                        final stop = entry.value;
                        final stopAddress = stop['addressName'] as String? ?? '${AppLocale.stop_prefix_with_number.getString(context)} ${index + 1}'; // Cast for 'addressName' might still be needed depending on how 'stops' is populated upstream
                        // Leg 0 is Driver -> Pickup
                        // Leg 1 is Pickup -> Stop 1 (index 0 of stops list)
                        // So, leg for stops[index] is _proposedRouteLegsData[index + 1]
                        final String? legInfoToStop = getLegInfo(index + 1);
                        final String stopText = '${AppLocale.stop_prefix_with_number.getString(context)} ${index + 1}: $stopAddress ${(legInfoToStop != null) ? "($legInfoToStop)" : ""}';
                        return _buildRideStep(Icons.location_on, stopText, mainRideStarted);
                      }).toList(),
                    // Destination Step
                    _buildRideStep(Icons.flag, '${AppLocale.destination_prefix.getString(context)} $dropoffAddress ${(getLegInfo((_proposedRouteLegsData?.length ?? 0) - 1) != null) ? "(${getLegInfo((_proposedRouteLegsData?.length ?? 0) - 1)})" : ""}', false),
                  ],
                ),
              ),

              // Action buttons
              Padding(
                padding: EdgeInsets.all(16),
                child: Row( // Use Row
                  children: [
                    if (isGoingToPickup)
                      Expanded(
                        child: ElevatedButton(
                          style: theme.elevatedButtonTheme.style?.copyWith(
                            backgroundColor: MaterialStateProperty.all(successColor),
                            foregroundColor: MaterialStateProperty.all(theme.colorScheme.onPrimary),
                          ),
                          child: Text(AppLocale.arrived.getString(context)),
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
                          child: Text(AppLocale.start_ride.getString(context)),
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
                          child: Text(AppLocale.complete_ride.getString(context)),
                          onPressed: () {
                            final rideId = _activeRideDetails?.id;
                            if (rideId != null) {
                              _completeRide(context, rideId); // Pass context
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocale.error_ride_id_missing.getString(context))));
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
                  child: Text(AppLocale.cancelRide.getString(context)),
                ),
              ),
             ),
            ],
          ),
        ), // Removed the closing parenthesis for the SingleChildScrollView here
        );
      },
    );
  }

  Future<void> _showCancelRideConfirmationDialog() async {
    // This method is fine as is
    final theme = Theme.of(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(AppLocale.confirm_cancel_ride_title.getString(context), style: theme.textTheme.titleLarge),
          content: SingleChildScrollView(
            child: ListBody(children: <Widget>[Text(AppLocale.confirm_cancel_ride_content.getString(context), style: theme.textTheme.bodyMedium)]),
          ),
          actions: <Widget>[
            TextButton(child: Text(AppLocale.dialog_no.getString(context), style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))), onPressed: () => Navigator.of(dialogContext).pop()),
            TextButton(
              child: Text(AppLocale.dialog_yes_cancel.getString(context), style: TextStyle(color: theme.colorScheme.error)),
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
    final String rideRequestId = rideData['rideRequestId'] as String? ?? 'N/A'; // Corrected key
    final String customerId = rideData['customerId'] as String? ?? 'N/A'; // Corrected key
    final String? displayEstimatedFareText = rideData['estimatedFare'] as String?;

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

    final theme = Theme.of(context); // Moved theme here as it's used throughout

    final String toPickupLegInfo = getLegInfo(0) ?? AppLocale.calculating_dots.getString(context); // Leg 0: Driver to Customer Pickup

     return Card(
        key: _rideRequestSheetKey, // Assign the key to the Card
        elevation: 8,
        margin: EdgeInsets.zero, // Remove default card margin
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)), // Rounded top corners
        ),
        color: theme.colorScheme.surface,
        child: Padding(
          key: ValueKey('ride-request-sheet-padding'), // Add key
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  key: ValueKey('ride-request-customer-avatar'),
                  child: Icon(Icons.person, color: theme.colorScheme.onPrimaryContainer), // Add key
                ),
                title: Text(
                    (rideData['customerName'] as String?)?.isNotEmpty == true
                      ? AppLocale.ride_from_customer.getString(context).replaceFirst('{name}', rideData['customerName'])
                      : AppLocale.new_ride_request.getString(context)),
                subtitle: Text(
                    rideData['customerDetails'] ?? AppLocale.customer_details_not_available.getString(context),
                    style: theme.textTheme.bodySmall, // Ensure consistent styling
                  ),
              ),
              // Display Customer Note if available
              if (rideData['customerNoteToDriver'] != null && (rideData['customerNoteToDriver'] as String).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text("${AppLocale.note_from_customer_prefix.getString(context)} ${rideData['customerNoteToDriver']}",
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                ),

              // Countdown Timer
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Chip(
                  avatar: Icon(Icons.timer, color: theme.colorScheme.onSecondaryContainer),
                  label: Text(AppLocale.auto_decline_in.getString(context).replaceFirst('{seconds}', _countdownSeconds.toString()), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
                  backgroundColor: theme.colorScheme.secondaryContainer,
                ),
              ),
              // Main Ride Distance and Duration
              if (_mainRideDistance != null && _mainRideDuration != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.directions_car, color: theme.colorScheme.secondary, size: 18),
                      horizontalSpaceSmall,
                      Text(
                        '${AppLocale.ride_prefix.getString(context)} $_mainRideDuration · $_mainRideDistance',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              // Estimated Fare
              if (displayEstimatedFareText != null && displayEstimatedFareText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text('${AppLocale.estimated_fare_prefix.getString(context)} TZS ${double.tryParse(displayEstimatedFareText)?.toStringAsFixed(0) ?? displayEstimatedFareText}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                ),

              // To Pickup Leg Info - Displaying the toPickupLegInfo
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Text('${AppLocale.to_pickup_prefix.getString(context)} $toPickupLegInfo', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
              ),
              const Divider(indent: 16, endIndent: 16, height: 20),
              
              // Pickup Location
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Row(
                  children: [ // Use Row
                    Icon(Icons.my_location, color: successColor, size: 20),
                    horizontalSpaceSmall,
                    Expanded(
                      child: Text('${AppLocale.pickup.getString(context)}: ${rideData['pickupAddressName'] ?? AppLocale.customer_pickup.getString(context)}', style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),

              // Display Stops (if any)
              if (stopsToDisplay.isNotEmpty)
                ...stopsToDisplay.asMap().entries.map((entry) {
                  final index = entry.key;
                  final stopMap = entry.value;
                  final stopAddress = stopMap['addressName'] as String? ?? (stopMap['name'] as String? ?? AppLocale.stop_prefix_with_number.getString(context));
                  // Leg to this stop:
                  // Leg 0 is Driver -> Pickup
                  // Leg 1 is Pickup -> Stop 1 (index 0 of stopsToDisplay)
                  // So, leg for stopsToDisplay[index] is _proposedRouteLegsData[index + 1]
                  final String? legInfoToStop = getLegInfo(index + 1);

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, color: theme.colorScheme.secondary, size: 20),
                        horizontalSpaceSmall,
                        Expanded(
                          child: Text('${AppLocale.stop_prefix_with_number.getString(context)} ${index + 1}: $stopAddress', style: theme.textTheme.bodyMedium),
                        ),
                        if (legInfoToStop != null)
                          Text('($legInfoToStop)', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                      ],
                    ),
                  );
                }).toList(),

              // Destination
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.flag, color: theme.colorScheme.error, size: 20),
                    horizontalSpaceSmall,
                    Expanded(
                      child: Text('${AppLocale.destination_prefix.getString(context)} ${rideData['dropoffAddressName'] ?? AppLocale.final_destination.getString(context)}', style: theme.textTheme.bodyMedium),
                    ),
                    if (_proposedRouteLegsData != null && _proposedRouteLegsData!.isNotEmpty)
                      Text('(${getLegInfo(_proposedRouteLegsData!.length - 1) ?? ""})', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                  ],
                ),
              ),
              // Show loading indicator if the proposed route is being fetched for the sheet
              if (_isLoadingRoute && _activeRoutePolylines.isEmpty) // Show loading if route is being fetched for the sheet
                Padding(padding: const EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator())),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton( // Use OutlinedButton
                      child: Text(AppLocale.decline.getString(context), style: TextStyle(color: theme.colorScheme.error)),
                      onPressed: () => _declineRide(rideRequestId, customerId),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _acceptRide(rideRequestId, customerId, rideData['pickupLat'], rideData['pickupLng'], _pendingRideCustomerName),
                      child: Text(AppLocale.accept.getString(context), style: TextStyle(color: theme.colorScheme.onPrimary)), // Use ElevatedButton
                    ),
                  ),
                ],
              ),
            ],
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

  Set<gmf.Marker> _buildDriverMarker(LocationProvider locationProvider) {
    final Set<gmf.Marker> markers = {};

    // Add driver marker
    if (locationProvider.currentLocation != null && _isIconLoaded) {
      markers.add(gmf.Marker(
        markerId: const gmf.MarkerId('driver'),
        position: gmf.LatLng(
          locationProvider.currentLocation!.latitude,
          locationProvider.currentLocation!.longitude,
        ),
        icon: _bodaIcon ?? gmf.BitmapDescriptor.defaultMarker,
        rotation: _currentHeading ?? 0.0,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        zIndex: 1000,
      ));
    }

    // Add ride-specific markers (pickup, dropoff, stops)
    markers.addAll(_rideSpecificMarkers);

    // Add the current Kijiwe marker if it exists
    if (_currentKijiweMarker != null) {
      markers.add(_currentKijiweMarker!);
    }

    return markers;
  }
  Future<void> _centerMapOnDriver() async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false); // Listen: false is correct here
    if (locationProvider.currentLocation == null || _mapController == null) return;

    _mapController?.animateCamera(
      gmf.CameraUpdate.newCameraPosition(
        gmf.CameraPosition(
          target: gmf.LatLng(locationProvider.currentLocation!.latitude, locationProvider.currentLocation!.longitude),
          zoom: await _mapController!.getZoomLevel(), // Maintain current zoom
          bearing: 0, // Ensure North is always up when re-centering
        ),
      ),
    );
  }

  void _toggleOnlineStatus() async {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false); // This is fine, it's at the start
    final currentContext = context; // Capture context
    final scaffoldMessenger = ScaffoldMessenger.of(currentContext); // Capture ScaffoldMessengerState
    final bool isMounted = mounted; // Capture mounted state


    // Store the current online status before toggling to determine success message
    final bool wasOnline = driverProvider.isOnline;
    final String? errorMessage = await driverProvider.toggleOnlineStatus();

    if (errorMessage != null) {
      if (!isMounted) return; // Use captured mounted state
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    } else {
      // Success, UI already updated by provider's notifyListeners
      if (!isMounted) return; // Use captured mounted state
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(wasOnline ? AppLocale.you_are_now_offline.getString(context) : AppLocale.you_are_now_online.getString(context))),
      );
    }
  }

 // This method will be called by the listener
  void _updateDriverLocationAndMap(LocationProvider locationProvider) {
    if (!mounted) return; // Ensure widget is still mounted

    final newLocation = locationProvider.currentLocation;
    if (newLocation == null) return;

    final newLatLng = ll.LatLng(newLocation.latitude, newLocation.longitude); // Use latlong2 for calculations

    try {
      if (mounted) {
        setState(() {
        // Update driver marker position and heading
        _lastPosition = newLatLng;
        _currentHeading = locationProvider.heading;

        // --- Ride Tracking Logic ---
        if (_activeRideDetails?.status == 'onRide') {
          if (_rideTrackingStartTime == null) {
            _rideTrackingStartTime = DateTime.now();
            _rideTrackingLastLocation = newLatLng; // Start tracking from the first location update in 'onRide'
            _trackedDistanceKm = 0.0; // Reset distance
            _trackedDrivingDurationSeconds = 0; // Reset duration
          } else {
            // Calculate distance since last update
            if (_rideTrackingLastLocation != null) {
              final distanceBetweenUpdates = const ll.Distance().as(ll.LengthUnit.Kilometer, _rideTrackingLastLocation!, newLatLng);
              _trackedDistanceKm += distanceBetweenUpdates;
            }
            _rideTrackingLastLocation = newLatLng; // Update last location

            // Calculate elapsed time since start
            final elapsedDuration = DateTime.now().difference(_rideTrackingStartTime!);
            _trackedDrivingDurationSeconds = elapsedDuration.inSeconds;
          }
          // Update dynamic polyline based on new driver location
          _updateDynamicPolylineForProgress(gmf.LatLng(newLatLng.latitude, newLatLng.longitude)); // Pass google_maps_flutter.LatLng
        } else {
          // If not on ride, stop tracking
          _rideTrackingStartTime = null;
          _rideTrackingLastLocation = null;
          // _trackedDistanceKm and _trackedDrivingDurationSeconds are reset in _resetActiveRideState
        }
      });
      }

      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      // Only center map on driver if online AND not on an active or pending ride
      if (driverProvider.isOnline && _mapController != null && _lastPosition != null && _activeRideDetails == null && driverProvider.pendingRideRequestDetails == null) {
        _mapController?.animateCamera(
          gmf.CameraUpdate.newLatLng(gmf.LatLng(_lastPosition!.latitude, _lastPosition!.longitude)), // This is correct
        );
      }

      if (driverProvider.isOnline && _lastPosition != null) {
        driverProvider.updateDriverPosition(
          gmf.LatLng(_lastPosition!.latitude, _lastPosition!.longitude),
          _currentHeading,
        ).catchError((e) {
          // Catch errors from async operation updateDriverPosition (e.g., Firestore write failure)
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

    if (newRideRequestId == null || !mounted) { // Added !mounted check
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
      // If already displayed, ensure map is zoomed correctly to the full view // No longer needed, handled by initial fetch
      debugPrint("DriverHome: _initiateFullProposedRideRouteForSheet - Proposed route already displayed for ID: $newRideRequestId. Skipping fetch.");
      return;
    }


    final dynamic pickupLatDynamic = rideData['pickupLat'];
    final dynamic pickupLngDynamic = rideData['pickupLng'];
    final dynamic dropoffLatDynamic = rideData['dropoffLat'];
    debugPrint("DriverHome: _initiateFullProposedRideRouteForSheet - Starting route fetch for ID: $newRideRequestId");
    final dynamic dropoffLngDynamic = rideData['dropoffLng'];
    
    List<gmf.LatLng> customerStops = [];
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
                  return gmf.LatLng(lat, lng);
                }
              }
            }
          }
          return null; // Or throw an error for invalid stop format
        }).whereType<gmf.LatLng>().toList();
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

    final gmf.LatLng ridePickupLocation = gmf.LatLng(pLat, pLng);
    final gmf.LatLng rideDropoffLocation = gmf.LatLng(dLat, dLng);

    // Build waypoints list for the API: pickup first, then stops (if any)
    final List<gmf.LatLng> waypointsForApi = [ridePickupLocation, ...customerStops];

    // Get driver's current location (using google_maps_flutter.LatLng for API call)
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    if (locationProvider.currentLocation == null) {
      await locationProvider.updateLocation(); // Try to get location
      if (locationProvider.currentLocation == null) return; // Still not available
    }
    final gmf.LatLng driverCurrentLocation = gmf.LatLng(locationProvider.currentLocation!.latitude, locationProvider.currentLocation!.longitude); // This is correct

    // Use customerName directly from rideData if available
    final String? customerNameFromRideData = rideData['customerName'] as String?;
    if (customerNameFromRideData != null && customerNameFromRideData.isNotEmpty) {
      if (mounted && (_pendingRideCustomerName != customerNameFromRideData || newRideRequestId != _currentlyDisplayedProposedRideId)) {
        setState(() {
          _pendingRideCustomerName = customerNameFromRideData;
        });
      }
    }


    await _fetchAndDisplayRoute(
        origin: driverCurrentLocation, // Origin is now driver's current location
        destination: rideDropoffLocation, // Destination is customer's final drop-off
        waypoints: waypointsForApi.isNotEmpty ? waypointsForApi : null, // Corrected: All intermediate points are waypoints
        onRouteFetched: (distance, duration, points, legs) { // Added legs parameter
          if (!mounted) return; // Guard setState in callback
          if (mounted && points != null && points.isNotEmpty) {
            _proposedRouteLegsData = legs; // Store the legs data
            if (legs != null) {
              if (legs.isNotEmpty) {
                final leg0 = legs[0]; // Driver to Pickup
                _driverToPickupDistance = leg0['distance']?['text'] as String?;
                _driverToPickupDuration = leg0['duration']?['text'] as String?;
              }
              // Calculate main ride distance/duration by summing legs from index 1 onwards
              if (legs.length > 1) {
                double mainRideTotalDistanceMeters = 0;
                double mainRideTotalDurationSeconds = 0;
                for (int i = 1; i < legs.length; i++) {
                  mainRideTotalDistanceMeters += (legs[i]['distance']?['value'] as num?) ?? 0;
                  mainRideTotalDurationSeconds += (legs[i]['duration']?['value'] as num?) ?? 0;
                }
                _mainRideDistance = "${(mainRideTotalDistanceMeters / 1000).toStringAsFixed(1)} km";
                _mainRideDuration = "${(mainRideTotalDurationSeconds / 60).round()} min";
              }
            }
            if (mounted) {
              setState(() {
              // These now represent the ENTIRE journey from driver to customer's final destination
              _proposedRideDistance = distance;
              _proposedRideDuration = duration;
              _entireActiveRidePoints = points;
              _activeRoutePolylines.clear();
              _activeRoutePolylines.add(gmf.Polyline(polylineId: const gmf.PolylineId('full_initial_route'), points: _entireActiveRidePoints, color: Colors.deepPurpleAccent, width: 6));

              // Segment the points for later use: Driver -> Pickup, and Pickup -> Destination (with stops)
              int pickupIndexInEntireRoute = MapUtils.findClosestPointIndex(ridePickupLocation, _entireActiveRidePoints);
              if (pickupIndexInEntireRoute != -1) {
                _driverToPickupRoutePoints = _entireActiveRidePoints.sublist(0, pickupIndexInEntireRoute + 1);
                // The segment from pickup to destination (including stops)
                _fullProposedRoutePoints = _entireActiveRidePoints.sublist(pickupIndexInEntireRoute);
              } else {
                _driverToPickupRoutePoints = [];
                _fullProposedRoutePoints = List.from(_entireActiveRidePoints); // Fallback
              }

              // Draw two polylines for the proposed route view
              // Clear existing polylines first
              _activeRoutePolylines.clear();
              // Add polyline from driver to pickup
              if (_driverToPickupRoutePoints.isNotEmpty) {
                _activeRoutePolylines.add(gmf.Polyline(polylineId: const gmf.PolylineId('proposed_driver_to_pickup'), points: _driverToPickupRoutePoints, color: Colors.blueAccent, width: 6));
              }
              // Add polyline from pickup to destination (including stops)
              if (_fullProposedRoutePoints.isNotEmpty) {
                _activeRoutePolylines.add(gmf.Polyline(polylineId: const gmf.PolylineId('proposed_customer_journey'), points: _fullProposedRoutePoints, color: Colors.deepPurpleAccent, width: 6));
              }
              // Zoom to fit the entire initially proposed route
              final gmf.LatLngBounds? bounds = MapUtils.boundsFromLatLngList(_entireActiveRidePoints); // This is correct
              if (_mapController != null) _mapController!.animateCamera(gmf.CameraUpdate.newLatLngBounds(bounds!, 60)); // Fixed: use CameraUpdate instead of PolylineId
            });
            }
          }
        });

    if (mounted) {
      debugPrint("DriverHome: _initiateFullProposedRideRouteForSheet - Setting markers for proposed ride ID: $newRideRequestId");
      setState(() {
        _rideSpecificMarkers.clear(); // Clear any previous ride-specific markers
        _rideSpecificMarkers.add(gmf.Marker(
          markerId: gmf.MarkerId('proposed_pickup'),
          position: ridePickupLocation, // Customer's pickup
          infoWindow: gmf.InfoWindow(title: '${AppLocale.pickup.getString(context)}: ${rideData['pickupAddressName'] as String? ?? AppLocale.customer_pickup.getString(context)}'),
          icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueGreen),
        ));
        _rideSpecificMarkers.add(gmf.Marker(
          markerId: gmf.MarkerId('proposed_dropoff'),
          position: rideDropoffLocation,
          infoWindow: gmf.InfoWindow(title: '${AppLocale.destination.getString(context)}: ${rideData['dropoffAddressName'] ?? AppLocale.customer_destination.getString(context)}'),
          icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueRed),
        ));
        customerStops.asMap().forEach((index, stopLatLng) {
        _rideSpecificMarkers.add(gmf.Marker(
            markerId: gmf.MarkerId('proposed_stop_$index'),
            position: stopLatLng,
            infoWindow: gmf.InfoWindow(title: '${AppLocale.stop_prefix_with_number.getString(context)} ${index + 1}'), // You might need stop names from rideData
            icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueOrange),
          ));
        });
      });
    }
    // Update the ID of the currently displayed proposed route
    if (mounted && _activeRoutePolylines.isNotEmpty && !_isLoadingRoute) {
      // Set this regardless of whether markers were added, as long as polyline is there
      debugPrint("DriverHome: _initiateFullProposedRideRouteForSheet - Setting _currentlyDisplayedProposedRideId to: $newRideRequestId"); // This is correct
      _currentlyDisplayedProposedRideId = newRideRequestId;
    }
  }

  // Modified to use pre-fetched segment points and handle zoom/dynamic polyline.
  Future<void> _fetchAndDisplayRouteToPickup(BuildContext context, gmf.LatLng customerPickupLocation) async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    if (locationProvider.currentLocation == null || !mounted) return;
    final gmf.LatLng driverCurrentLocation = gmf.LatLng(locationProvider.currentLocation!.latitude, locationProvider.currentLocation!.longitude); // This is correct

    // Use the pre-calculated segment points
    if (mounted && _driverToPickupRoutePoints.isNotEmpty) {
      if (mounted) {
        setState(() {
        _activeRoutePolylines.clear();
        _activeRoutePolylines.add(gmf.Polyline(polylineId: const gmf.PolylineId('driver_to_pickup_active'), points: _driverToPickupRoutePoints, color: Colors.blueAccent, width: 6));
        // Distance and duration for this segment are not re-fetched here.
        // They could be calculated manually or parsed from the initial full route response if available.
      });
      }
      _zoomToDriverToPickupSegment(driverCurrentLocation, customerPickupLocation);
      _updateDynamicPolylineForProgress(driverCurrentLocation);
    } else {
       debugPrint("DriverHome: _driverToPickupRoutePoints is empty. Cannot display route to pickup.");
       // Fallback: Maybe zoom to driver and pickup location without polyline?
       _zoomToDriverToPickupSegment(driverCurrentLocation, customerPickupLocation);
    }

    // Add marker for customer's pickup when navigating to them
    if (mounted) {
      if (mounted) {
        setState(() { // Use setState to update markers
        _rideSpecificMarkers.clear(); // Clear previous proposed markers
        _rideSpecificMarkers.add(gmf.Marker(
          markerId: gmf.MarkerId('customer_pickup_active'),
          position: customerPickupLocation,
          infoWindow: gmf.InfoWindow(title: '${AppLocale.pickup.getString(context)}: ${_activeRideDetails?.pickupAddressName ?? AppLocale.customer_pickup.getString(context)}'),
          icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueGreen),
        ));
      });
      }
    }
  }

  // Fetches and displays route from CUSTOMER'S PICKUP to CUSTOMER'S DESTINATION (Main Ride)
  // Modified to use pre-fetched segment points and handle zoom/dynamic polyline.
  Future<void> _fetchAndDisplayMainRideRoute(gmf.LatLng ridePickup, gmf.LatLng rideDropoff, List<gmf.LatLng> stops) async {
    if (!mounted) return;

    // Fetch the route specifically from customer pickup to destination to get the correct legs.
    await _fetchAndDisplayRoute(
      origin: ridePickup,
      destination: rideDropoff,
      waypoints: stops.isNotEmpty ? stops : null,
      onRouteFetched: (distance, duration, points, legs) {
        if (!mounted) return;
        setState(() {
          _proposedRouteLegsData = legs; // Update legs data for the customer's journey
          _mainRideDistance = distance;
          _mainRideDuration = duration;
          _activeRoutePolylines.clear();
          if (points != null && points.isNotEmpty) {
            _activeRoutePolylines.add(gmf.Polyline(polylineId: const gmf.PolylineId('main_ride_active'), points: points, color: Colors.greenAccent, width: 6));
          }
        });
        _zoomToMainRideSegment(ridePickup, rideDropoff, stops);
        _updateDynamicPolylineForProgress(ridePickup); // Start dynamic polyline from pickup
      },
    );

    // Add markers for main ride (pickup, destination, stops)
    if (mounted) {
      if (mounted) {
        setState(() { // Use setState to update markers
        _rideSpecificMarkers.clear();
        _rideSpecificMarkers.add(gmf.Marker(
          markerId: gmf.MarkerId('main_ride_pickup'),
          position: ridePickup,
          infoWindow: gmf.InfoWindow(title: AppLocale.ride_pickup.getString(context)),
          icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueGreen),
        ));
        _rideSpecificMarkers.add(gmf.Marker(
          markerId: gmf.MarkerId('main_ride_destination'),
          position: rideDropoff,
          infoWindow: gmf.InfoWindow(title: AppLocale.ride_destination.getString(context)),
          icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueRed),
        ));
        stops.asMap().forEach((index, stopLatLng) {
          _rideSpecificMarkers.add(gmf.Marker(
            markerId: gmf.MarkerId('main_ride_stop_$index'),
            position: stopLatLng,
            infoWindow: gmf.InfoWindow(title: '${AppLocale.stop_prefix_with_number.getString(context)} ${index + 1}'),
            icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueOrange),
          ));
        });
      });
      }
    }
  }

  // Generic method to fetch and display a route
  Future<void> _fetchAndDisplayRoute({
    required gmf.LatLng origin,
    required gmf.LatLng destination,
    List<gmf.LatLng>? waypoints,
    required Function(String? distance, String? duration, List<gmf.LatLng>? points, List<Map<String, dynamic>>? legs) onRouteFetched,
  }) async {
    if (origin.latitude == destination.latitude && origin.longitude == destination.longitude && (waypoints == null || waypoints.isEmpty)) {
      debugPrint("DriverHome: Origin and Destination are the same, and no waypoints. Skipping route draw.");
      if (mounted) setState(() => _isLoadingRoute = false);
      if (!mounted) return; // Check before calling callback
      onRouteFetched(null, null, null, null); // Call with nulls as no route is drawn
      return;
    }

    if (!mounted) return;
    if (mounted) {
      setState(() {
      _isLoadingRoute = true;
      // _activeRoutePolylines.clear(); // Let the caller manage clearing polylines
      // _rideSpecificMarkers are managed by the calling functions like _initiateFullProposedRideRouteForSheet, _fetchAndDisplayRouteToPickup, etc.
      // Clear all specific route details before fetching a new one
      _proposedRouteLegsData = null; // Clear previous legs data
      _proposedRideDistance = null; _proposedRideDuration = null;
      _driverToPickupDistance = null; _driverToPickupDuration = null;
      _mainRideDistance = null; _mainRideDuration = null;
    });
    }

    try {
      final List<Map<String, dynamic>>? routeDetailsList = await MapUtils.getRouteDetails(
        origin: origin,
        destination: destination, // This is correct
        waypoints: waypoints,
        apiKey: _googlePlacesApiKey,
      );

      // Add this debug log to inspect the structure of routeDetailsList
      // debugPrint("DriverHome: _fetchAndDisplayRoute - Raw routeDetailsList from MapUtils: ${jsonEncode(routeDetailsList)}");
      // if (routeDetailsList != null && routeDetailsList.isNotEmpty) {
      //   debugPrint("DriverHome: _fetchAndDisplayRoute - First route's legs type: ${routeDetailsList.first['legs'].runtimeType}");
      //   debugPrint("DriverHome: _fetchAndDisplayRoute - First route's legs content: ${jsonEncode(routeDetailsList.first['legs'])}");
      // }


      if (!mounted) return;
      if (routeDetailsList != null && routeDetailsList.isNotEmpty) {
        final Map<String, dynamic> primaryRouteDetails = routeDetailsList.first;
        // Call the onRouteFetched callback with the data.
        // The caller will handle setState, polyline creation, and zooming.
        onRouteFetched(
          primaryRouteDetails['distance'] as String?,
          primaryRouteDetails['duration'] as String?,
          primaryRouteDetails['points'] as List<gmf.LatLng>?, // Assuming 'points' is List<gmf.LatLng>
          (primaryRouteDetails['legs'] as List<dynamic>?)
              ?.map((leg) => leg as Map<String, dynamic>)
              .toList() // Safely cast each leg
        );
        // No need to check mounted again here as onRouteFetched should handle it
      } else {
        // No route details found
        // isLoadingRoute will be set to false in the finally block.
        if (!mounted) return;
        onRouteFetched(null, null, null, null); // Call with nulls as no route is drawn
      }
    } catch (e) {
      debugPrint('Error in _fetchAndDisplayRoute: $e'); // This is correct
      if (!mounted) return; // Check before calling callback
      onRouteFetched(null, null, null, null); // Call with nulls as no route is drawn
    } finally {
      if (mounted) {
        setState(() { _isLoadingRoute = false; });
      }
    }
  }

  void _zoomToDriverToPickupSegment(gmf.LatLng driverLocation, gmf.LatLng customerPickup) {
    if (_mapController == null) return;
    final bounds = MapUtils.boundsFromLatLngList([driverLocation, customerPickup]); // This is correct
    _mapController!.animateCamera(gmf.CameraUpdate.newLatLngBounds(bounds, 60));
  }

  void _zoomToMainRideSegment(gmf.LatLng customerPickup, gmf.LatLng customerDestination, List<gmf.LatLng>? stops) { // This is correct
    if (_mapController == null) return;
    List<gmf.LatLng> pointsForBounds = [customerPickup, customerDestination];
    if (stops != null && stops.isNotEmpty) {
      pointsForBounds.addAll(stops);
    }
    final bounds = MapUtils.boundsFromLatLngList(pointsForBounds);
    _mapController!.animateCamera(gmf.CameraUpdate.newLatLngBounds(bounds, 60));
  }

  void _clearAllRouteData() {
    _activeRoutePolylines.clear();
    _fullProposedRoutePoints.clear();
    _driverToPickupRoutePoints.clear();
    _rideTrackingLastLocation = null;
    _trackedDistanceKm = 0.0;
    _trackedDrivingDurationSeconds = 0;
  }
   void _acceptRide(String rideId, String customerId, dynamic pickupLatRaw, dynamic pickupLngRaw, String? customerName) async {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    _cancelDeclineTimer(); // Stop the auto-decline timer
    debugPrint("DriverHome: _acceptRide called for ride ID: $rideId");
    final currentContext = context; // Capture context
    final scaffoldMessenger = ScaffoldMessenger.of(currentContext); // Capture ScaffoldMessengerState
    final bool isMounted = mounted; // Capture mounted state
    try {
      final pendingDetails = driverProvider.pendingRideRequestDetails;
      final String? pickupAddressName = pendingDetails?['pickupAddressName'] as String?;
      final String? dropoffAddressName = pendingDetails?['dropoffAddressName'] as String?;
      final dynamic dropoffLatRaw = pendingDetails?['dropoffLat'];
      final dynamic dropoffLngRaw = pendingDetails?['dropoffLng'];

      await driverProvider.acceptRideRequest(currentContext, rideId, customerId);

      if (!isMounted) return;
      debugPrint("DriverHome: _acceptRide - Ride accepted in provider. Updating local state.");
      if (isMounted) {
        setState(() {
        _rideRequestSheetHeight = 0.0; // Clear the request sheet height
        // Create a basic RideRequestModel instance.
        _currentSheetSize = 0.3; // Set initial sheet size for padding
        // The full details will come from the Firestore stream.
        _activeRideDetails = RideRequestModel(
          id: rideId,
          customerId: customerId,
          status: 'accepted', // Initial status after acceptance
          customerName: customerName ?? AppLocale.customer.getString(context),
          pickup: gmf.LatLng(double.parse(pickupLatRaw.toString()), double.parse(pickupLngRaw.toString())),
          dropoff: gmf.LatLng(double.parse(dropoffLatRaw.toString()), double.parse(dropoffLngRaw.toString())),
          pickupAddressName: pickupAddressName ?? AppLocale.pickup_location.getString(context),
          dropoffAddressName: dropoffAddressName ?? AppLocale.destination_location.getString(context),
          stops: [], // Initialize with empty stops, will be populated by stream if they exist
          // Other fields will be null or default initially
        );
        _activeRoutePolylines.clear(); // Clear proposed full route polyline
        _rideSpecificMarkers.clear(); // Clear proposed full route markers
      });
      }

      // Start listening to the active ride document
      _listenToActiveRide(rideId);
      
      // After setting state, call _fetchAndDisplayRouteToPickup which will handle zoom and initial dynamic polyline
      if (pickupLatRaw != null && pickupLngRaw != null) {
        final gmf.LatLng customerPickupLoc = gmf.LatLng(double.parse(pickupLatRaw.toString()), double.parse(pickupLngRaw.toString()));
        await _fetchAndDisplayRouteToPickup(currentContext, customerPickupLoc);
        if (!isMounted) return; // Check after await
      }
      debugPrint("DriverHome: _acceptRide - UI state updated, snackbar shown.");
      // Ensure context is still valid before showing SnackBar
      if (isMounted) {
        scaffoldMessenger.showSnackBar(SnackBar(content: Text(AppLocale.ride_accepted.getString(context))), // Use captured scaffoldMessenger
        );
      }
    } catch (e) {
      if (isMounted) {
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('${AppLocale.failed_to_accept_ride.getString(context)}: ${e.toString()}')), // Use captured variables
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
    _activeRideSubscription = firestoreService.getRideRequestDocumentStream(rideId).listen( // Listen to the specific ride document
      (DocumentSnapshot rideSnapshot) {
        if (mounted && rideSnapshot.exists && rideSnapshot.data() != null) {
          final newRideDetails = RideRequestModel.fromJson(rideSnapshot.data() as Map<String, dynamic>, rideSnapshot.id);
          debugPrint("DriverHome: _listenToActiveRide - Received update for ride ID: ${newRideDetails.id}, Status: ${newRideDetails.status}");
          if (mounted) {
            setState(() {
            if (_activeRideDetails == null) { // If this is the first time we're seeing this active ride
              _currentSheetSize = 0.3; // Set initial sheet size for padding
            }
            _activeRideDetails = newRideDetails;
            // Potentially update map/route based on new status if needed here,
            // though specific actions like _confirmArrival already handle this.
            if (newRideDetails.status == 'completed' ||
                newRideDetails.status == 'cancelled_by_customer' ||
                newRideDetails.status == 'cancelled_by_driver') {
              debugPrint("DriverHome: _listenToActiveRide - Ride ${newRideDetails.id} ended. Resetting active ride state.");
              _resetActiveRideState();
            }
            // React to status changes to update map/route display
            if (newRideDetails.status == 'arrivedAtPickup') {
              final gmf.LatLng? pickup = newRideDetails.pickup;
              final gmf.LatLng? dropoff = newRideDetails.dropoff;
              final List<gmf.LatLng> stops = newRideDetails.stops.map((s) => s['location'] as gmf.LatLng).toList();
              if (pickup != null && dropoff != null) _fetchAndDisplayMainRideRoute(pickup, dropoff, stops);
            }
          });
          }
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
    _cancelDeclineTimer(); // Stop the auto-decline timer
    debugPrint("DriverHome: _declineRide called for ride ID: $rideId");
    final currentContext = context; // Capture context
    final scaffoldMessenger = ScaffoldMessenger.of(currentContext); // Capture ScaffoldMessengerState
    final bool isMounted = mounted; // Capture mounted state
    try {
      await driverProvider.declineRideRequest(currentContext, rideId, customerId);
      if (!isMounted) return;
      debugPrint("DriverHome: _declineRide - Ride declined in provider. Clearing local proposed ride state."); // This is correct
      _rideRequestSheetHeight = 0.0; // Clear the request sheet height
      if (isMounted) {
        setState(() {
        _proposedRideDistance = null; _proposedRideDuration = null; // This is correct
        _pendingRideCustomerName = null; // Clear customer name for sheet
      });
      }
      if (isMounted) {
        scaffoldMessenger.showSnackBar(SnackBar(content: Text(AppLocale.ride_declined.getString(context))),
      );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppLocale.error_declining_ride.getString(context)}: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _navigateToNextPoint() async {
    if (_activeRideDetails == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocale.no_active_ride.getString(context))));
      return;
    }

    final String status = _activeRideDetails!.status;
    gmf.LatLng? destinationLatLng;
    String destinationName = AppLocale.next_destination.getString(context);

    if (status == 'accepted' || status == 'goingToPickup') {
      destinationLatLng = _activeRideDetails!.pickup;
      destinationName = _activeRideDetails!.pickupAddressName ?? AppLocale.pickup.getString(context);
    } else if (status == 'onRide' || status == 'arrivedAtPickup') { // 'arrivedAtPickup' implies next point is start of main ride or first stop
      final List<Map<String, dynamic>> stops = _activeRideDetails!.stops;
      // For simplicity, we'll assume stops are ordered and we navigate to the first one if not yet "completed"
      // A more robust solution would track completed stops.
      if (stops.isNotEmpty) {
        // Find the first "unvisited" stop. This is a simplified logic.
        final firstStop = stops.first; // Assuming stops are ordered
        destinationLatLng = firstStop['location'] as gmf.LatLng?;
        destinationName = firstStop['addressName'] as String? ?? AppLocale.next_stop.getString(context);
      }

      // If no stops or all stops visited, navigate to final destination
      if (destinationLatLng == null) {
        destinationLatLng = _activeRideDetails!.dropoff;
        destinationName = _activeRideDetails!.dropoffAddressName ?? AppLocale.final_destination.getString(context);
      }
    }

    if (destinationLatLng != null) {
      final uri = Uri.parse('google.navigation:q=${destinationLatLng.latitude},${destinationLatLng.longitude}&mode=d');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppLocale.could_not_launch_navigation.getString(context)} $destinationName')));
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocale.next_destination_not_available.getString(context))));
    }
  }

  void _confirmArrival(BuildContext context) async {
    final details = _getCurrentRideDetails();
    final rideId = details['rideId'];
    final customerId = details['customerId'];
    final currentContext = context; // Capture context
    final scaffoldMessenger = ScaffoldMessenger.of(currentContext); // Capture ScaffoldMessengerState
    final bool isMounted = mounted; // Capture mounted state

    if (rideId == null || customerId == null) {
      if (isMounted) scaffoldMessenger.showSnackBar(SnackBar(content: Text(AppLocale.error_ride_details_missing_for_arrival.getString(context))));
      return;
    }
    debugPrint("DriverHome: _confirmArrival called for ride ID: $rideId");

    final driverProvider = Provider.of<DriverProvider>(currentContext, listen: false);
    try {
      if (!isMounted) return;
      await driverProvider.confirmArrival(currentContext, rideId, customerId);
      if (isMounted) {
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
      final gmf.LatLng? pickup = _activeRideDetails?.pickup;
      final gmf.LatLng? dropoff = _activeRideDetails?.dropoff;
      final List<gmf.LatLng> stops = _activeRideDetails?.stops.map((s) => s['location'] as gmf.LatLng).toList() ?? [];
      if (pickup != null && dropoff != null) {
        await _fetchAndDisplayMainRideRoute(pickup, dropoff, stops);
        _zoomToMainRideSegment(pickup, dropoff, stops);
      }
      }
    }
    } catch (e) {
      if (isMounted) { // Use captured mounted state
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('${AppLocale.failed_to_confirm_arrival.getString(context)}: ${e.toString()}')));
      }
    }
  }

  void _startRide(BuildContext context) async {
    final details = _getCurrentRideDetails();
    final rideId = details['rideId'];
    final customerId = details['customerId'];
    final currentContext = context; // Capture context
    final scaffoldMessenger = ScaffoldMessenger.of(currentContext); // Capture ScaffoldMessengerState
    final bool isMounted = mounted; // Capture mounted state

    if (rideId == null || customerId == null) {
      if (isMounted) scaffoldMessenger.showSnackBar(SnackBar(content: Text(AppLocale.error_ride_details_missing_for_start.getString(context))));
      return;
    }
    debugPrint("DriverHome: _startRide called for ride ID: $rideId");
    final driverProvider = Provider.of<DriverProvider>(currentContext, listen: false);
    try {
      if (!isMounted) return;
      await driverProvider.startRide(currentContext, rideId, customerId);
      if (isMounted) {
        setState(() {
        // _activeRideDetails will be updated by the stream listener
      });
      }
    } catch (e) {
      if (isMounted) { // Use captured mounted state
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('${AppLocale.failed_to_start_ride.getString(context)}: ${e.toString()}')));      }
    }
  }

  void _completeRide(BuildContext context, String rideId) async {
    final customerId = _activeRideDetails?.customerId;
    if (customerId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocale.error_customer_id_not_found.getString(context)))); // This one is fine, it's a guard
      return;
    }
    debugPrint("DriverHome: _completeRide called for ride ID: $rideId");
    final currentContext = context; // Capture context
    final scaffoldMessenger = ScaffoldMessenger.of(currentContext); // Capture ScaffoldMessengerState
    final bool isMounted = mounted; // Capture mounted state

    final driverProvider = Provider.of<DriverProvider>(currentContext, listen: false);
    try {
      if (!isMounted) {
        debugPrint("DriverHome: _completeRide - Widget not mounted, cannot proceed.");
        return;
      }
      debugPrint("COMPLETING RIDE: Passing actuals - Distance: $_trackedDistanceKm km, Duration: ${_trackedDrivingDurationSeconds / 60.0} min");
      // Pass the tracked data to the provider
      await driverProvider.completeRide(
        currentContext,
        rideId, 
        customerId,
        actualDistanceKm: _trackedDistanceKm, // Pass tracked distance
        actualDrivingDurationMinutes: _trackedDrivingDurationSeconds > 0 ? _trackedDrivingDurationSeconds / 60.0 : null, // Pass tracked duration in minutes, or null if not tracked
        // actualTotalWaitingTimeMinutes: _your_waiting_time_variable_if_any, // If you track waiting time
      );
      // UI update handled by stream listener or _resetActiveRideState.
      // We'll call _resetActiveRideState after attempting to show the dialog.

      if (!isMounted) return; // Use captured mounted state
      if (isMounted) scaffoldMessenger.showSnackBar(SnackBar(content: Text(AppLocale.ride_completed_successfully.getString(context))));

      // Capture details for the dialog BEFORE resetting state.
      // Schedule the dialog and state reset to occur after the current frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showRateCustomerDialog(rideId, customerId); // Don't pass the model, dialog will stream it
          _resetActiveRideState(); // Reset state after dialog is queued or shown
        }
      });
    } catch (e) {
      if (isMounted) {
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('${AppLocale.failed_to_complete_ride.getString(context)}: ${e.toString()}')));
      }
    }
  }

  void _resetActiveRideState() {
    _cancelDeclineTimer(); // Ensure timer is cancelled when a ride ends
    debugPrint("DriverHome: _resetActiveRideState - ENTERED.  Current _activeRideDetails = ${_activeRideDetails?.id}, Clear provider pending= ${Provider.of<DriverProvider>(context, listen: false).pendingRideRequestDetails}");
    if (mounted) {
      _rideRequestSheetHeight = 0.0; // Reset sheet height
      _currentSheetSize = 0.0; // Reset sheet size for padding
      debugPrint("DriverHome: _resetActiveRideState called.");
      if (mounted) {
        setState(() { // Use setState to trigger UI rebuild
        _activeRideDetails = null; // Clear active ride details
        _clearAllRouteData(); // This is correct
      });
      // Explicitly clear pending ride from provider when resetting active state
      Provider.of<DriverProvider>(context, listen: false).clearPendingRide();
      debugPrint("DriverHome: _resetActiveRideState - Resetting states and cleared provider pending.");
      }
    }
  }



    Future<void> _showRateCustomerDialog(String rideId, String customerId) async {
    // This method is fine as is
    double ratingValue = 0; // Renamed to avoid conflict with widget
    final theme = Theme.of(context);
    TextEditingController commentController = TextEditingController();

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog( // The AlertDialog itself
              title: Text(AppLocale.rate_customer.getString(context), style: theme.textTheme.titleLarge),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    Text(AppLocale.how_was_your_experience_with_customer.getString(context), style: theme.textTheme.bodyMedium),
                    // Display Final Fare here using a StreamBuilder
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('rideRequests').doc(rideId).snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data!.exists) {
                          final rideData = snapshot.data!.data() as Map<String, dynamic>?;
                          final fare = rideData?['fare'] as num?;
                          if (fare != null) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: Text('${AppLocale.final_fare_prefix.getString(context)} TZS ${fare.toStringAsFixed(0)}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                            );
                          }
                        }
                        return const SizedBox.shrink(); // Show nothing while loading or if no fare
                      },
                    ),
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
                      decoration: appInputDecoration(hintText: AppLocale.addCommentOptional.getString(context)), // Use appInputDecoration
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: Text(AppLocale.skip.getString(context), style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
                ElevatedButton( // Changed to ElevatedButton for primary action
                  child: Text(AppLocale.submit_rating.getString(context)),
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
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocale.rating_submitted.getString(context))));
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppLocale.failed_to_submit_rating.getString(context)}: $e')));
                        }
                      }
                    } else {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocale.please_select_star_rating.getString(context))));
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

  Future<void> _cancelRide() async {
    final details = _getCurrentRideDetails();
    final rideId = details['rideId'];
    final customerId = details['customerId'];

    final currentContext = context; // Capture context
    final scaffoldMessenger = ScaffoldMessenger.of(currentContext); // Capture ScaffoldMessengerState
    final bool isMounted = mounted; // Capture mounted state


    if (rideId == null || customerId == null) {
      if (isMounted) scaffoldMessenger.showSnackBar(SnackBar(content: Text(AppLocale.error_ride_details_missing_for_cancellation.getString(context))));
      return;
    }
    debugPrint("DriverHome: _cancelRide called for ride ID: $rideId");
    final driverProvider = Provider.of<DriverProvider>(currentContext, listen: false);
    try {
      if (!isMounted) return;
      await driverProvider.cancelRide(currentContext, rideId, customerId);
      _resetActiveRideState(); // UI update handled by stream listener or this reset
    } catch (e) {
      if (isMounted) {
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('${AppLocale.failed_to_cancel_ride.getString(context)}: ${e.toString()}')));
      }
    }
  }

  Widget _buildIdleOnlineDriverView(BuildContext context, DriverProvider driverProvider) {
    // This method is fine as is
    final theme = Theme.of(context);
    final firestoreService = FirestoreService(); // Assuming you have a way to access this
    final authService = AuthService(); // To get current driver's ID
    final String? currentDriverId = authService.currentUser?.uid;

    // Achievements from DriverProvider
    final achievements = driverProvider.driverProfileData;
    final completedRides = achievements?['completedRidesCount']?.toString() ?? '0';
    final averageRating = (achievements?['averageRating'] as num?)?.toStringAsFixed(1) ?? 'N/A';

    return Card(
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
              Text(AppLocale.waiting_for_ride.getString(context), style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary)),
              verticalSpaceSmall,
              if (driverProvider.currentKijiweId != null)
                StreamBuilder<DocumentSnapshot>(
                  stream: firestoreService.getKijiweQueueStream(driverProvider.currentKijiweId!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Row(children: [Text("${AppLocale.kijiwe_prefix.getString(context)} ", style: theme.textTheme.bodyMedium), CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary))]);
                    }
                    if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
                      return Text(AppLocale.kijiwe_not_found.getString(context), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error));
                    }
                    final kijiweData = snapshot.data!.data() as Map<String, dynamic>;
                    final kijiweName = kijiweData['name'] as String? ?? AppLocale.unnamed_kijiwe.getString(context);
                    final List<dynamic> queue = kijiweData['queue'] as List<dynamic>? ?? [];
                    final queuePosition = currentDriverId != null ? queue.indexOf(currentDriverId) : -1;
                    final positionText = queuePosition != -1 ? "${queuePosition + 1}/${queue.length}" : AppLocale.not_in_queue.getString(context);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${AppLocale.kijiwe_prefix.getString(context)} $kijiweName", style: theme.textTheme.titleMedium),
                        Text("${AppLocale.your_position_prefix.getString(context)} $positionText", style: theme.textTheme.bodyMedium),
                      ],
                    );
                  },
                )
              else
                Text(AppLocale.not_associated_with_kijiwe.getString(context), style: theme.textTheme.bodyMedium),
              
              verticalSpaceMedium,
              Text(AppLocale.your_stats.getString(context), style: theme.textTheme.titleMedium),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildStatItem(theme, Icons.motorcycle, AppLocale.rides.getString(context), completedRides),
                  _buildStatItem(theme, Icons.star, AppLocale.rating.getString(context), averageRating),
                  // Add more stats if needed
                ],
              ),
              verticalSpaceMedium,
              ElevatedButton.icon(
                icon: const Icon(Icons.add_road),
                label: Text(AppLocale.street_pickup.getString(context)),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: theme.colorScheme.secondary,
                  foregroundColor: theme.colorScheme.onSecondary,
                ),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ManualRideScreen())),
              ),
            ],
          ),
        ),
      );
  }

  Widget _buildStatItem(ThemeData theme, IconData icon, String label, String value) {
    // This method is fine as is
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

  void _listenToCurrentKijiwe(String kijiweId) {
    _kijiweSubscription?.cancel();
    final firestoreService = FirestoreService();
    _kijiweSubscription = firestoreService.getKijiweQueueStream(kijiweId).listen((doc) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        final position = data['position']?['geopoint'] as GeoPoint?;
        final name = data['name'] as String?;
        if (position != null && name != null && _kijiweIcon != null) {
          if (mounted) {
            setState(() {
              _currentKijiweMarker = gmf.Marker(
                markerId: const gmf.MarkerId('current_kijiwe'),
                position: gmf.LatLng(position.latitude, position.longitude),
                icon: _kijiweIcon!,
                infoWindow: gmf.InfoWindow(title: '${AppLocale.home_kijiwe_prefix.getString(context)} $name'),
                zIndex: 1,
              );
            });
          }
        }
      }
    });
  }
}
  
  