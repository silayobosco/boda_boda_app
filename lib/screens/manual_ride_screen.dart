import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmf;
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../localization/locales.dart';
import '../providers/driver_provider.dart';
import '../providers/location_provider.dart';
import '../utils/map_utils.dart';
import '../utils/ui_utils.dart';
import 'map_picker_screen.dart';

enum ManualRideState {
  selectingDestination,
  previewingRide,
  rideInProgress,
  rideCompleted,
}

class ManualRideScreen extends StatefulWidget {
  const ManualRideScreen({super.key});

  @override
  State<ManualRideScreen> createState() => _ManualRideScreenState();
}

class _ManualRideScreenState extends State<ManualRideScreen> {
  ManualRideState _currentState = ManualRideState.selectingDestination;
  gmf.GoogleMapController? _mapController;
  gmf.LatLng? _destination;
  gmf.LatLng? _startLocation;

  String? _estimatedDistance;
  String? _estimatedDuration;
  double? _estimatedFare;
  List<gmf.LatLng> _routePoints = [];
  bool _isLoading = false;

  // Ride Tracking
  DateTime? _rideStartTime;
  ll.LatLng? _rideTrackingLastLocation;
  double _trackedDistanceKm = 0.0;
  int _trackedDurationSeconds = 0;
  StreamSubscription? _locationSubscription;

  // Final Ride Info
  String? _finalDistance;
  String? _finalDuration;
  double? _finalFare;

  @override
  void initState() {
    super.initState();
    _setInitialLocation();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _setInitialLocation() async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    await locationProvider.updateLocation();
    if (locationProvider.currentLocation != null && mounted) {
      setState(() {
        _startLocation = gmf.LatLng(
          locationProvider.currentLocation!.latitude,
          locationProvider.currentLocation!.longitude,
        );
      });
    }
  }

  Future<void> _selectDestination() async {
    if (_startLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocale.could_not_get_current_location.getString(context))));
      return;
    }
    final result = await Navigator.push<gmf.LatLng>(
      context,
      MaterialPageRoute(
        builder: (context) => MapPickerScreen(initialLocation: _startLocation!),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _destination = result;
        _currentState = ManualRideState.previewingRide;
      });
      _getRouteAndFare();
    }
  }

  Future<void> _getRouteAndFare() async {
    if (_startLocation == null || _destination == null) return;
    if (mounted) setState(() => _isLoading = true);

    // MapUtils.getRouteDetails returns a list of possible routes.
    final List<Map<String, dynamic>>? routes = await MapUtils
        .getRouteDetails(
            apiKey: dotenv.env['GOOGLE_MAPS_API_KEY']!,
            origin: _startLocation!,
            destination: _destination!);

    if (routes != null && routes.isNotEmpty && mounted) {
      final routeDetails = routes.first; // We'll use the primary route.
      final driverProvider =
          Provider.of<DriverProvider>(context, listen: false);
      // Ensure correct types from the map, which can be dynamic.
      final num distanceMeters = (routeDetails['distance_meters'] as num?) ?? 0;
      final dynamic durationSecondsRaw = routeDetails['duration_seconds']; // Can be num or String

      // The API might return duration as a String or num, so we parse it safely.
      final int durationSeconds = int.tryParse(durationSecondsRaw.toString()) ?? 0;

      final fare = driverProvider.calculateFare(
        distanceMeters: distanceMeters.toDouble(),
        durationSeconds: durationSeconds,
      );

      setState(() {
        // The key for the points list is 'points' and it needs to be cast correctly.
        _routePoints = (routeDetails['points'] as List<dynamic>?)
                ?.map((point) => point as gmf.LatLng)
                .toList() ??
            [];
        _estimatedDistance = routeDetails['distance'] as String?;
        _estimatedDuration = routeDetails['duration'] as String?;
        _estimatedFare = fare;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocale.could_not_get_route_details.getString(context))));
    }
  }

  void _startRide() {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    setState(() {
      _currentState = ManualRideState.rideInProgress;
      _rideStartTime = DateTime.now();
      _rideTrackingLastLocation = ll.LatLng(
        _startLocation!.latitude,
        _startLocation!.longitude,
      );
      _trackedDistanceKm = 0.0;
    });

    _locationSubscription = locationProvider.locationStream.listen((locationData) {
      if (mounted && _currentState == ManualRideState.rideInProgress) {
        final currentLatLng = ll.LatLng(locationData.latitude, locationData.longitude);
        if (_rideTrackingLastLocation != null) {
          const distance = ll.Distance();
          final meters = distance(
            _rideTrackingLastLocation!,
            currentLatLng,
          );
          _trackedDistanceKm += meters / 1000.0;
        }
        _rideTrackingLastLocation = currentLatLng;

        final duration = DateTime.now().difference(_rideStartTime!);
        _trackedDurationSeconds = duration.inSeconds;

        setState(() {
          // This will trigger a rebuild of the UI with updated tracking info
        });
      }
    });
  }

  void _completeRide() {
    _locationSubscription?.cancel();
    _locationSubscription = null;

    final driverProvider =
        Provider.of<DriverProvider>(context, listen: false);
    final finalFare = driverProvider.calculateFare(
      distanceMeters: _trackedDistanceKm * 1000,
      durationSeconds: _trackedDurationSeconds,
    );

    setState(() {
      _currentState = ManualRideState.rideCompleted;
      _finalDistance = '${_trackedDistanceKm.toStringAsFixed(2)} km';
      _finalDuration = '${(_trackedDurationSeconds / 60).floor()} min';
      _finalFare = finalFare;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        leading: _currentState == ManualRideState.rideInProgress ? Container() : null,
      ),
      body: _buildBody(),
    );
  }

  String _getAppBarTitle() {
    switch (_currentState) {
      case ManualRideState.selectingDestination:
        return AppLocale.select_destination.getString(context);
      case ManualRideState.previewingRide:
        return AppLocale.manual_ride_preview.getString(context);
      case ManualRideState.rideInProgress:
        return AppLocale.ride_in_progress.getString(context);
      case ManualRideState.rideCompleted:
        return AppLocale.ride_summary.getString(context);
    }
  }

  Widget _buildBody() {
    switch (_currentState) {
      case ManualRideState.selectingDestination:
        return _buildDestinationSelector();
      case ManualRideState.previewingRide:
        return _buildRidePreview();
      case ManualRideState.rideInProgress:
        return _buildRideInProgress();
      case ManualRideState.rideCompleted:
        return _buildRideSummary();
    }
  }

  Widget _buildDestinationSelector() {
    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.search),
        label: Text(AppLocale.select_destination.getString(context)),
        style: appButtonStyle().copyWith(
          padding: MaterialStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 40, vertical: 20)),
        ),
        onPressed: _selectDestination,
      ),
    );
  }

  Widget _buildRidePreview() {
    return Column(
      children: [
        Expanded(
          child: gmf.GoogleMap(
            initialCameraPosition: gmf.CameraPosition(target: _startLocation!, zoom: 14),
            onMapCreated: (controller) => _mapController = controller,
            markers: {
              gmf.Marker(markerId: const gmf.MarkerId('start'), position: _startLocation!),
              gmf.Marker(markerId: const gmf.MarkerId('destination'), position: _destination!),
            },
            polylines: {
              gmf.Polyline(
                polylineId: const gmf.PolylineId('route'),
                points: _routePoints,
                color: Colors.blue,
                width: 5,
              )
            },
          ),
        ),
        _buildRideInfoCard(
          distance: _estimatedDistance,
          duration: _estimatedDuration,
          fare: _estimatedFare,
          buttonText: AppLocale.start_this_ride.getString(context),
          onButtonPressed: _startRide,
        ),
      ],
    );
  }

  Widget _buildRideInProgress() {
    return Column(
      children: [
        Expanded(
          child: gmf.GoogleMap(
            initialCameraPosition: gmf.CameraPosition(target: _startLocation!, zoom: 16),
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: {
              if (_destination != null)
                gmf.Marker(markerId: const gmf.MarkerId('destination'), position: _destination!),
            },
          ),
        ),
        _buildRideInfoCard(
          distance: '${_trackedDistanceKm.toStringAsFixed(2)} km',
          duration: '${(_trackedDurationSeconds / 60).floor()} min',
          buttonText: AppLocale.complete_ride.getString(context),
          onButtonPressed: _completeRide,
        ),
      ],
    );
  }

  Widget _buildRideSummary() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSummaryRow(AppLocale.total_distance.getString(context), _finalDistance ?? ''),
            verticalSpaceMedium,
            _buildSummaryRow(AppLocale.total_duration.getString(context), _finalDuration ?? ''),
            verticalSpaceMedium,
            _buildSummaryRow(AppLocale.final_fare.getString(context), 'TZS ${_finalFare?.toStringAsFixed(0) ?? ''}', isFare: true),
            verticalSpaceLarge,
            ElevatedButton(
              child: Text(AppLocale.close.getString(context)),
              onPressed: () => Navigator.of(context).pop(),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildRideInfoCard({
    String? distance,
    String? duration,
    double? fare,
    required String buttonText,
    required VoidCallback onButtonPressed,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoItem(Icons.social_distance, AppLocale.distance.getString(context), distance ?? AppLocale.calculating.getString(context)),
                _buildInfoItem(Icons.timer_outlined, AppLocale.duration.getString(context), duration ?? AppLocale.calculating.getString(context)),
                if (fare != null)
                  _buildInfoItem(Icons.monetization_on_outlined, AppLocale.fare.getString(context), 'TZS ${fare.toStringAsFixed(0)}'),
              ],
            ),
            verticalSpaceMedium,
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: appButtonStyle().copyWith(
                  padding: MaterialStateProperty.all(const EdgeInsets.symmetric(vertical: 16)),
                ),
                onPressed: onButtonPressed,
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : Text(buttonText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        verticalSpaceSmall,
        Text(label, style: theme.textTheme.bodySmall),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isFare = false}) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.titleMedium),
        Text(
          value,
          style: isFare
              ? theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)
              : theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}