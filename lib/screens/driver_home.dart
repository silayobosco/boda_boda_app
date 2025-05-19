import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/driver_provider.dart';
import '../services/auth_service.dart';
import '../providers/location_provider.dart'; // Reuse from customer home

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
  bool _isIconLoaded = false; // New flag

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
            polylines: _buildRoutePolylines(),
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

          // Ride Request Notification (appears when a ride comes in)
          if (driverProvider.isOnline && !_hasActiveRide && _currentRide == null) _buildRideRequestSheet(), // Added check for _currentRide
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
    final isInProgress = _currentRide?['status'] == 'in_progress';
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
                title: Text('John D. ⭐ 4.8'),
                subtitle: Text('2 passengers • Cash'),
              ),

              Divider(),

              // Ride progress
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildRideStep(Icons.pin_drop, 'Pickup: 123 Main St', true),
                    _buildRideStep(Icons.flag, 'Destination: 456 Park Ave', false),
                  ],
                ),
              ),

              // Action buttons
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (!isAtPickup && !isInProgress) ...[
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                        child: Text('Arrived'),
                        onPressed: () => _confirmArrival(),
                      ),
                    ),
                  ],
                  if (isAtPickup) ...[
                    // At pickup state
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                        child: Text('Start Ride'),
                        onPressed: _startRide,
                      ),
                    ),
                  ],
                  if (isInProgress) ...[
                    // In progress state
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green),
                        child: const Text('Complete Ride'), // Ensure _currentRide and its rideId are not null
                        onPressed: () {
                          final rideId = _currentRide?['rideId'] as String?;
                          if (rideId != null) {
                            _completeRide(rideId);
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
            ],
          ),
        ),
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

  Widget _buildRideRequestSheet() {
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
                title: Text('New Ride Request'),
                subtitle: Text('2.3 km away • \$12.50 est.'),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      child: const Text('Decline'),
                      onPressed: () {
                        // TODO: Replace placeholders with actual rideId and customerId from the incoming ride request data.
                        // This data would typically be available when the ride request sheet is displayed.
                        // For example, if you have state variables _pendingRideId and _pendingCustomerId:
                        _declineRide('placeholder_ride_id', 'placeholder_customer_id');
                      },
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      child: const Text('Accept'),
                      onPressed: () {
                        // TODO: Replace placeholders with actual rideId and customerId from the incoming ride request data.
                        // This data would typically be available when the ride request sheet is displayed.
                        // For example, if you have state variables _pendingRideId and _pendingCustomerId:
                        _acceptRide('placeholder_ride_id', 'placeholder_customer_id');
                      },
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


  Set<Polyline> _buildRoutePolylines() {
    // Example implementation: Replace with actual route data
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: [
          LatLng(0.0, 0.0), // Replace with actual coordinates
          LatLng(0.1, 0.1),
        ],
        color: Colors.blue,
        width: 5,
      ),
    };
  }

  void _acceptRide(String rideId, String customerId) async {
  final driverProvider = Provider.of<DriverProvider>(context, listen: false);
  try {
    await driverProvider.acceptRideRequest(rideId, customerId);
    
    setState(() {
      _hasActiveRide = true;
      _currentRide = {
        'rideId': rideId,
        'customerId': customerId, // Store customerId
        'status': 'accepted', // This status should ideally be driven by provider/backend
        // TODO: Populate these with actual data from the ride request
        'pickup': 'Placeholder Pickup',
        'destination': 'Placeholder Destination',
        'fare': 0.0,
      };
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ride accepted successfully')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to accept ride: ${e.toString()}')),
    );
  }
}

void _declineRide(String rideId, String customerId) async {
  final driverProvider = Provider.of<DriverProvider>(context, listen: false);
  try {
    await driverProvider.declineRideRequest(rideId, customerId);
    
    // TODO: Clear pending ride request details from UI state if any
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

  // TODO: Get the actual pickup coordinates from _currentRide or a navigation service
  // For example, if _currentRide stores pickup LatLng:
  // final LatLng pickupLocation = _currentRide!['pickupCoordinates'] as LatLng;
  // Using placeholder coordinates for now.
  final pickupLat = _currentRide!['pickupLat'] ?? 0.0; // Example, replace with actual data
  final pickupLng = _currentRide!['pickupLng'] ?? 0.0; // Example, replace with actual data

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

void _confirmArrival() async {
  final details = _getCurrentRideDetails();
  final rideId = details['rideId'];
  final customerId = details['customerId'];

  if (rideId == null || customerId == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Ride details missing for arrival confirmation.')));
    return;
  }

  final driverProvider = Provider.of<DriverProvider>(context, listen: false);
  try {
    await driverProvider.confirmArrival(rideId, customerId);
    setState(() {
      _currentRide?['status'] = 'arrived';
    });
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to confirm arrival: ${e.toString()}')),
    );
  }
}

  void _startRide() async {
    final details = _getCurrentRideDetails();
    final rideId = details['rideId'];
    final customerId = details['customerId'];

    if (rideId == null || customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Ride details missing for starting ride.')));
      return;
    }
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    try {
      await driverProvider.startRide(rideId, customerId);
      setState(() {
        _currentRide?['status'] = 'in_progress';
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start ride: ${e.toString()}')),
      );
    }
  }

  void _completeRide(String rideId) async {
  // rideId is passed from the button, ensure customerId is available from _currentRide
  final customerId = _currentRide?['customerId'] as String?;

  if (customerId == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error: Customer ID not found for this ride.')));
    return;
  }

  final driverProvider = Provider.of<DriverProvider>(context, listen: false);

  try {
    await driverProvider.completeRide(rideId, customerId);
    setState(() {
      _hasActiveRide = false;
      _currentRide = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ride completed successfully')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to complete ride: $e')),
    );
  }
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
      await driverProvider.cancelRide(rideId, customerId);
      setState(() {
        _hasActiveRide = false;
        _currentRide = null;
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