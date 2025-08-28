import 'dart:async';
import 'dart:convert'; // Added for jsonDecode
import 'package:cloud_firestore/cloud_firestore.dart';

import 'manual_ride_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmf; // Hide LatLng to avoid conflict with latlong2
import 'package:provider/provider.dart';
import '../providers/driver_provider.dart';
import '../providers/location_provider.dart'; // Reuse from customer home
import '../services/firestore_service.dart'; // Import FirestoreService
import '../services/auth_service.dart'; // Import AuthService to get current user ID
import '../utils/ui_utils.dart'; // Import UI Utils for styles and spacing
import 'package:flutter_localization/flutter_localization.dart';
import '../localization/locales.dart';
import 'chat_screen.dart'; // Import ChatScreen
import '../viewmodels/driver_home_viewmodel.dart';

class DriverHome extends StatelessWidget {
  const DriverHome({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => DriverHomeViewModel(
        driverProvider: Provider.of<DriverProvider>(context, listen: false),
        locationProvider: Provider.of<LocationProvider>(context, listen: false),
        firestoreService: Provider.of<FirestoreService>(context, listen: false),
        authService: Provider.of<AuthService>(context, listen: false),
        context: context,
      ),
      child: const DriverHomeView(),
    );
  }
}

class DriverHomeView extends StatefulWidget {
  const DriverHomeView({super.key});

  @override
  _DriverHomeViewState createState() => _DriverHomeViewState();
}

class _DriverHomeViewState extends State<DriverHomeView> with AutomaticKeepAliveClientMixin {
  gmf.GoogleMapController? _mapController;
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  double _currentSheetSize = 0.0; // For map padding
  final GlobalKey _rideRequestSheetKey = GlobalKey();
  double _rideRequestSheetHeight = 0.0;

  late final DriverHomeViewModel _viewModel;

  @override
  bool get wantKeepAlive => true; // Add this to keep the state alive

  @override
  void initState() {
    super.initState();
    _viewModel = Provider.of<DriverHomeViewModel>(context, listen: false);
    _viewModel.onUiAction = _handleUiAction;
    _viewModel.initialize();
    _sheetController.addListener(_onSheetChanged);
  }

  void _handleUiAction(UiAction action) {
    if (!mounted) return;
    if (action.type == 'dialog' && action.message == 'show_rate_customer_dialog') {
      _showRateCustomerDialog(action.data!['rideId'], action.data!['customerId']);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action.message),
          backgroundColor: action.isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
    }
  }

void _onSheetChanged() {
  if (!mounted) return;
  // Only update the size if the active ride sheet is the one being shown
  if (_viewModel.activeRideDetails != null) {
    setState(() {
      _currentSheetSize = _sheetController.size;
    });
  }
}

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final driverProvider = Provider.of<DriverProvider>(context);
    final locationProvider = Provider.of<LocationProvider>(context);
    final viewModel = Provider.of<DriverHomeViewModel>(context);
    final theme = Theme.of(context); // Get the current theme

    double bottomPadding = 0;
    if (viewModel.activeRideDetails != null) {
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
              target: locationProvider.currentLocation != null
                  ? gmf.LatLng(locationProvider.currentLocation!.latitude, locationProvider.currentLocation!.longitude)
                  : const gmf.LatLng(0, 0),
              zoom: 17, // Keep zoom level
              bearing: 0, // Always keep North up
            ),
            onMapCreated: (gmf.GoogleMapController controller) {
              viewModel.mapController = controller;
              _mapController = controller; // Keep local ref for UI-only actions
              viewModel.centerMapOnDriver();
            },
            myLocationEnabled: false,
            zoomControlsEnabled: false, // Disable default zoom controls
            markers: viewModel.markers,
            polylines: viewModel.polylines,
            padding: EdgeInsets.only(bottom: bottomPadding, top: MediaQuery.of(context).padding.top + 70),
          ),

          // Online Status Toggle / Card
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: _buildOnlineStatusWidget(),
          ),

          // Bottom Sheet for Ride Control
          if (driverProvider.isOnline && viewModel.activeRideDetails == null && driverProvider.pendingRideRequestDetails == null && driverProvider.currentKijiweId != null)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: _buildIdleOnlineDriverView(context, driverProvider),
            ),
          if (viewModel.activeRideDetails != null)
            _buildActiveRideSheet(), // Show if there's an active ride
          // This is the crucial condition for the accept/decline sheet
          if (driverProvider.isOnline &&
              driverProvider.pendingRideRequestDetails != null &&
              viewModel.activeRideDetails == null)
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
                  heroTag: 'recenter_button',
                  onPressed: viewModel.centerMapOnDriver,
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
  Widget _buildOnlineCardWithToggle(DriverProvider driverProvider) {
  final theme = Theme.of(context); // Define theme here
  return SizedBox(
    width: 123, // Square width
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
    onPressed: _viewModel.toggleOnlineStatus,
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
    onPressed: _viewModel.toggleOnlineStatus,
  );
}

  Widget _buildActiveRideSheet() {
    final isAtPickup = _viewModel.activeRideDetails?.status == 'arrivedAtPickup';
    final isRideInProgress = _viewModel.activeRideDetails?.status == 'onRide';
    final theme = Theme.of(context);
    final isGoingToPickup = _viewModel.activeRideDetails?.status == 'accepted' || _viewModel.activeRideDetails?.status == 'goingToPickup';

    final String customerName = _viewModel.activeRideDetails?.customerName ?? AppLocale.customer.getString(context);
    final String pickupAddress = _viewModel.activeRideDetails?.pickupAddressName ?? AppLocale.pickup_location.getString(context);
    final String dropoffAddress = _viewModel.activeRideDetails?.dropoffAddressName ?? AppLocale.destination_location.getString(context);
    final bool pickupStepCompleted = isAtPickup || isRideInProgress;
    final bool canNavigate = isGoingToPickup || isRideInProgress || isAtPickup; 
    final bool mainRideStarted = isRideInProgress;
    final List<Map<String, dynamic>> stops = _viewModel.activeRideDetails?.stops ?? [];
    final String? imageUrl = _viewModel.activeRideDetails?.customerProfileImageUrl;

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
                    child: FloatingActionButton.small(heroTag: 'navigateSheetButton', onPressed: _viewModel.navigateToNextPoint, child: Icon(Icons.navigation)),
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
                  _viewModel.activeRideDetails?.customerDetails ?? AppLocale.customer_details_not_available.getString(context),
                  style: theme.textTheme.bodySmall,
                ),
                // subtitle: Text('Status: ${_currentRide?['status'] ?? 'Unknown'}', style: theme.textTheme.bodySmall), // Status is shown in Chip below
              ),
              // Display Estimated Fare (if available and status is before start)
              if (_viewModel.activeRideDetails?.fare == null && (_viewModel.activeRideDetails?.status == 'accepted' || _viewModel.activeRideDetails?.status == 'goingToPickup' || _viewModel.activeRideDetails?.status == 'arrivedAtPickup'))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Text('${AppLocale.estimated_fare_prefix.getString(context)} TZS ${_viewModel.activeRideDetails?.estimatedFare?.toStringAsFixed(0) ?? AppLocale.not_applicable.getString(context)}', // Display estimated fare from model
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                ),

              // Chat with Customer Button
              if (_viewModel.activeRideDetails?.customerId != null && (_viewModel.activeRideDetails?.status == 'accepted' || _viewModel.activeRideDetails?.status == 'goingToPickup' || _viewModel.activeRideDetails?.status == 'arrivedAtPickup' || _viewModel.activeRideDetails?.status == 'onRide')) ...[
                verticalSpaceSmall,
                TextButton.icon(
                  icon: Icon(Icons.chat_bubble_outline, color: theme.colorScheme.primary, size: 20),
                  label: Text(AppLocale.chat_with_customer.getString(context), style: TextStyle(color: theme.colorScheme.primary)),
                  onPressed: () {
                    debugPrint("DriverHome: Chat button pressed for ride ID: ${_viewModel.activeRideDetails!.id} with customer ID: ${_viewModel.activeRideDetails!.customerId}");
                    Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(
                      rideRequestId: _viewModel.activeRideDetails!.id,
                      recipientId: _viewModel.activeRideDetails!.customerId,
                      recipientName: _viewModel.activeRideDetails!.customerName ?? "Customer",
                    )));
                  },
                ),
              ],
              // Display Customer Note if available
              if (_viewModel.activeRideDetails?.customerNoteToDriver != null && _viewModel.activeRideDetails!.customerNoteToDriver!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), // Use spacing constants?
                child: Text("${AppLocale.note_from_customer_prefix.getString(context)} ${_viewModel.activeRideDetails!.customerNoteToDriver}", style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: theme.colorScheme.secondary)),
              ),

              // Display route to pickup or main ride information if available
              if ((_viewModel.activeRideDetails?.status == 'accepted' && _viewModel.driverToPickupDistance != null && _viewModel.driverToPickupDuration != null) ||
                  ((_viewModel.activeRideDetails?.status == 'arrivedAtPickup' || _viewModel.activeRideDetails?.status == 'onRide') && _viewModel.mainRideDistance != null && _viewModel.mainRideDuration != null))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    _viewModel.activeRideDetails?.status == 'accepted' || _viewModel.activeRideDetails?.status == 'goingToPickup'
                        ? '${AppLocale.to_pickup_prefix.getString(context)} ${_viewModel.driverToPickupDuration ?? AppLocale.calculating_dots.getString(context)} · ${_viewModel.driverToPickupDistance ?? AppLocale.calculating_dots.getString(context)}' // Add null checks
                        : '${AppLocale.ride_prefix.getString(context)} ${_viewModel.mainRideDistance} · ${_viewModel.mainRideDuration}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary),
                  ),
                ),

              if (_viewModel.isLoadingRoute && _viewModel.activeRideDetails?.status == 'accepted')
                Padding(padding: const EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator())),

              Divider(),

              // Ride progress
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column( // Use Column
                  children: [
                    _buildRideStep(
                        Icons.my_location,
                        '${AppLocale.pickup.getString(context)}: $pickupAddress ${(isGoingToPickup && _viewModel.getLegInfo(0) != null) ? "(${_viewModel.getLegInfo(0)})" : ""}',
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
                        final String? legInfoToStop = _viewModel.getLegInfo(index + 1);
                        final String stopText = '${AppLocale.stop_prefix_with_number.getString(context)} ${index + 1}: $stopAddress ${(legInfoToStop != null) ? "($legInfoToStop)" : ""}';
                        return _buildRideStep(Icons.location_on, stopText, mainRideStarted);
                      }).toList(),
                    // Destination Step
                    _buildRideStep(Icons.flag, '${AppLocale.destination_prefix.getString(context)} $dropoffAddress ${(_viewModel.getLegInfo((_viewModel.proposedRouteLegsData?.length ?? 0) - 1) != null) ? "(${_viewModel.getLegInfo((_viewModel.proposedRouteLegsData?.length ?? 0) - 1)})" : ""}', false),
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
                          onPressed: _viewModel.confirmArrival,
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
                          onPressed: _viewModel.startRide,
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
                          onPressed: _viewModel.completeRide,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            // Cancel Ride Button - visible if ride is active but not yet completed
            if (_viewModel.activeRideDetails != null && !isRideInProgress && _viewModel.activeRideDetails?.status != 'completed' && _viewModel.activeRideDetails?.status != 'cancelled_by_driver' && _viewModel.activeRideDetails?.status != 'cancelled_by_customer')
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
                _viewModel.cancelRide();
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
    final viewModel = Provider.of<DriverHomeViewModel>(context);
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

    final String toPickupLegInfo = viewModel.getLegInfo(0) ?? AppLocale.calculating_dots.getString(context); // Leg 0: Driver to Customer Pickup

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
                  label: Text(AppLocale.auto_decline_in.getString(context).replaceFirst('{seconds}', viewModel.countdownSeconds.toString()), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
                  backgroundColor: theme.colorScheme.secondaryContainer,
                ),
              ),
              // Main Ride Distance and Duration
              if (viewModel.mainRideDistance != null && viewModel.mainRideDuration != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.directions_car, color: theme.colorScheme.secondary, size: 18),
                      horizontalSpaceSmall,
                      Text(
                        '${AppLocale.ride_prefix.getString(context)} ${viewModel.mainRideDuration} · ${viewModel.mainRideDistance}',
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
                  final String? legInfoToStop = viewModel.getLegInfo(index + 1);

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
                    if (viewModel.proposedRouteLegsData != null && viewModel.proposedRouteLegsData!.isNotEmpty)
                      Text('(${viewModel.getLegInfo(viewModel.proposedRouteLegsData!.length - 1) ?? ""})', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
                  ],
                ),
              ),
              // Show loading indicator if the proposed route is being fetched for the sheet
              if (viewModel.isLoadingRoute && viewModel.polylines.isEmpty) // Show loading if route is being fetched for the sheet
                Padding(padding: const EdgeInsets.all(8.0), child: Center(child: CircularProgressIndicator())),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton( // Use OutlinedButton
                      child: Text(AppLocale.decline.getString(context), style: TextStyle(color: theme.colorScheme.error)),
                      onPressed: () => viewModel.declineRide(rideRequestId, customerId),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => viewModel.acceptRide(rideRequestId, customerId),
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
                      final comment = commentController.text.trim().isNotEmpty ? commentController.text.trim() : null;
                      Navigator.of(dialogContext).pop();
                      await _viewModel.rateCustomer(rideId, customerId, ratingValue, comment);
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

  @override
  void dispose() {
    _mapController?.dispose();
    _sheetController.removeListener(_onSheetChanged);
    _sheetController.dispose();
    // ViewModel is disposed by the provider
    _viewModel.onUiAction = null;
    super.dispose();
  }
}
  
  