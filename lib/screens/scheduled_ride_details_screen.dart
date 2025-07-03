import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmf;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/Ride_Request_Model.dart';
import '../providers/ride_request_provider.dart';
import '../utils/ui_utils.dart';
import '../utils/map_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ScheduledRideDetailsScreen extends StatefulWidget {
  final RideRequestModel initialRide;

  const ScheduledRideDetailsScreen({super.key, required this.initialRide});

  @override
  State<ScheduledRideDetailsScreen> createState() => _ScheduledRideDetailsScreenState();
}

class _ScheduledRideDetailsScreenState extends State<ScheduledRideDetailsScreen> {
  // Map and Route state
  gmf.GoogleMapController? _mapController;
  final Set<gmf.Marker> _markers = {};
  final Set<gmf.Polyline> _polylines = {};
  bool _isRouteLoading = true;
  String? _routeDistance;
  String? _routeDuration;
  double? _estimatedFare;
  Map<String, dynamic>? _fareConfig;
  final String _googlePlacesApiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchRouteAndFare();
      }
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _fetchFareConfig() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('appConfiguration').doc('fareSettings').get();
      if (mounted && doc.exists && doc.data() != null) {
        setState(() => _fareConfig = doc.data());
      }
    } catch (e) {
      debugPrint("Error fetching fare config: $e");
    }
  }

  void _calculateEstimatedFare() {
    if (!mounted || _fareConfig == null || _routeDistance == null || _routeDuration == null) {
      setState(() => _estimatedFare = null);
      return;
    }

    double distanceKm = 0;
    final distanceMatch = RegExp(r'([\d\.]+)').firstMatch(_routeDistance!);
    if (distanceMatch != null) {
      double numericValue = double.tryParse(distanceMatch.group(1) ?? '0') ?? 0;
      if (_routeDistance!.toLowerCase().contains("km")) {
        distanceKm = numericValue;
      } else if (_routeDistance!.toLowerCase().contains("m")) {
        distanceKm = numericValue / 1000.0;
      }
    }

    double durationMinutes = 0;
    final hourMatch = RegExp(r'(\d+)\s*hr').firstMatch(_routeDuration!);
    if (hourMatch != null) durationMinutes += (double.tryParse(hourMatch.group(1) ?? '0') ?? 0) * 60;
    final minMatch = RegExp(r'(\d+)\s*min').firstMatch(_routeDuration!);
    if (minMatch != null) durationMinutes += double.tryParse(minMatch.group(1) ?? '0') ?? 0;
    if (durationMinutes == 0 && _routeDuration!.contains("min")) {
      final simpleMinMatch = RegExp(r'([\d\.]+)').firstMatch(_routeDuration!);
      if (simpleMinMatch != null) durationMinutes = double.tryParse(simpleMinMatch.group(1) ?? '0') ?? 0;
    }

    final double baseFare = (_fareConfig!['startingFare'] as num?)?.toDouble() ?? 0.0;
    final double perKmRate = (_fareConfig!['farePerKilometer'] as num?)?.toDouble() ?? 0.0;
    final double perMinRate = (_fareConfig!['farePerMinuteDriving'] as num?)?.toDouble() ?? 0.0;
    final double minFare = (_fareConfig!['minimumFare'] as num?)?.toDouble() ?? 0.0;
    double calculatedFare = baseFare + (distanceKm * perKmRate) + (durationMinutes * perMinRate);
    calculatedFare = calculatedFare > minFare ? calculatedFare : minFare;
    final double roundingInc = (_fareConfig!['roundingIncrement'] as num?)?.toDouble() ?? 0.0;
    if (roundingInc > 0) {
      calculatedFare = (calculatedFare / roundingInc).ceil() * roundingInc;
    }

    setState(() => _estimatedFare = calculatedFare);
  }

  @override
  Widget build(BuildContext context) {
    final rideProvider = Provider.of<RideRequestProvider>(context, listen: false);

    return StreamBuilder<RideRequestModel?>(
      stream: rideProvider.getScheduledRideStream(widget.initialRide.id!),
      initialData: widget.initialRide,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(appBar: AppBar(), body: Center(child: Text("Error: ${snapshot.error}")));
        }
        if (!snapshot.hasData) {
          // This can happen if the ride is deleted while the user is on this screen.
          return Scaffold(
            appBar: AppBar(title: const Text("Ride Not Found")),
            body: const Center(child: Text("This scheduled ride no longer exists.")),
          );
        }

        final ride = snapshot.data!;
        return _buildDetailsScaffold(context, ride);
      },
    );
  }

  Future<void> _fetchRouteAndFare() async {
    if (!mounted) return;
    setState(() => _isRouteLoading = true);

    await _fetchFareConfig();

    final ride = widget.initialRide;

    final List<gmf.LatLng> waypoints = ride.stops.map((stop) {
      final loc = stop['location'];
      if (loc is gmf.LatLng) return loc;
      if (loc is GeoPoint) return gmf.LatLng(loc.latitude, loc.longitude);
      return const gmf.LatLng(0, 0);
    }).where((loc) => loc.latitude != 0).toList();

    final routes = await MapUtils.getRouteDetails(
      origin: ride.pickup,
      destination: ride.dropoff,
      waypoints: waypoints.isNotEmpty ? waypoints : null,
      apiKey: _googlePlacesApiKey,
    );

    if (!mounted) return;

    if (routes != null && routes.isNotEmpty) {
      final primaryRoute = routes.first;
      final points = primaryRoute['points'] as List<gmf.LatLng>;
      final distance = primaryRoute['distance'] as String?;
      final duration = primaryRoute['duration'] as String?;

      setState(() {
        _routeDistance = distance;
        _routeDuration = duration;
        _polylines.add(gmf.Polyline(polylineId: const gmf.PolylineId('scheduled_route'), points: points, color: Theme.of(context).colorScheme.primary, width: 5));
        _markers.add(gmf.Marker(markerId: const gmf.MarkerId('pickup'), position: ride.pickup, icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueGreen)));
        _markers.add(gmf.Marker(markerId: const gmf.MarkerId('dropoff'), position: ride.dropoff, icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueRed)));
        for (var i = 0; i < waypoints.length; i++) {
          _markers.add(gmf.Marker(markerId: gmf.MarkerId('stop_$i'), position: waypoints[i], icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueOrange)));
        }
        _calculateEstimatedFare();
      });

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _mapController != null) _mapController!.animateCamera(gmf.CameraUpdate.newLatLngBounds(MapUtils.boundsFromLatLngList(points), 60));
      });
    }

    setState(() => _isRouteLoading = false);
  }
  // Builds the main scaffold for the ride details screen
  // Displays the ride details, actions, and map with route
  Widget _buildDetailsScaffold(BuildContext context, RideRequestModel ride) {
    final theme = Theme.of(context);
    final rideProvider = Provider.of<RideRequestProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(ride.title ?? 'Scheduled Ride'),
        actions: [
          if (ride.isRecurring == true)
            // Action for recurring rides: Stop
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Stop Recurrence',
              onPressed: () => _showStopRecurrenceConfirmationDialog(context, ride.id!, rideProvider),
            )
          else ...[
            // Actions for single scheduled rides: Pause/Resume and Delete
            if (ride.status == 'scheduled' || ride.status == 'paused')
              IconButton(
                icon: Icon(ride.status == 'scheduled' ? Icons.pause_circle_outline : Icons.play_circle_outline),
                tooltip: ride.status == 'scheduled' ? 'Pause Ride' : 'Resume Ride',
                onPressed: () => ride.status == 'scheduled' ? rideProvider.pauseScheduledRide(ride.id!) : rideProvider.unpauseScheduledRide(ride.id!),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Cancel Ride',
              onPressed: () => _showCancelConfirmationDialog(context, ride.id!, rideProvider),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 250,
            child: Stack(
              children: [
                gmf.GoogleMap(
                  initialCameraPosition: gmf.CameraPosition(target: ride.pickup, zoom: 14),
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  markers: _markers,
                  polylines: _polylines,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                ),
                if (_isRouteLoading)
                  Container(
                    color: Colors.black.withOpacity(0.3),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(theme, 'Ride Summary'),
                  // Status Chip
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Chip(
                      label: Text('Status: ${ride.status.capitalize()}', style: TextStyle(color: ride.status == 'stopped' ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSecondaryContainer)),
                      backgroundColor: ride.status == 'paused' || ride.status == 'stopped' ? warningColor.withOpacity(0.3) : theme.colorScheme.secondaryContainer,
                      avatar: ride.status == 'paused' || ride.status == 'stopped' ? Icon(Icons.pause, color: theme.colorScheme.onSecondaryContainer) : null,
                    ),
                  ),
                  _buildDetailItem(theme, Icons.schedule, 'Scheduled Time', DateFormat('E, MMM d, yyyy hh:mm a').format(ride.scheduledDateTime!.toLocal())),
                  _buildDetailItem(theme, Icons.my_location, 'From', ride.pickupAddressName ?? 'N/A'),
                  if (ride.stops.isNotEmpty)
                    ...ride.stops.asMap().entries.map((entry) {
                      final index = entry.key;
                      final stop = entry.value;
                      return _buildDetailItem(theme, Icons.location_on_outlined, 'Stop ${index + 1}', stop['addressName'] ?? 'N/A');
                    }).toList(),
                  _buildDetailItem(theme, Icons.flag, 'To', ride.dropoffAddressName ?? 'N/A'),
                  // Route & Fare Details
                  if (_routeDistance != null && _routeDuration != null) ...[
                    verticalSpaceMedium,
                    _buildSectionHeader(theme, 'Route & Fare'),
                    _buildDetailItem(theme, Icons.directions_car, 'Estimated Duration', _routeDuration!),
                    _buildDetailItem(theme, Icons.route, 'Estimated Distance', _routeDistance!),
                    if (_estimatedFare != null)
                      _buildDetailItem(theme, Icons.payments_outlined, 'Estimated Fare', 'TZS ${_estimatedFare!.toStringAsFixed(0)}'),
                  ],
                  if (ride.isRecurring == true) ...[
                    verticalSpaceMedium,
                    _buildSectionHeader(theme, 'Recurrence'),
                    _buildDetailItem(theme, Icons.repeat, 'Frequency', ride.recurrenceType ?? 'N/A'),
                    if (ride.recurrenceDaysOfWeek != null && ride.recurrenceDaysOfWeek!.isNotEmpty)
                      _buildDetailItem(theme, Icons.calendar_view_week, 'Days', ride.recurrenceDaysOfWeek!.join(', ')),
                    if (ride.recurrenceEndDate != null)
                      _buildDetailItem(theme, Icons.event_busy, 'Ends On', DateFormat.yMMMd().format(ride.recurrenceEndDate!.toLocal())),
                  ],
                  if (ride.customerNoteToDriver != null && ride.customerNoteToDriver!.isNotEmpty) ...[
                    verticalSpaceMedium,
                    _buildSectionHeader(theme, 'Note to Driver'),
                    Text(ride.customerNoteToDriver!, style: theme.textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
                  ]
                ],
              ),
            ),
          ),
        ],
        ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Implement Edit functionality
          // This will be complex, likely opening a new screen or a large dialog
          // similar to the scheduling dialog in customer_home.dart
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Editing scheduled rides is coming soon!')));
        },
        icon: const Icon(Icons.edit),
        label: const Text('Edit Ride'),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }

  Widget _buildDetailItem(ThemeData theme, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.secondary, size: 20),
          horizontalSpaceMedium,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCancelConfirmationDialog(BuildContext context, String rideId, RideRequestProvider rideProvider) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Scheduled Ride'),
        content: const Text('Are you sure you want to permanently cancel this scheduled ride?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await rideProvider.deleteScheduledRide(rideId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scheduled ride cancelled.')),
          );
          Navigator.of(context).pop(); // Go back to the list screen
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to cancel ride: $e')),
          );
        }
      }
    }
  }
}

  Future<void> _showStopRecurrenceConfirmationDialog(BuildContext context, String rideId, RideRequestProvider rideProvider) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop Recurring Ride'),
        content: const Text('Are you sure you want to stop this ride from recurring? This will not affect any rides that have already been scheduled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Yes, Stop'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await rideProvider.stopScheduledRecurrence(rideId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recurring ride stopped.')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to stop ride: $e')));
        }
      }
    }
  }

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}