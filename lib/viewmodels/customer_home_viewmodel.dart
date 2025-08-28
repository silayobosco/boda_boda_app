import 'dart:async';
import 'dart:convert';
import 'package:boda_boda/models/ride_request_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:boda_boda/providers/ride_request_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:flutter_localization/flutter_localization.dart';
import '../providers/location_provider.dart';
import 'package:geocoding/geocoding.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/stop.dart';
import '../models/user_model.dart';
import '../utils/map_utils.dart';
import '../services/firestore_service.dart';
import '../localization/locales.dart';

class UiAction {
  final String message;
  final bool isError;
  UiAction(this.message, {this.isError = false});
}

class CustomerHomeViewModel extends ChangeNotifier {
  // --- Dependencies ---
  final RideRequestProvider _rideRequestProvider;
  final FirestoreService _firestoreService;
  final LocationProvider _locationProvider;
  final BuildContext _context; // For localization

  // --- UI Action Callback ---
  Function(UiAction)? onUiAction;

  // --- Map and Location State ---
  GoogleMapController? mapController;
  ll.LatLng? pickupLocation;
  ll.LatLng? dropOffLocation;
  final Set<Marker> _markers = {};
  Set<Marker> get markers => {..._markers, ..._kijiweMarkers};
  final Set<Polyline> polylines = {};
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController destinationController = TextEditingController();
  final String _googlePlacesApiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;

  // --- Search and Suggestions State ---
  List<Map<String, dynamic>> destinationSuggestions = [];
  List<Map<String, dynamic>> pickupSuggestions = [];
  final List<String> searchHistory = [];

  // --- UI Interaction State ---
  bool selectingPickup = false;
  bool editingPickup = false;
  bool editingDestination = false;

  // --- Stops Management ---
  final List<Stop> stops = [];
  int? editingStopIndex;
  bool routeReady = false;
  List<Map<String, dynamic>> stopSuggestions = [];

  // --- Route Management ---
  List<Map<String, dynamic>> allFetchedRoutes = [];
  int selectedRouteIndex = 0;
  String? selectedRouteDistance;
  String? selectedRouteDuration;

  // --- Ride Lifecycle State ---
  bool isFindingDriver = false;
  String? activeRideRequestId;
  RideRequestModel? activeRideRequestDetails;
  UserModel? assignedDriverModel;
  StreamSubscription? _activeRideSubscription;
  StreamSubscription? _driverLocationSubscription;
  BitmapDescriptor? driverIcon;
  bool isDriverIconLoaded = false;
  String? _processedCompletedRideId;

  // --- Kijiwe State ---
  StreamSubscription? _kijiweSubscription;
  BitmapDescriptor? kijiweIcon;
  final Set<Marker> _kijiweMarkers = {};
  bool _kijiweFetchInitiated = false;
  static const double _kijiweSearchRadiusKm = 10.0;

  // --- Configuration State ---
  int maxSchedulingDaysAhead = 30;
  int minSchedulingMinutesAhead = 5;
  double? estimatedFare;
  Map<String, dynamic>? _fareConfig;
  final TextEditingController customerNoteController = TextEditingController();

  CustomerHomeViewModel({
    required RideRequestProvider rideRequestProvider,
    required FirestoreService firestoreService,
    required LocationProvider locationProvider,
    required BuildContext context,
  })  : _rideRequestProvider = rideRequestProvider,
        _firestoreService = firestoreService,
        _locationProvider = locationProvider,
        _context = context {
    _locationProvider.addListener(_onLocationUpdated);
  }

  Future<void> setupInitialMapState() async {
    await _loadMarkerIcons();
    await _locationProvider.updateLocation();
    if (_locationProvider.currentLocation != null) {
      _onLocationUpdated();
    }
    await _loadSearchHistory();
    await _fetchSchedulingLimits();
    await _fetchFareConfig();
  }

  void _onLocationUpdated() {
    final newLocation = _locationProvider.currentLocation;
    if (!_kijiweFetchInitiated && newLocation != null) {
      _kijiweFetchInitiated = true;
      if (pickupLocation == null) {
        pickupLocation = newLocation;
        _updateGooglePickupMarker(LatLng(newLocation.latitude, newLocation.longitude));
        editingDestination = true;
        notifyListeners();
        _reverseGeocode(newLocation, pickupController);
      }
      _fetchAndDisplayNearbyKijiwes();
    }
  }

  Future<void> _fetchFareConfig() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('appConfiguration').doc('fareSettings').get();
      if (doc.exists && doc.data() != null) {
        _fareConfig = doc.data();
        if (selectedRouteDistance != null && selectedRouteDuration != null) {
          _calculateEstimatedFare();
        }
      } else {
        _fareConfig = null;
        _calculateEstimatedFare();
      }
    } catch (e) {
      debugPrint("CustomerHomeViewModel: ERROR fetching fare config: $e");
      _fareConfig = null;
    }
    notifyListeners();
  }

  (double, double) _parseRouteDistanceAndDuration() {
    if (selectedRouteDistance == null || selectedRouteDuration == null) return (0.0, 0.0);
    double distanceKm = 0;
    final distanceMatch = RegExp(r'([\d\.]+)').firstMatch(selectedRouteDistance!);
    if (distanceMatch != null) {
      double numericValue = double.tryParse(distanceMatch.group(1) ?? '0') ?? 0;
      if (selectedRouteDistance!.toLowerCase().contains("km")) distanceKm = numericValue;
      else if (selectedRouteDistance!.toLowerCase().contains("m")) distanceKm = numericValue / 1000.0;
      else distanceKm = numericValue;
    }

    double durationMinutes = 0;
    final hourMatch = RegExp(r'(\d+)\s*hr').firstMatch(selectedRouteDuration!);
    if (hourMatch != null) durationMinutes += (double.tryParse(hourMatch.group(1) ?? '0') ?? 0) * 60;
    final minMatch = RegExp(r'(\d+)\s*min').firstMatch(selectedRouteDuration!);
    if (minMatch != null) durationMinutes += double.tryParse(minMatch.group(1) ?? '0') ?? 0;
    if (durationMinutes == 0 && selectedRouteDuration!.contains("min")) {
      final simpleMinMatch = RegExp(r'([\d\.]+)').firstMatch(selectedRouteDuration!);
      if (simpleMinMatch != null) durationMinutes = double.tryParse(simpleMinMatch.group(1) ?? '0') ?? 0;
    }
    return (distanceKm, durationMinutes);
  }

  Future<void> _fetchSchedulingLimits() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('appConfiguration').doc('schedulingSettings').get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        maxSchedulingDaysAhead = data['maxSchedulingDaysAhead'] as int? ?? maxSchedulingDaysAhead;
        minSchedulingMinutesAhead = data['minSchedulingMinutesAhead'] as int? ?? minSchedulingMinutesAhead;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching scheduling limits: $e. Using defaults.");
    }
  }

  void _calculateEstimatedFare() {
    if (_fareConfig == null || selectedRouteDistance == null || selectedRouteDuration == null) {
      if (estimatedFare != null) {
        estimatedFare = null;
        notifyListeners();
      }
      return;
    }

    final (distanceKm, durationMinutes) = _parseRouteDistanceAndDuration();
    final double baseFare = (_fareConfig!['startingFare'] as num?)?.toDouble() ?? 0.0;
    final double perKmRate = (_fareConfig!['farePerKilometer'] as num?)?.toDouble() ?? 0.0;
    final double perMinRate = (_fareConfig!['farePerMinuteDriving'] as num?)?.toDouble() ?? 0.0;
    final double minFare = (_fareConfig!['minimumFare'] as num?)?.toDouble() ?? 0.0;
    double calculatedFare = baseFare + (distanceKm * perKmRate) + (durationMinutes * perMinRate);
    calculatedFare = calculatedFare > minFare ? calculatedFare : minFare;
    final double roundingInc = (_fareConfig!['roundingIncrement'] as num?)?.toDouble() ?? 0.0;
    if (roundingInc > 0) calculatedFare = (calculatedFare / roundingInc).ceil() * roundingInc;

    if (estimatedFare != calculatedFare) {
      estimatedFare = calculatedFare;
      notifyListeners();
    }
  }

  Future<void> _loadMarkerIcons() async {
    try {
      driverIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/boda_marker.png',
      );
      isDriverIconLoaded = true;

      kijiweIcon = await BitmapDescriptor.fromAssetImage(
        const ImageConfiguration(size: Size(48, 48)),
        'assets/kijiwe_marker.png',
      );
    } catch (e) {
      debugPrint("Error loading marker icons: $e");
    }
    notifyListeners();
  }

  void _fetchAndDisplayNearbyKijiwes() {
    if (pickupLocation == null || kijiweIcon == null) return;

    _kijiweSubscription?.cancel();
    _kijiweSubscription = _firestoreService.getNearbyKijiwes(pickupLocation!, _kijiweSearchRadiusKm).listen(
      (kijiweDocs) {
        final Set<Marker> newMarkers = {};
        for (var doc in kijiweDocs) {
          final data = doc.data() as Map<String, dynamic>?;
          final positionField = data?['position'];
          if (positionField is Map) {
            final geoPointField = positionField['geopoint'];
            if (geoPointField is GeoPoint) {
              final kijiweId = doc.id;
              final kijiweLocation = LatLng(geoPointField.latitude, geoPointField.longitude);
              final kijiweName = data?['name'] as String? ?? 'Kijiwe';
              final memberCount = (data?['permanentMembers'] as List<dynamic>?)?.length ?? 0;

              newMarkers.add(
                Marker(
                  markerId: MarkerId('kijiwe_${doc.id}'),
                  position: kijiweLocation,
                  icon: kijiweIcon!,
                  infoWindow: InfoWindow(
                      title: kijiweName,
                      snippet: AppLocale.infoWindowKijiweSnippet.getString(_context)
                          .replaceFirst('{memberCount}', memberCount.toString())
                  ),
                  onTap: () => onUiAction?.call(UiAction('kijiwe_tap:$kijiweId:$kijiweName:${kijiweLocation.latitude}:${kijiweLocation.longitude}')),
                  alpha: 0.8,
                  zIndex: 1,
                ),
              );
            }
          }
        }
        _kijiweMarkers.clear();
        _kijiweMarkers.addAll(newMarkers);
        notifyListeners();
      },
      onError: (error) {
        onUiAction?.call(UiAction(AppLocale.errorLoadingHubs.getString(_context), isError: true));
      },
    );
  }

  void setKijiweAsLocation(String name, LatLng location, {required bool isPickup}) {
    final llLocation = ll.LatLng(location.latitude, location.longitude);
    if (isPickup) {
      pickupLocation = llLocation;
      pickupController.text = name;
      _updateGooglePickupMarker(location);
    } else {
      dropOffLocation = llLocation;
      destinationController.text = name;
      _updateGoogleDropOffMarker(location);
    }
    _updateSearchHistory(name);
    drawRoute();
    _checkRouteReady();
    notifyListeners();
  }

  void startEditing(String field) {
    editingPickup = false;
    editingDestination = false;
    editingStopIndex = null;

    if (field == 'pickup') editingPickup = true;
    else if (field == 'destination') editingDestination = true;
    else if (field.startsWith('stop_')) {
      editingStopIndex = int.parse(field.split('_')[1]);
    }
    notifyListeners();
  }

  void _checkRouteReady() {
    final newRouteReady = pickupLocation != null && dropOffLocation != null;
    if (routeReady != newRouteReady) {
      routeReady = newRouteReady;
      notifyListeners();
    }
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? storedHistory = prefs.getStringList('search_history');
    if (storedHistory != null) {
      searchHistory.clear();
      searchHistory.addAll(storedHistory);
      notifyListeners();
    }
  }

  void _updateSearchHistory(String address) {
    if (address.isNotEmpty && !searchHistory.contains(address)) {
      searchHistory.insert(0, address);
      if (searchHistory.length > 8) {
        searchHistory.removeLast();
      }
      _saveSearchHistory();
      notifyListeners();
    }
  }

  Future<void> _saveSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('search_history', searchHistory);
  }

  Future<void> _reverseGeocode(ll.LatLng location, TextEditingController controller) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(location.latitude, location.longitude);
      if (placemarks.isNotEmpty) {
        final Placemark place = placemarks.first;
        String address = _formatAddress(place);
        controller.text = address;
        _updateSearchHistory(address);
      } else {
        throw Exception('No placemarks found');
      }
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
      controller.text = _formatFallbackAddress(location);
    }
    notifyListeners();
  }

  String _formatAddress(Placemark place) {
    List<String> addressParts = [];
    if (place.name != null && place.name!.isNotEmpty && place.name != 'Unnamed Road') addressParts.add(place.name!);
    if (place.street != null && place.street!.isNotEmpty) {
      if (addressParts.isEmpty || !addressParts.last.contains(place.street!)) addressParts.add(place.street!);
    }
    if (place.subLocality != null && place.subLocality!.isNotEmpty) addressParts.add(place.subLocality!);
    else if (place.locality != null && place.locality!.isNotEmpty) addressParts.add(place.locality!);
    if (addressParts.isEmpty) return AppLocale.selectedLocation.getString(_context);
    return addressParts.join(', ');
  }

  String _formatFallbackAddress(ll.LatLng location) {
    return AppLocale.locationWithCoords.getString(_context)
        .replaceFirst('{lat}', location.latitude.toStringAsFixed(4))
        .replaceFirst('{lng}', location.longitude.toStringAsFixed(4));
  }

  void _updateGooglePickupMarker(LatLng location) {
    _markers.removeWhere((marker) => marker.markerId == const MarkerId('pickup'));
    _markers.add(
      Marker(
        markerId: const MarkerId('pickup'),
        position: location,
        infoWindow: InfoWindow(title: AppLocale.pickup.getString(_context)),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    );
    notifyListeners();
  }

  void _updateGoogleDropOffMarker(LatLng? location) {
    if (location != null) {
      _markers.removeWhere((marker) => marker.markerId == const MarkerId('dropoff'));
      _markers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: location,
          infoWindow: InfoWindow(title: AppLocale.dropoff.getString(_context)),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
      notifyListeners();
    }
  }

  void _updateStopMarker(int index, LatLng location) {
    _markers.removeWhere((marker) => marker.markerId == MarkerId('stop_$index'));
    _markers.add(
      Marker(
        markerId: MarkerId('stop_$index'),
        position: location,
        infoWindow: InfoWindow(title: AppLocale.stopWithNumber.getString(_context).replaceFirst('{number}', (index + 1).toString())),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        zIndex: index.toDouble(),
      ),
    );
    notifyListeners();
  }

  void handleMapTap(LatLng tappedLatLng) {
    final llTappedLatLng = ll.LatLng(tappedLatLng.latitude, tappedLatLng.longitude);

    if (selectingPickup || editingPickup) {
      pickupLocation = llTappedLatLng;
      _updateGooglePickupMarker(tappedLatLng);
      selectingPickup = false;
      editingPickup = false;
      editingDestination = true;
      onUiAction?.call(UiAction('unfocus:pickup'));
      _reverseGeocode(pickupLocation!, pickupController);
    } else if (editingStopIndex != null) {
      stops[editingStopIndex!].location = llTappedLatLng;
      _reverseGeocode(llTappedLatLng, stops[editingStopIndex!].controller);
      _updateStopMarker(editingStopIndex!, tappedLatLng);
      editingStopIndex = null;
      onUiAction?.call(UiAction('unfocus:stop'));
      drawRoute();
    } else if (editingDestination) {
      dropOffLocation = llTappedLatLng;
      _updateGoogleDropOffMarker(tappedLatLng);
      _reverseGeocode(dropOffLocation!, destinationController);
      editingDestination = false;
      onUiAction?.call(UiAction('unfocus:destination'));
      drawRoute();
    } else if (dropOffLocation == null && !editingPickup && editingStopIndex == null) {
      dropOffLocation = llTappedLatLng;
      _updateGoogleDropOffMarker(tappedLatLng);
      _reverseGeocode(dropOffLocation!, destinationController);
    }
    _checkRouteReady();
    notifyListeners();
  }

  Future<void> drawRoute() async {
    if (pickupLocation == null || dropOffLocation == null) {
      polylines.clear();
      allFetchedRoutes.clear();
      selectedRouteDistance = null;
      selectedRouteDuration = null;
      estimatedFare = null;
      notifyListeners();
      return;
    }

    polylines.clear();
    allFetchedRoutes.clear();
    selectedRouteIndex = 0;
    selectedRouteDistance = null;
    selectedRouteDuration = null;
    notifyListeners();

    try {
      final List<ll.LatLng>? waypointsLatLng = stops.where((s) => s.location != null).map((s) => s.location!).toList();
      final List<Map<String, dynamic>>? routes = await MapUtils.getRouteDetails(
        origin: LatLng(pickupLocation!.latitude, pickupLocation!.longitude),
        destination: LatLng(dropOffLocation!.latitude, dropOffLocation!.longitude),
        apiKey: _googlePlacesApiKey,
        waypoints: waypointsLatLng?.map((ll) => LatLng(ll.latitude, ll.longitude)).toList(),
      );

      if (routes != null && routes.isNotEmpty) {
        allFetchedRoutes = routes;
        selectRoute(0);

        if (allFetchedRoutes.isNotEmpty) {
          final List<LatLng> primaryRoutePoints = allFetchedRoutes[0]['points'] as List<LatLng>;
          mapController?.animateCamera(
            CameraUpdate.newLatLngBounds(MapUtils.boundsFromLatLngList(primaryRoutePoints), 100),
          );
        }
      } else {
        polylines.clear();
        selectedRouteDistance = null;
        selectedRouteDuration = null;
        estimatedFare = null;
      }
    } catch (e) {
      debugPrint('Error in drawRoute (ViewModel): $e');
      polylines.clear();
      selectedRouteDistance = null;
      selectedRouteDuration = null;
      estimatedFare = null;
      onUiAction?.call(UiAction(AppLocale.failedToGetRouteDetails.getString(_context), isError: true));
    }
    _checkRouteReady();
    notifyListeners();
  }

  void selectRoute(int index) {
    if (allFetchedRoutes.isEmpty) return;

    selectedRouteIndex = index;
    polylines.clear();
    for (int i = 0; i < allFetchedRoutes.length; i++) {
      final routeData = allFetchedRoutes[i];
      final Polyline originalPolyline = routeData['polyline'] as Polyline;

      polylines.add(originalPolyline.copyWith(
        colorParam: i == selectedRouteIndex ? Colors.blueAccent : Colors.grey,
        widthParam: i == selectedRouteIndex ? 6 : 4,
        onTapParam: () => selectRoute(i),
      ));
    }
    selectedRouteDistance = allFetchedRoutes[selectedRouteIndex]['distance'] as String?;
    selectedRouteDuration = allFetchedRoutes[selectedRouteIndex]['duration'] as String?;
    _calculateEstimatedFare();
    notifyListeners();
  }

  void _listenToActiveRide(String rideId) {
    _stopListeningToActiveRide();
    _activeRideSubscription = _rideRequestProvider.getRideStream(rideId).listen((rideDetails) {
      activeRideRequestDetails = rideDetails;

      if (rideDetails == null) {
        resetUIForNewTrip();
        notifyListeners();
        return;
      }

      final driverId = rideDetails.driverId;
      final rideStatus = rideDetails.status;

      if (driverId != null) {
        if (['accepted', 'goingToPickup', 'arrivedAtPickup', 'onRide'].contains(rideStatus)) {
          if (isFindingDriver) isFindingDriver = false;
          if (_driverLocationSubscription == null || assignedDriverModel?.uid != driverId) {
            assignedDriverModel = UserModel(uid: driverId);
            _startListeningToDriverLocation(driverId);
          }
        }
      } else {
        if (_driverLocationSubscription != null) {
          _stopListeningToDriverLocation();
          assignedDriverModel = null;
        }
      }

      if ((rideStatus == 'completed' || rideStatus.contains('cancelled') || rideStatus == 'no_drivers_available') &&
          rideId == activeRideRequestId && rideId != _processedCompletedRideId) {
        _processedCompletedRideId = rideId;
        final endMessage = getRideEndMessage(rideStatus);
        onUiAction?.call(UiAction(endMessage));
        if (rideStatus == 'completed' && rideDetails.driverId != null) {
          onUiAction?.call(UiAction('show_rate_dialog:$rideId:${rideDetails.driverId!}'));
        } else {
          resetUIForNewTrip();
        }
      }
      notifyListeners();
    });
  }

  void _startListeningToDriverLocation(String driverId) {
    _driverLocationSubscription?.cancel();
    _driverLocationSubscription = _firestoreService.getUserDocumentStream(driverId).listen((driverDoc) {
      if (driverDoc.exists && driverDoc.data() != null) {
        final data = driverDoc.data() as Map<String, dynamic>;
        final driverProfile = data['driverProfile'] as Map<String, dynamic>?;
        if (driverProfile != null && driverProfile['currentLocation'] is GeoPoint) {
          final GeoPoint driverGeoPoint = driverProfile['currentLocation'] as GeoPoint;
          final LatLng driverLatLng = LatLng(driverGeoPoint.latitude, driverGeoPoint.longitude);
          final double driverHeading = (driverProfile['currentHeading'] as num?)?.toDouble() ?? 0.0;

          _markers.removeWhere((m) => m.markerId.value == 'driver_active_location');
          _markers.add(
            Marker(
              markerId: const MarkerId('driver_active_location'),
              position: driverLatLng,
              icon: isDriverIconLoaded && driverIcon != null ? driverIcon! : BitmapDescriptor.defaultMarker,
              rotation: driverHeading,
              anchor: const Offset(0.5, 0.5),
              flat: true,
              zIndex: 10,
            ),
          );

          if (pickupLocation != null) {
            final LatLng pickupLatLng = LatLng(pickupLocation!.latitude, pickupLocation!.longitude);
            final bounds = MapUtils.boundsFromLatLngList([driverLatLng, pickupLatLng]);
            mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
          } else {
            mapController?.animateCamera(CameraUpdate.newLatLng(driverLatLng));
          }
          notifyListeners();
        }
      }
    }, onError: (error) {
      debugPrint("Error listening to driver location: $error");
    });
  }

  void _stopListeningToDriverLocation() {
    _driverLocationSubscription?.cancel();
    _driverLocationSubscription = null;
    _markers.removeWhere((m) => m.markerId.value == 'driver_active_location');
    notifyListeners();
  }

  Future<void> getGooglePlacesSuggestions(String query, String type) async {
    if (query.isEmpty) {
      if (type == 'pickup') pickupSuggestions = [];
      if (type == 'destination') destinationSuggestions = [];
      if (type == 'stop') stopSuggestions = [];
      notifyListeners();
      return;
    }
    final url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$_googlePlacesApiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final suggestions = (data['predictions'] as List).map((p) => {
            'place_id': p['place_id'],
            'description': p['description'],
          }).toList();
          if (type == 'pickup') pickupSuggestions = suggestions;
          if (type == 'destination') destinationSuggestions = suggestions;
          if (type == 'stop') stopSuggestions = suggestions;
        }
      }
    } catch (e) {
      debugPrint('Error fetching suggestions: $e');
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>?> _getPlaceDetails(String placeId) async {
    final url = 'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_googlePlacesApiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final geometry = data['result']['geometry']['location'];
          return {'latitude': geometry['lat'], 'longitude': geometry['lng']};
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching place details: $e');
      return null;
    }
  }

  Future<void> handleDestinationSelected(Map<String, dynamic> suggestion) async {
    final placeDetails = await _getPlaceDetails(suggestion['place_id']);
    if (placeDetails != null) {
      final latLng = ll.LatLng(placeDetails['latitude'], placeDetails['longitude']);
      final address = suggestion['description'] ?? '';

      dropOffLocation = latLng;
      _updateGoogleDropOffMarker(LatLng(latLng.latitude, latLng.longitude));
      destinationController.text = suggestion['description'] ?? '';
      destinationSuggestions = [];
      _updateSearchHistory(address);
      editingDestination = false;
      onUiAction?.call(UiAction('unfocus:destination'));

      drawRoute();
    }
    _checkRouteReady();
    notifyListeners();
  }

  Future<void> handlePickupSelected(Map<String, dynamic> suggestion) async {
    final placeDetails = await _getPlaceDetails(suggestion['place_id']);
    if (placeDetails != null) {
      final latLng = ll.LatLng(placeDetails['latitude'], placeDetails['longitude']);
      final address = suggestion['description'] ?? '';

      pickupLocation = latLng;
      _updateGooglePickupMarker(LatLng(latLng.latitude, latLng.longitude));
      pickupController.text = suggestion['description'] ?? '';
      pickupSuggestions = [];
      _updateSearchHistory(address);
      editingPickup = false;
      onUiAction?.call(UiAction('unfocus:pickup'));

      drawRoute();
    }
    _checkRouteReady();
    notifyListeners();
  }

  Future<void> handleStopSelected(int index, Map<String, dynamic> suggestion) async {
    final placeDetails = await _getPlaceDetails(suggestion['place_id']);
    if (placeDetails != null) {
      final latLng = ll.LatLng(placeDetails['latitude'], placeDetails['longitude']);
      final address = suggestion['description'] ?? '';

      stops[index].location = latLng;
      stops[index].controller.text = suggestion['description'] ?? '';
      _updateStopMarker(index, LatLng(latLng.latitude, latLng.longitude));
      stopSuggestions = [];
      _updateSearchHistory(address);
      editingStopIndex = null;
      onUiAction?.call(UiAction('unfocus:stop'));

      drawRoute();
    }
    _checkRouteReady();
    notifyListeners();
  }

  void swapLocations() {
    final tempText = pickupController.text;
    pickupController.text = destinationController.text;
    destinationController.text = tempText;

    final tempLoc = pickupLocation;
    pickupLocation = dropOffLocation;
    dropOffLocation = tempLoc;

    _markers.removeWhere((m) => m.markerId == const MarkerId('pickup'));
    _markers.removeWhere((m) => m.markerId == const MarkerId('dropoff'));

    if (pickupLocation != null) {
      _markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(pickupLocation!.latitude, pickupLocation!.longitude),
        infoWindow: InfoWindow(title: AppLocale.pickup.getString(_context)),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }

    if (dropOffLocation != null) {
      _markers.add(Marker(
        markerId: const MarkerId('dropoff'),
        position: LatLng(dropOffLocation!.latitude, dropOffLocation!.longitude),
        infoWindow: InfoWindow(title: AppLocale.dropoff.getString(_context)),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ));
    }
    _checkRouteReady();
    notifyListeners();
  }

  void clearPickup() {
    pickupController.clear();
    pickupLocation = null;
    selectedRouteDistance = null;
    selectedRouteDuration = null;
    _markers.removeWhere((m) => m.markerId == const MarkerId('pickup'));
    drawRoute();
    _checkRouteReady();
    notifyListeners();
  }

  void clearDestination() {
    destinationController.clear();
    dropOffLocation = null;
    selectedRouteDistance = null;
    selectedRouteDuration = null;
    _markers.removeWhere((m) => m.markerId == const MarkerId('dropoff'));
    drawRoute();
    _checkRouteReady();
    notifyListeners();
  }

  void clearStop(int index) {
    stops[index].controller.clear();
    stops[index].location = null;
    selectedRouteDistance = null;
    selectedRouteDuration = null;
    _markers.removeWhere((m) => m.markerId == MarkerId('stop_$index'));
    drawRoute();
    _checkRouteReady();
    notifyListeners();
  }

  void addStop() {
    stops.add(Stop(name: 'Stop ${stops.length + 1}', address: 'Search or tap on map'));
    editingStopIndex = stops.length - 1;
    notifyListeners();
  }

  void addStopAfter(int index) {
    stops.insert(index + 1, Stop(name: 'Stop ${stops.length + 1}', address: 'Search or tap on map'));
    editingStopIndex = index + 1;
    notifyListeners();
  }

  void removeStop(int index) {
    _markers.removeWhere((m) => m.markerId == MarkerId('stop_$index'));
    stops[index].dispose();
    stops.removeAt(index);

    for (int i = 0; i < stops.length; i++) {
      if (stops[i].location != null) {
        _markers.removeWhere((m) => m.markerId == MarkerId('stop_$i'));
        _updateStopMarker(i, LatLng(stops[i].location!.latitude, stops[i].location!.longitude));
      }
    }

    drawRoute();
    _checkRouteReady();
    notifyListeners();
  }

  Future<void> confirmRideRequest() async {
    if (isFindingDriver) return;

    if (pickupLocation == null || dropOffLocation == null) {
      onUiAction?.call(UiAction(AppLocale.selectPickupAndDropoff.getString(_context), isError: true));
      return;
    }
    final currentUserId = _rideRequestProvider.currentUserId;
    if (currentUserId == null) {
      onUiAction?.call(UiAction(AppLocale.userNotAuthenticated.getString(_context), isError: true));
      return;
    }

    try {
      isFindingDriver = true;
      notifyListeners();

      _processedCompletedRideId = null;

      String rideId = await _rideRequestProvider.createRideRequest(
        pickup: pickupLocation!,
        pickupAddressName: pickupController.text,
        dropoff: dropOffLocation!,
        estimatedDistanceText: selectedRouteDistance,
        estimatedFare: estimatedFare,
        estimatedDurationText: selectedRouteDuration,
        dropoffAddressName: destinationController.text,
        customerNote: customerNoteController.text.trim(),
        stops: stops.map((s) => {
          'name': s.name,
          'location': s.location!,
          'addressName': s.controller.text,
        }).toList(),
      );

      activeRideRequestId = rideId;
      isFindingDriver = true;
      _listenToActiveRide(rideId);
    } catch (e) {
      onUiAction?.call(UiAction('${AppLocale.failedToCreateRideRequest.getString(_context)}: $e', isError: true));
      isFindingDriver = false;
      activeRideRequestId = null;
    }
    notifyListeners();
  }

  Future<void> cancelRideRequest() async {
    if (activeRideRequestId != null) {
      try {
        await _rideRequestProvider.cancelRideByCustomer(activeRideRequestId!);
      } catch (e) {
        onUiAction?.call(UiAction('Failed to cancel ride: $e', isError: true));
      }
    } else {
      onUiAction?.call(UiAction(AppLocale.cannotCancelRide.getString(_context), isError: true));
    }
  }

  Future<void> updateCustomerNote(String rideId, String note) async {
    try {
      await _rideRequestProvider.updateCustomerNote(rideId, note);
      onUiAction?.call(UiAction(AppLocale.noteUpdated.getString(_context)));
    } catch (e) {
      onUiAction?.call(UiAction(AppLocale.failedToUpdateNote.getString(_context), isError: true));
    }
  }

  Future<void> saveScheduledRide({
    required String title,
    required DateTime scheduledDateTime,
    required bool isRecurring,
    required String recurrenceType,
    required List<bool> selectedRecurrenceDays,
    required DateTime? recurrenceEndDate,
    required List<String> dayAbbreviations,
  }) async {
    final String? customerId = _rideRequestProvider.authService.currentUser?.uid;
    if (customerId == null) {
      onUiAction?.call(UiAction(AppLocale.userNotAuthenticated.getString(_context), isError: true));
      return;
    }

    try {
      final rideData = {
        'customerId': customerId,
        'title': title,
        'scheduledDateTime': Timestamp.fromDate(scheduledDateTime),
        'createdAt': FieldValue.serverTimestamp(),
        'pickup': GeoPoint(pickupLocation!.latitude, pickupLocation!.longitude),
        'dropoff': GeoPoint(dropOffLocation!.latitude, dropOffLocation!.longitude),
        'pickupAddressName': pickupController.text,
        'dropoffAddressName': destinationController.text,
        'status': 'scheduled',
        'isRecurring': isRecurring,
        'recurrenceType': isRecurring ? recurrenceType : null,
        'recurrenceDaysOfWeek': isRecurring && recurrenceType == 'Weekly'
            ? selectedRecurrenceDays.asMap().entries.where((e) => e.value).map((e) => dayAbbreviations[e.key]).toList()
            : null,
        'recurrenceEndDate': isRecurring && recurrenceEndDate != null ? Timestamp.fromDate(recurrenceEndDate) : null,
        'stops': stops.map((stop) => {
          'name': stop.name,
          'location': stop.location != null ? GeoPoint(stop.location!.latitude, stop.location!.longitude) : null,
          'addressName': stop.controller.text,
        }).toList(),
      };

      await FirebaseFirestore.instance.collection('scheduledRides').add(rideData);
      onUiAction?.call(UiAction(AppLocale.rideScheduledSuccessfully.getString(_context)));
      onUiAction?.call(UiAction('show_post_schedule_dialog'));
    } catch (e) {
      onUiAction?.call(UiAction('${AppLocale.failedToScheduleRide.getString(_context)}: $e', isError: true));
    }
  }

  Future<void> rateDriver(String rideId, String driverId, double rating, String? comment) async {
    try {
      await _rideRequestProvider.rateUser(
        rideId: rideId,
        ratedUserId: driverId,
        ratedUserRole: 'Driver',
        rating: rating,
        comment: comment,
      );
      onUiAction?.call(UiAction(AppLocale.ratingSubmitted.getString(_context)));
    } catch (e) {
      onUiAction?.call(UiAction('${AppLocale.failedToSubmitRating.getString(_context)} $e', isError: true));
    }
  }

  void resetUIForNewTrip() {
    pickupController.clear();
    destinationController.clear();
    stops.forEach((stop) => stop.controller.clear());
    stops.clear();

    pickupLocation = null;
    dropOffLocation = null;

    _markers.clear();
    polylines.clear();

    selectedRouteDistance = null;
    selectedRouteDuration = null;
    estimatedFare = null;
    routeReady = false;

    pickupSuggestions = [];
    destinationSuggestions = [];
    stopSuggestions = [];

    editingPickup = false;
    editingDestination = true;
    editingStopIndex = null;

    activeRideRequestId = null;
    activeRideRequestDetails = null;
    assignedDriverModel = null;
    isFindingDriver = false;
    _stopListeningToActiveRide();
    _stopListeningToDriverLocation();

    _kijiweFetchInitiated = false;
    setupInitialMapState();
    notifyListeners();
  }

  String getRideEndMessage(String? status) {
    switch (status) {
      case 'completed': return AppLocale.rideCompleted.getString(_context);
      case 'cancelled_by_customer': return AppLocale.rideCancelledByYou.getString(_context);
      case 'cancelled_by_driver': return AppLocale.rideCancelledByDriver.getString(_context);
      case 'no_drivers_available': return AppLocale.noDriverAvailable.getString(_context);
      case 'matching_error_missing_pickup': return AppLocale.matchingErrorMissingPickup.getString(_context);
      case 'matching_error_kijiwe_fetch': return AppLocale.matchingErrorKijiweFetch.getString(_context);
      default: return AppLocale.rideHasEnded.getString(_context);
    }
  }

  Future<void> centerMapOnCurrentLocation() async {
    if (mapController == null) return;
    final targetLocation = pickupLocation ?? _locationProvider.currentLocation;

    if (targetLocation == null) {
      onUiAction?.call(UiAction(AppLocale.currentLocationNotAvailable.getString(_context), isError: true));
      return;
    }

    final currentZoom = await mapController!.getZoomLevel();
    mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(targetLocation.latitude, targetLocation.longitude), zoom: currentZoom, bearing: 0),
      ),
    );
  }

  void resetActiveRideStateOnly() {
    activeRideRequestId = null;
    activeRideRequestDetails = null;
    assignedDriverModel = null;
    isFindingDriver = false;
    _stopListeningToActiveRide();
    _stopListeningToDriverLocation();
    polylines.clear();
    _markers.removeWhere((m) => m.markerId.value == 'driver_active_location');
    routeReady = false;
    estimatedFare = null;
    notifyListeners();
  }

  void _stopListeningToActiveRide() {
    _activeRideSubscription?.cancel();
    _activeRideSubscription = null;
  }

  @override
  void dispose() {
    _locationProvider.removeListener(_onLocationUpdated);
    pickupController.dispose();
    destinationController.dispose();
    customerNoteController.dispose();
    _driverLocationSubscription?.cancel();
    _kijiweSubscription?.cancel();
    _stopListeningToActiveRide();
    for (var stop in stops) {
      stop.dispose();
    }
    super.dispose();
  }
}