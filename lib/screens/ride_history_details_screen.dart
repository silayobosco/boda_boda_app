import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmf;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/Ride_Request_Model.dart';
import '../utils/ui_utils.dart';
import '../utils/map_utils.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';

class RideHistoryDetailsScreen extends StatefulWidget {
  final RideRequestModel ride;

  const RideHistoryDetailsScreen({super.key, required this.ride});

  @override
  State<RideHistoryDetailsScreen> createState() => _RideHistoryDetailsScreenState();
}

class _RideHistoryDetailsScreenState extends State<RideHistoryDetailsScreen> {
  gmf.GoogleMapController? _mapController;
  final Set<gmf.Marker> _markers = {};
  final Set<gmf.Polyline> _polylines = {};
  bool _isRouteLoading = true;
  final String _googlePlacesApiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchRouteAndSetupMap();
      }
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _fetchRouteAndSetupMap() async {
    if (!mounted) return;
    setState(() => _isRouteLoading = true);

    final ride = widget.ride;
    // Removed null checks for ride.pickup and ride.dropoff as they cannot be null

    final List<gmf.LatLng> waypoints = ride.stops.map((stop) => stop['location'] as gmf.LatLng).toList();

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

      setState(() {
        _polylines.add(gmf.Polyline(polylineId: const gmf.PolylineId('history_route'), points: points, color: Theme.of(context).colorScheme.primary, width: 5));
        _markers.add(gmf.Marker(markerId: const gmf.MarkerId('pickup'), position: ride.pickup, icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueGreen)));
        _markers.add(gmf.Marker(markerId: const gmf.MarkerId('dropoff'), position: ride.dropoff, icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueRed)));
        for (var i = 0; i < waypoints.length; i++) {
          _markers.add(gmf.Marker(markerId: gmf.MarkerId('stop_$i'), position: waypoints[i], icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueOrange)));
        }
      });

      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _mapController != null) _mapController!.animateCamera(gmf.CameraUpdate.newLatLngBounds(MapUtils.boundsFromLatLngList(points), 60));
      });
    }

    setState(() => _isRouteLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ride = widget.ride;
    final authService = Provider.of<AuthService>(context, listen: false);
    final isDriver = authService.currentUser?.uid == ride.driverId;

    return Scaffold(
      appBar: AppBar(
        title: Text('Ride on ${DateFormat.yMMMd().format(ride.requestTime!)}'),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 250,
            child: Stack(
              children: [
                gmf.GoogleMap(
                  initialCameraPosition: gmf.CameraPosition(target: ride.pickup, zoom: 14),
                  onMapCreated: (controller) => _mapController = controller,
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
                  _buildSectionHeader(theme, 'Trip Details'),
                  _buildDetailItem(theme, Icons.my_location, 'From', ride.pickupAddressName ?? 'N/A'),
                  if (ride.stops.isNotEmpty)
                    ...ride.stops.asMap().entries.map((entry) {
                      final index = entry.key;
                      final stop = entry.value;
                      return _buildDetailItem(theme, Icons.location_on_outlined, 'Stop ${index + 1}', stop['addressName'] ?? 'N/A');
                    }).toList(),
                  _buildDetailItem(theme, Icons.flag, 'To', ride.dropoffAddressName ?? 'N/A'),
                  _buildDetailItem(theme, Icons.schedule, 'Date', DateFormat('E, MMM d, yyyy hh:mm a').format(ride.completedTime ?? ride.requestTime!)),
                  _buildDetailItem(theme, Icons.info_outline, 'Status', ride.status.replaceAll('_', ' ').capitalize()),
                  verticalSpaceMedium,
                  _buildSectionHeader(theme, 'Fare Details'),
                  _buildDetailItem(theme, Icons.payments_outlined, 'Final Fare', 'TZS ${ride.fare?.toStringAsFixed(0) ?? 'N/A'}'),
                  verticalSpaceMedium,
                  _buildSectionHeader(theme, isDriver ? 'Customer Info' : 'Driver Info'),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundImage: NetworkImage(isDriver ? ride.customerProfileImageUrl ?? '' : ride.driverProfileImageUrl ?? ''),
                      child: (isDriver ? ride.customerProfileImageUrl : ride.driverProfileImageUrl) == null ? const Icon(Icons.person) : null,
                    ),
                    title: Text(isDriver ? ride.customerName ?? 'Customer' : ride.driverName ?? 'Driver'),
                    subtitle: Text(isDriver ? ride.customerDetails ?? '' : 'Vehicle: ${ride.driverVehicleType ?? 'N/A'}'),
                  ),
                  verticalSpaceLarge,
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.support_agent),
                      label: const Text('Get Help With This Ride'),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(rideRequestId: ride.id!, recipientId: 'support_team_id', recipientName: 'Support Team', isChatActive: false, canContactAdmin: true)));
                      },
                      style: OutlinedButton.styleFrom(side: BorderSide(color: theme.colorScheme.secondary), foregroundColor: theme.colorScheme.secondary),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
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
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}