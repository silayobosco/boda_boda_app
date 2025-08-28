import 'dart:async';
import 'dart:convert';
import 'package:boda_boda/models/ride_request_model.dart';
import 'package:boda_boda/providers/driver_provider.dart';
import 'package:boda_boda/providers/location_provider.dart';
import 'package:boda_boda/services/auth_service.dart';
import 'package:boda_boda/services/firestore_service.dart';
import 'package:boda_boda/utils/map_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmf;
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';
import '../localization/locales.dart';

class UiAction {
  final String message;
  final bool isError;
  final String? type; // e.g., 'dialog', 'snackbar'
  final Map<String, dynamic>? data;

  UiAction(this.message, {this.isError = false, this.type, this.data});
}

class DriverHomeViewModel extends ChangeNotifier {
  // --- Dependencies ---
  final DriverProvider _driverProvider;
  final LocationProvider _locationProvider;
  final FirestoreService _firestoreService;
  final AuthService _authService;
  final BuildContext _context;

  // --- UI Action Callback ---
  Function(UiAction)? onUiAction;

  // --- Map State ---
  gmf.GoogleMapController? mapController;
  final Set<gmf.Marker> _markers = {};
  final Set<gmf.Polyline> _polylines = {};
  gmf.BitmapDescriptor? _bodaIcon;
  gmf.BitmapDescriptor? _kijiweIcon;
  bool _isIconLoaded = false;
  double? currentHeading;
  ll.LatLng? lastPosition;

  Set<gmf.Marker> get markers => {..._markers, ..._rideSpecificMarkers, if (currentKijiweMarker != null) currentKijiweMarker!};
  Set<gmf.Polyline> get polylines => _polylines;

  // --- Ride State ---
  RideRequestModel? activeRideDetails;
  StreamSubscription? _activeRideSubscription;
  bool isLoadingRoute = false;

  // --- Route Drawing State ---
  List<gmf.LatLng> _driverToPickupRoutePoints = [];
  List<Map<String, dynamic>>? proposedRouteLegsData;
  String? proposedRideDistance;
  String? proposedRideDuration;
  String? driverToPickupDistance;
  String? driverToPickupDuration;
  String? mainRideDistance;
  String? mainRideDuration;
  String? currentlyDisplayedProposedRideId;
  final Set<gmf.Marker> _rideSpecificMarkers = {};
  final String _googlePlacesApiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;

  // --- Kijiwe State ---
  gmf.Marker? currentKijiweMarker;
  StreamSubscription? _kijiweSubscription;

  // --- Ride Request Sheet State ---
  Timer? _declineTimer;
  int countdownSeconds = 30;
  String? pendingRideCustomerName;

  // --- Ride Tracking State ---
  DateTime? _rideTrackingStartTime;
  ll.LatLng? _rideTrackingLastLocation;
  double _trackedDistanceKm = 0.0;
  int _trackedDrivingDurationSeconds = 0;

  DriverHomeViewModel({
    required DriverProvider driverProvider,
    required LocationProvider locationProvider,
    required FirestoreService firestoreService,
    required AuthService authService,
    required BuildContext context,
  })  : _driverProvider = driverProvider,
        _locationProvider = locationProvider,
        _firestoreService = firestoreService,
        _authService = authService,
        _context = context {
    _driverProvider.addListener(_onDriverProviderChange);
    _locationProvider.addListener(_onLocationProviderChange);
  }

  Future<void> initialize() async {
    await _loadCustomMarker();
    await _driverProvider.loadDriverData();
    if (_driverProvider.currentKijiweId != null) {
      _listenToCurrentKijiwe(_driverProvider.currentKijiweId!);
    }
    await _locationProvider.updateLocation();
    centerMapOnDriver();
    _fetchDriverStats();
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
      _isIconLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading custom marker: $e");
    }
  }

  void _onDriverProviderChange() {
    if (_driverProvider.pendingRideRequestDetails != null && activeRideDetails == null) {
      final newRideId = _driverProvider.pendingRideRequestDetails!['rideRequestId'] as String?;
      if (!isLoadingRoute && (newRideId != currentlyDisplayedProposedRideId || _polylines.isEmpty)) {
        _startDeclineTimer();
        _initiateFullProposedRideRouteForSheet(_driverProvider.pendingRideRequestDetails!);
      }
    } else if (_driverProvider.pendingRideRequestDetails == null && activeRideDetails == null) {
      if (currentlyDisplayedProposedRideId != null || _polylines.isNotEmpty || _rideSpecificMarkers.isNotEmpty) {
        _cancelDeclineTimer();
        _polylines.clear();
        _rideSpecificMarkers.clear();
        currentlyDisplayedProposedRideId = null;
        proposedRideDistance = null;
        proposedRideDuration = null;
        proposedRouteLegsData = null;
        notifyListeners();
      }
    }
  }

  void _onLocationProviderChange() {
    final newLocation = _locationProvider.currentLocation;
    if (newLocation == null) return;

    final newLatLng = ll.LatLng(newLocation.latitude, newLocation.longitude);
    lastPosition = newLatLng;
    currentHeading = _locationProvider.heading;

    if (activeRideDetails?.status == 'onRide') {
      if (_rideTrackingStartTime == null) {
        _rideTrackingStartTime = DateTime.now();
        _rideTrackingLastLocation = newLatLng;
        _trackedDistanceKm = 0.0;
        _trackedDrivingDurationSeconds = 0;
      } else {
        if (_rideTrackingLastLocation != null) {
          final distanceBetweenUpdates = const ll.Distance().as(ll.LengthUnit.Kilometer, _rideTrackingLastLocation!, newLatLng);
          _trackedDistanceKm += distanceBetweenUpdates;
        }
        _rideTrackingLastLocation = newLatLng;
        final elapsedDuration = DateTime.now().difference(_rideTrackingStartTime!);
        _trackedDrivingDurationSeconds = elapsedDuration.inSeconds;
      }
      _updateDynamicPolylineForProgress(gmf.LatLng(newLatLng.latitude, newLatLng.longitude));
    } else {
      _rideTrackingStartTime = null;
      _rideTrackingLastLocation = null;
    }

    if (_driverProvider.isOnline && mapController != null && lastPosition != null && activeRideDetails == null && _driverProvider.pendingRideRequestDetails == null) {
      mapController?.animateCamera(gmf.CameraUpdate.newLatLng(gmf.LatLng(lastPosition!.latitude, lastPosition!.longitude)));
    }

    if (_driverProvider.isOnline && lastPosition != null) {
      _driverProvider.updateDriverPosition(gmf.LatLng(lastPosition!.latitude, lastPosition!.longitude), currentHeading)
          .catchError((e) => debugPrint('Error in driverProvider.updateDriverPosition: $e'));
    }
    _updateDriverMarker();
  }

  void _updateDriverMarker() {
    _markers.removeWhere((m) => m.markerId.value == 'driver');
    if (lastPosition != null && _isIconLoaded) {
      _markers.add(gmf.Marker(
        markerId: const gmf.MarkerId('driver'),
        position: gmf.LatLng(lastPosition!.latitude, lastPosition!.longitude),
        icon: _bodaIcon ?? gmf.BitmapDescriptor.defaultMarker,
        rotation: currentHeading ?? 0.0,
        anchor: const Offset(0.5, 0.5),
        flat: true,
        zIndex: 1000,
      ));
    }
    notifyListeners();
  }

  Future<void> centerMapOnDriver() async {
    if (_locationProvider.currentLocation == null || mapController == null) return;

    mapController?.animateCamera(
      gmf.CameraUpdate.newCameraPosition(
        gmf.CameraPosition(
          target: gmf.LatLng(_locationProvider.currentLocation!.latitude, _locationProvider.currentLocation!.longitude),
          zoom: await mapController!.getZoomLevel(),
          bearing: 0,
        ),
      ),
    );
  }

  Future<void> toggleOnlineStatus() async {
    final bool wasOnline = _driverProvider.isOnline;
    final String? errorMessage = await _driverProvider.toggleOnlineStatus();
    if (errorMessage != null) {
      onUiAction?.call(UiAction(errorMessage, isError: true));
    } else {
      onUiAction?.call(UiAction(wasOnline ? AppLocale.you_are_now_offline.getString(_context) : AppLocale.you_are_now_online.getString(_context)));
    }
  }

  Future<void> _fetchDriverStats() async {
    final userId = _authService.currentUser?.uid;
    if (userId != null) {
      await _driverProvider.fetchDriverDailyEarnings(userId);
    }
  }

  void _startDeclineTimer() {
    _cancelDeclineTimer();
    countdownSeconds = 30;
    notifyListeners();
    _declineTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdownSeconds > 0) {
        countdownSeconds--;
        notifyListeners();
      } else {
        timer.cancel();
        final rideData = _driverProvider.pendingRideRequestDetails;
        if (rideData != null) {
          declineRide(rideData['rideRequestId'], rideData['customerId']);
        }
      }
    });
  }

  void _cancelDeclineTimer() {
    _declineTimer?.cancel();
  }

  Future<void> _initiateFullProposedRideRouteForSheet(Map<String, dynamic> rideData) async {
    final String? newRideRequestId = rideData['rideRequestId'] as String?;
    if (newRideRequestId == null) return;
    if (isLoadingRoute) return;
    if (newRideRequestId == currentlyDisplayedProposedRideId && _polylines.isNotEmpty) return;

    final pLat = double.tryParse(rideData['pickupLat'].toString());
    final pLng = double.tryParse(rideData['pickupLng'].toString());
    final dLat = double.tryParse(rideData['dropoffLat'].toString());
    final dLng = double.tryParse(rideData['dropoffLng'].toString());

    if (pLat == null || pLng == null || dLat == null || dLng == null) return;

    final ridePickupLocation = gmf.LatLng(pLat, pLng);
    final rideDropoffLocation = gmf.LatLng(dLat, dLng);

    List<gmf.LatLng> customerStops = [];
    if (rideData['stops'] is String && rideData['stops'].isNotEmpty) {
      try {
        final List<dynamic> decodedStopsList = jsonDecode(rideData['stops']);
        customerStops = decodedStopsList.map((stopMap) {
          final locationString = stopMap['location'] as String?;
          if (locationString != null) {
            final parts = locationString.split(',');
            if (parts.length == 2) {
              return gmf.LatLng(double.parse(parts[0]), double.parse(parts[1]));
            }
          }
          return null;
        }).whereType<gmf.LatLng>().toList();
      } catch (e) {
        debugPrint("Error parsing stops: $e");
      }
    }

    if (_locationProvider.currentLocation == null) await _locationProvider.updateLocation();
    if (_locationProvider.currentLocation == null) return;

    final driverCurrentLocation = gmf.LatLng(_locationProvider.currentLocation!.latitude, _locationProvider.currentLocation!.longitude);

    pendingRideCustomerName = rideData['customerName'] as String?;

    await _fetchAndDisplayRoute(
      origin: driverCurrentLocation,
      destination: rideDropoffLocation,
      waypoints: [ridePickupLocation, ...customerStops],
      onRouteFetched: (distance, duration, points, legs) {
        if (points != null && points.isNotEmpty) {
          proposedRouteLegsData = legs;
          if (legs != null) {
            if (legs.isNotEmpty) {
              driverToPickupDistance = legs[0]['distance']?['text'] as String?;
              driverToPickupDuration = legs[0]['duration']?['text'] as String?;
            }
            if (legs.length > 1) {
              double mainRideTotalDistanceMeters = 0;
              double mainRideTotalDurationSeconds = 0;
              for (int i = 1; i < legs.length; i++) {
                mainRideTotalDistanceMeters += (legs[i]['distance']?['value'] as num?) ?? 0;
                mainRideTotalDurationSeconds += (legs[i]['duration']?['value'] as num?) ?? 0;
              }
              mainRideDistance = "${(mainRideTotalDistanceMeters / 1000).toStringAsFixed(1)} km";
              mainRideDuration = "${(mainRideTotalDurationSeconds / 60).round()} min";
            }
          }

          proposedRideDistance = distance;
          proposedRideDuration = duration;

          int pickupIndexInEntireRoute = MapUtils.findClosestPointIndex(ridePickupLocation, points);
          if (pickupIndexInEntireRoute != -1) {
            _driverToPickupRoutePoints = points.sublist(0, pickupIndexInEntireRoute + 1);
          }

          _polylines.clear();
          _polylines.add(gmf.Polyline(polylineId: const gmf.PolylineId('proposed_driver_to_pickup'), points: _driverToPickupRoutePoints, color: Colors.blueAccent, width: 6));
          _polylines.add(gmf.Polyline(polylineId: const gmf.PolylineId('proposed_customer_journey'), points: points.sublist(pickupIndexInEntireRoute), color: Colors.deepPurpleAccent, width: 6));

          final gmf.LatLngBounds? bounds = MapUtils.boundsFromLatLngList(points);
          if (mapController != null && bounds != null) mapController!.animateCamera(gmf.CameraUpdate.newLatLngBounds(bounds, 60));
        }
        notifyListeners();
      },
    );

    _rideSpecificMarkers.clear();
    _rideSpecificMarkers.add(gmf.Marker(markerId: gmf.MarkerId('proposed_pickup'), position: ridePickupLocation, icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueGreen)));
    _rideSpecificMarkers.add(gmf.Marker(markerId: gmf.MarkerId('proposed_dropoff'), position: rideDropoffLocation, icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueRed)));
    customerStops.asMap().forEach((index, stopLatLng) {
      _rideSpecificMarkers.add(gmf.Marker(markerId: gmf.MarkerId('proposed_stop_$index'), position: stopLatLng, icon: gmf.BitmapDescriptor.defaultMarkerWithHue(gmf.BitmapDescriptor.hueOrange)));
    });

    if (_polylines.isNotEmpty && !isLoadingRoute) {
      currentlyDisplayedProposedRideId = newRideRequestId;
    }
    notifyListeners();
  }

  Future<void> _fetchAndDisplayRoute({
    required gmf.LatLng origin,
    required gmf.LatLng destination,
    List<gmf.LatLng>? waypoints,
    required Function(String? distance, String? duration, List<gmf.LatLng>? points, List<Map<String, dynamic>>? legs) onRouteFetched,
  }) async {
    if (origin.latitude == destination.latitude && origin.longitude == destination.longitude && (waypoints == null || waypoints.isEmpty)) {
      onRouteFetched(null, null, null, null);
      return;
    }

    isLoadingRoute = true;
    proposedRouteLegsData = null;
    proposedRideDistance = null;
    proposedRideDuration = null;
    driverToPickupDistance = null;
    driverToPickupDuration = null;
    mainRideDistance = null;
    mainRideDuration = null;
    notifyListeners();

    try {
      final List<Map<String, dynamic>>? routeDetailsList = await MapUtils.getRouteDetails(
        origin: origin,
        destination: destination,
        waypoints: waypoints,
        apiKey: _googlePlacesApiKey,
      );

      if (routeDetailsList != null && routeDetailsList.isNotEmpty) {
        final Map<String, dynamic> primaryRouteDetails = routeDetailsList.first;
        onRouteFetched(
          primaryRouteDetails['distance'] as String?,
          primaryRouteDetails['duration'] as String?,
          primaryRouteDetails['points'] as List<gmf.LatLng>?,
          (primaryRouteDetails['legs'] as List<dynamic>?)?.map((leg) => leg as Map<String, dynamic>).toList(),
        );
      } else {
        onRouteFetched(null, null, null, null);
      }
    } catch (e) {
      debugPrint('Error in _fetchAndDisplayRoute: $e');
      onRouteFetched(null, null, null, null);
    } finally {
      isLoadingRoute = false;
      notifyListeners();
    }
  }

  void _updateDynamicPolylineForProgress(gmf.LatLng driverCurrentLocation) {
    if (activeRideDetails == null) return;

    final status = activeRideDetails!.status;
    List<gmf.LatLng> basePathPoints;

    if (status == 'accepted' || status == 'goingToPickup') {
      basePathPoints = _driverToPickupRoutePoints;
    } else if (status == 'arrived' || status == 'onRide') {
      basePathPoints = _polylines.firstWhere((p) => p.polylineId.value == 'main_ride_active', orElse: () => const gmf.Polyline(polylineId: gmf.PolylineId(''))).points;
    } else {
      return;
    }

    if (basePathPoints.isEmpty) return;

    int closestPointIndex = MapUtils.findClosestPointIndex(driverCurrentLocation, basePathPoints);
    if (closestPointIndex == -1) return;

    List<gmf.LatLng> remainingPath = [driverCurrentLocation, ...basePathPoints.sublist(closestPointIndex)];
    _polylines.removeWhere((p) => p.polylineId.value.contains('dynamic'));
    _polylines.add(gmf.Polyline(
      polylineId: gmf.PolylineId('dynamic_route_segment'),
      points: remainingPath,
      color: Colors.blue,
      width: 6,
    ));
    notifyListeners();
  }

  Future<void> acceptRide(String rideId, String customerId) async {
    _cancelDeclineTimer();
    try {
      await _driverProvider.acceptRideRequest(_context, rideId, customerId);
      final pendingDetails = _driverProvider.pendingRideRequestDetails;
      List<Map<String, dynamic>> stopsList = [];
      if (pendingDetails != null && pendingDetails['stops'] is String && (pendingDetails['stops'] as String).isNotEmpty) {
        try {
          final List<dynamic> decodedStops = jsonDecode(pendingDetails['stops']);
          stopsList = decodedStops.map((stop) {
            final stopMap = stop as Map<String, dynamic>;
            final locationString = stopMap['location'] as String?;
            gmf.LatLng? location;
            if (locationString != null) {
              final parts = locationString.split(',');
              if (parts.length == 2) {
                location = gmf.LatLng(double.parse(parts[0]), double.parse(parts[1]));
              }
            }
            return {
              'name': stopMap['name'] as String? ?? 'Stop',
              'location': location ?? const gmf.LatLng(0, 0),
              'addressName': stopMap['addressName'] as String?,
            };
          }).toList();
        } catch (e) {
          debugPrint("Error parsing stops in acceptRide: $e");
        }
      }
      activeRideDetails = RideRequestModel(
        id: rideId,
        customerId: customerId,
        status: 'accepted',
        customerName: pendingDetails?['customerName'] as String?,
        pickup: gmf.LatLng(double.parse(pendingDetails?['pickupLat'].toString() ?? '0'), double.parse(pendingDetails?['pickupLng'].toString() ?? '0')),
        dropoff: gmf.LatLng(double.parse(pendingDetails?['dropoffLat'].toString() ?? '0'), double.parse(pendingDetails?['dropoffLng'].toString() ?? '0')),
        stops: stopsList,
      );
      _polylines.clear();
      _rideSpecificMarkers.clear();
      notifyListeners();
      _listenToActiveRide(rideId);
      onUiAction?.call(UiAction(AppLocale.ride_accepted.getString(_context)));
    } catch (e) {
      onUiAction?.call(UiAction('${AppLocale.failed_to_accept_ride.getString(_context)}: ${e.toString()}', isError: true));
    }
  }

  void _listenToActiveRide(String rideId) {
    _activeRideSubscription?.cancel();
    _activeRideSubscription = _firestoreService.getRideRequestDocumentStream(rideId).listen(
      (DocumentSnapshot rideSnapshot) {
        if (rideSnapshot.exists && rideSnapshot.data() != null) {
          activeRideDetails = RideRequestModel.fromJson(rideSnapshot.data() as Map<String, dynamic>, rideSnapshot.id);
          if (['completed', 'cancelled_by_customer', 'cancelled_by_driver'].contains(activeRideDetails?.status)) {
            onUiAction?.call(UiAction('show_rate_customer_dialog', data: {'rideId': rideId, 'customerId': activeRideDetails!.customerId}));
            resetActiveRideState();
          }
          notifyListeners();
        } else {
          resetActiveRideState();
        }
      },
      onError: (error) => resetActiveRideState(),
    );
  }

  Future<void> declineRide(String rideId, String customerId) async {
    _cancelDeclineTimer();
    try {
      await _driverProvider.declineRideRequest(_context, rideId, customerId);
      onUiAction?.call(UiAction(AppLocale.ride_declined.getString(_context)));
    } catch (e) {
      onUiAction?.call(UiAction('${AppLocale.error_declining_ride.getString(_context)}: ${e.toString()}', isError: true));
    }
  }

  Future<void> confirmArrival() async {
    if (activeRideDetails?.id == null) {
      onUiAction?.call(UiAction(AppLocale.error_ride_id_missing.getString(_context), isError: true));
      return;
    }
    try {
      await _driverProvider.confirmArrival(_context, activeRideDetails!.id!, activeRideDetails!.customerId);
    } catch (e) {
      onUiAction?.call(UiAction('${AppLocale.failed_to_confirm_arrival.getString(_context)}: ${e.toString()}', isError: true));
    }
  }

  Future<void> startRide() async {
    if (activeRideDetails?.id == null) {
      onUiAction?.call(UiAction(AppLocale.error_ride_id_missing.getString(_context), isError: true));
      return;
    }
    try {
      await _driverProvider.startRide(_context, activeRideDetails!.id!, activeRideDetails!.customerId);
    } catch (e) {
      onUiAction?.call(UiAction('${AppLocale.failed_to_start_ride.getString(_context)}: ${e.toString()}', isError: true));
    }
  }

  Future<void> completeRide() async {
    if (activeRideDetails?.id == null) {
      onUiAction?.call(UiAction(AppLocale.error_ride_id_missing.getString(_context), isError: true));
      return;
    }
    try {
      await _driverProvider.completeRide(
        _context,
        activeRideDetails!.id!,
        activeRideDetails!.customerId,
        actualDistanceKm: _trackedDistanceKm,
        actualDrivingDurationMinutes: _trackedDrivingDurationSeconds > 0 ? _trackedDrivingDurationSeconds / 60.0 : null,
      );
      onUiAction?.call(UiAction(AppLocale.ride_completed_successfully.getString(_context)));
    } catch (e) {
      onUiAction?.call(UiAction('${AppLocale.failed_to_complete_ride.getString(_context)}: ${e.toString()}', isError: true));
    }
  }

  Future<void> cancelRide() async {
    if (activeRideDetails?.id == null) {
      onUiAction?.call(UiAction(AppLocale.error_ride_id_missing.getString(_context), isError: true));
      return;
    }
    try {
      await _driverProvider.cancelRide(_context, activeRideDetails!.id!, activeRideDetails!.customerId);
    } catch (e) {
      onUiAction?.call(UiAction('${AppLocale.failed_to_cancel_ride.getString(_context)}: ${e.toString()}', isError: true));
    }
  }

  Future<void> rateCustomer(String rideId, String customerId, double rating, String? comment) async {
    try {
      await _driverProvider.rateCustomer(_context, customerId, rating, rideId, comment: comment);
      onUiAction?.call(UiAction(AppLocale.rating_submitted.getString(_context)));
    } catch (e) {
      onUiAction?.call(UiAction('${AppLocale.failed_to_submit_rating.getString(_context)}: ${e.toString()}', isError: true));
    }
  }

  void resetActiveRideState() {
    _cancelDeclineTimer();
    activeRideDetails = null;
    _polylines.clear();
    _rideSpecificMarkers.clear();
    _driverToPickupRoutePoints.clear();
    _rideTrackingStartTime = null;
    _rideTrackingLastLocation = null;
    _trackedDistanceKm = 0.0;
    _trackedDrivingDurationSeconds = 0;
    _driverProvider.clearPendingRide();
    notifyListeners();
  }

  void _listenToCurrentKijiwe(String kijiweId) {
    _kijiweSubscription?.cancel();
    _kijiweSubscription = _firestoreService.getKijiweQueueStream(kijiweId).listen((doc) {
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        final position = data['position']?['geopoint'] as GeoPoint?;
        final name = data['name'] as String?;
        if (position != null && name != null && _kijiweIcon != null) {
          currentKijiweMarker = gmf.Marker(
            markerId: const gmf.MarkerId('current_kijiwe'),
            position: gmf.LatLng(position.latitude, position.longitude),
            icon: _kijiweIcon!,
            infoWindow: gmf.InfoWindow(title: '${AppLocale.home_kijiwe_prefix.getString(_context)} $name'),
            zIndex: 1,
          );
          notifyListeners();
        }
      }
    });
  }

  String? getLegInfo(int legIndex) {
    if (proposedRouteLegsData != null && legIndex >= 0 && legIndex < proposedRouteLegsData!.length) {
      final leg = proposedRouteLegsData![legIndex];
      final distance = leg['distance']?['text'] as String?;
      final duration = leg['duration']?['text'] as String?;
      if (distance != null && duration != null) {
        return '$duration · $distance';
      }
    }
    return null;
  }

  Future<void> navigateToNextPoint() async {
    if (activeRideDetails == null) {
      onUiAction?.call(UiAction(AppLocale.no_active_ride.getString(_context), isError: true));
      return;
    }
    // ... logic to determine destinationLatLng and destinationName ...
    gmf.LatLng? destinationLatLng;
    // This logic needs to be completed based on ride status and stops
    if (destinationLatLng != null) {
      final uri = Uri.parse('google.navigation:q=${destinationLatLng.latitude},${destinationLatLng.longitude}&mode=d');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        onUiAction?.call(UiAction(AppLocale.could_not_launch_navigation.getString(_context), isError: true));
      }
    }
  }

  @override
  void dispose() {
    mapController?.dispose();
    _locationProvider.removeListener(_onLocationProviderChange);
    _driverProvider.removeListener(_onDriverProviderChange);
    _activeRideSubscription?.cancel();
    _kijiweSubscription?.cancel();
    _declineTimer?.cancel();
    super.dispose();
  }
}