import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmf;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/ride_request_model.dart';
import '../localization/locales.dart';
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

  String _getLocalizedStatus(BuildContext context, String status) {
    switch (status) {
      case 'completed':
        return AppLocale.status_completed.getString(context);
      case 'cancelled_by_customer':
        return AppLocale.status_cancelled_by_customer.getString(context);
      case 'cancelled_by_driver':
        return AppLocale.status_cancelled_by_driver.getString(context);
      default:
        // Fallback for any other status that doesn't have a specific translation
        return status.replaceAll('_', ' ').split(' ').map((str) => str.isNotEmpty ? '${str[0].toUpperCase()}${str.substring(1).toLowerCase()}' : '').join(' ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ride = widget.ride;
    final authService = Provider.of<AuthService>(context, listen: false);
    final isDriver = authService.currentUser?.uid == ride.driverId;

    return Scaffold(
      appBar: AppBar(
        title: Text('${AppLocale.ride_on.getString(context)} ${DateFormat.yMMMd().format(ride.requestTime!)}'),
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
                  _buildSectionHeader(theme, AppLocale.trip_details.getString(context)),
                  _buildDetailItem(theme, Icons.my_location, AppLocale.from.getString(context), ride.pickupAddressName ?? AppLocale.not_available_abbreviation.getString(context)),
                  if (ride.stops.isNotEmpty)
                    ...ride.stops.asMap().entries.map((entry) {
                      final index = entry.key;
                      final stop = entry.value;
                      return _buildDetailItem(theme, Icons.location_on_outlined, '${AppLocale.stop_prefix.getString(context)}${index + 1}', stop['addressName'] ?? AppLocale.not_available_abbreviation.getString(context));
                    }).toList(),
                  _buildDetailItem(theme, Icons.flag, AppLocale.to.getString(context), ride.dropoffAddressName ?? AppLocale.not_available_abbreviation.getString(context)),
                  _buildDetailItem(theme, Icons.schedule, AppLocale.date.getString(context), DateFormat('E, MMM d, yyyy hh:mm a').format(ride.completedTime ?? ride.requestTime!)),
                  _buildDetailItem(theme, Icons.info_outline, AppLocale.status.getString(context), _getLocalizedStatus(context, ride.status)),
                  verticalSpaceMedium,
                  _buildSectionHeader(theme, AppLocale.fare_details.getString(context)),
                  _buildDetailItem(theme, Icons.payments_outlined, AppLocale.final_fare.getString(context), 'TZS ${ride.fare?.toStringAsFixed(0) ?? AppLocale.not_available_abbreviation.getString(context)}'),
                  verticalSpaceMedium,
                  _buildSectionHeader(theme, isDriver ? AppLocale.customer_info.getString(context) : AppLocale.driver_info.getString(context)),
                  Builder(builder: (context) {
                    String subtitleText;
                    if (isDriver) {
                      subtitleText = ride.customerDetails ?? AppLocale.no_customer_details.getString(context);
                    } else {
                      List<String> driverDetails = [];
                      if (ride.driverVehicleType != null && ride.driverVehicleType!.isNotEmpty) driverDetails.add('${AppLocale.vehicle_prefix.getString(context)}${ride.driverVehicleType}');
                      if (ride.driverLicenseNumber != null && ride.driverLicenseNumber!.isNotEmpty) driverDetails.add('${AppLocale.plate_prefix.getString(context)}${ride.driverLicenseNumber}');
                      if (ride.driverGender != null && ride.driverGender != "Unknown" && ride.driverAgeGroup != null && ride.driverAgeGroup != "Unknown") driverDetails.add('${ride.driverGender}, ${ride.driverAgeGroup}');
                      subtitleText = driverDetails.isNotEmpty ? driverDetails.join(' • ') : AppLocale.no_driver_details.getString(context);
                    }
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: NetworkImage(isDriver ? ride.customerProfileImageUrl ?? '' : ride.driverProfileImageUrl ?? ''),
                        child: (isDriver ? ride.customerProfileImageUrl : ride.driverProfileImageUrl) == null ? const Icon(Icons.person) : null,
                      ),
                      title: Text(isDriver ? ride.customerName ?? AppLocale.customer.getString(context) : ride.driverName ?? AppLocale.driver.getString(context)),
                      subtitle: Text(subtitleText),
                    );
                  }),
                  verticalSpaceLarge,
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.support_agent),
                      label: Text(AppLocale.get_help_with_ride.getString(context)),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(rideRequestId: ride.id!, recipientId: 'support_team_id', recipientName: AppLocale.support_team.getString(context), isChatActive: false, canContactAdmin: true)));
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