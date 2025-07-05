import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart'; 
import 'dart:math';

class DriverProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  // RideRequestProvider is typically accessed via Provider.of in widgets, or passed if needed for direct calls
  bool _isOnline = false;
  String? _currentKijiweId;
  bool _isLoading = false;
  double _dailyEarnings = 0.0; // New field for daily earnings
  Map<String, dynamic>? _pendingRideRequestDetails;
  Map<String, dynamic>? _driverProfileData; // To store driver-specific profile data
  Map<String, dynamic>? _fareConfig; // To store fare configuration from Firestore

  bool get isLoading => _isLoading;
  bool get isOnline => _isOnline;
  String? get currentKijiweId => _currentKijiweId;
  Map<String, dynamic>? get pendingRideRequestDetails => _pendingRideRequestDetails;
  double get dailyEarnings => _dailyEarnings; // Getter for daily earnings
  Map<String, dynamic>? get driverProfileData => _driverProfileData; // Getter for driver profile

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<void> _fetchFareConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('appConfiguration')
          .doc('fareSettings')
          .get();

      if (doc.exists && doc.data() != null) {
        _fareConfig = doc.data();
        debugPrint("DriverProvider: Fare config loaded successfully: $_fareConfig");
      } else {
        debugPrint("DriverProvider: 'fareSettings' document does not exist. Using fallback fare calculation.");
        _fareConfig = null;
      }
    } catch (e) {
      debugPrint("DriverProvider: ERROR fetching fare config: $e. Using fallback fare calculation.");
      _fareConfig = null;
    }
  }

  Future<void> loadDriverData() async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      _isOnline = false;
      _currentKijiweId = null;
      _driverProfileData = null;
      // No setLoading needed if returning early, but notify for UI consistency
      notifyListeners();
      return;
    }
    setLoading(true);
    try {
      // Fetch fare config and user data in parallel for efficiency
      await Future.wait([
        _fetchFareConfig(),
        FirebaseFirestore.instance.collection('users').doc(userId).get().then((userDoc) {
          if (userDoc.exists && userDoc.data() != null) {
            final data = userDoc.data() as Map<String, dynamic>;
            if (data.containsKey('driverProfile')) {
              final driverProfile = data['driverProfile'] as Map<String, dynamic>;
              _isOnline = driverProfile['isOnline'] ?? false;
              _currentKijiweId = driverProfile['kijiweId'] as String?;
              _driverProfileData = Map<String, dynamic>.from(driverProfile); // Store the profile
            } else { // Driver profile doesn't exist
              debugPrint("DriverProvider: Driver profile not found for user $userId.");
              _isOnline = false;
              _currentKijiweId = null;
              _driverProfileData = null;
            }
          } else { // User document doesn't exist
            _isOnline = false;
            _currentKijiweId = null;
            _driverProfileData = null; // Ensure profile is null if user doc doesn't exist
          }
        })
      ]);
    } catch (e) {
      debugPrint("Error loading driver data: $e");
      _isOnline = false; // Reset on error
      _currentKijiweId = null;
      _driverProfileData = null;
    } finally {
      // Fetch daily earnings after loading driver data
      try {
        _dailyEarnings = await _firestoreService.getDriverDailyEarnings(userId);
        debugPrint("DriverProvider: Fetched daily earnings: $_dailyEarnings");
      } catch (e) {
        debugPrint("DriverProvider: Error fetching daily earnings: $e");
        _dailyEarnings = 0.0; // Reset on error
      }
          setLoading(false); // This will also call notifyListeners()
    }
  }

  Future<String?> toggleOnlineStatus() async {
    setLoading(true);
    final userId = _authService.currentUser?.uid;

    if (userId == null) {
      setLoading(false);
      return 'User not authenticated. Cannot toggle status.';
    }

    final newOnlineStatus = !_isOnline;

    // Prevent going ONLINE if Kijiwe ID is not set.
    if (newOnlineStatus && _currentKijiweId == null) {
      setLoading(false); // Stop loading as we are returning.
      return 'Kijiwe ID is not set. Cannot go online.';
    }

    // Optimistically update UI
    _isOnline = newOnlineStatus;
    notifyListeners();

    try {
      // 1. Always update driverProfile's isOnline and status in Firestore.
      await _updateDriverProfileInFirestore(
        userId: userId,
        isOnline: newOnlineStatus,
        statusString: newOnlineStatus ? "waitingForRide" : "offline",
        // kijiweId in driverProfile is only associated when going online with a specific kijiwe.
        // It's not cleared from driverProfile by this toggle when going offline.
        kijiweId: (newOnlineStatus && _currentKijiweId != null) ? _currentKijiweId : null,
      );

      // 2. Update KijiweQueues (join or leave) only if _currentKijiweId is available.
      if (_currentKijiweId != null) {
        if (newOnlineStatus) {
          await _firestoreService.joinKijiweQueue(_currentKijiweId!, userId);
        } else {
          await _firestoreService.leaveKijiweQueue(_currentKijiweId!, userId);
        }
      }

      // Success
      setLoading(false);
      return null; // Indicates success
    } catch (e) {
      // Revert optimistic UI update on failure
      _isOnline = !newOnlineStatus; // Revert to previous state
      notifyListeners();
      setLoading(false);
      return 'Failed to toggle status: ${e.toString()}';
    }
  }

  // method to handle direct Firestore updates for driver profile status
  Future<void> _updateDriverProfileInFirestore({
    required String userId,
    required bool isOnline,
    String? statusString,
    String? kijiweId, // Optional, only needed when going online
  // This is the Kijiwe ID the driver is joining or leaving
  }) async {
    // Use dot notation to update specific fields within the driverProfile map
    final Map<String, dynamic> updateData = {};
    updateData['driverProfile.isOnline'] = isOnline;
    if (statusString != null) {
      updateData['driverProfile.status'] = statusString;
    }
    // Only update kijiweId if it's explicitly provided (e.g., when going online or changing kijiwe)
    // When going offline, kijiweId in profile should typically remain.
    if (kijiweId != null) {
      updateData['driverProfile.kijiweId'] = kijiweId;
    };

    if (updateData.isNotEmpty) {
      await FirebaseFirestore.instance.collection('users').doc(userId).update(updateData);
    }
  }

  Future<void> registerAsDriver({
    required String userId,
    required String vehicleType,
    required String licenseNumber,
    required final bool createNewKijiwe,
    final String? newKijiweName,
    final LatLng? newKijiweLocation,
    final String? existingKijiweId,
    final String? profileImageUrl,
  }) async {
    setLoading(true);
    try {
      final kijiweIdToUse = await _firestoreService.registerDriver(
        userId: userId,
        vehicleType: vehicleType,
        licenseNumber: licenseNumber,
        createNewKijiwe: createNewKijiwe,
        newKijiweName: newKijiweName,
        newKijiweLocation: newKijiweLocation,
        existingKijiweId: existingKijiweId,
        profileImageUrl: profileImageUrl,
      );

      // Update provider's internal state immediately after successful registration
      _currentKijiweId = kijiweIdToUse;
      _isOnline = true; // The service registers the driver as online by default
      await loadDriverData(); // Re-fetch profile data to update the local cache
    } catch (e) {
      debugPrint('DriverProvider: Registration failed, rethrowing... $e');
      rethrow; // Rethrow the exception for the UI to handle
    } finally {
      setLoading(false);
    }
  }

  // Method to set new pending ride details from FCM
  void setNewPendingRide(Map<String, dynamic> rideData) {
    // Only set as pending if it's a new request meant for driver acceptance
    final status = rideData['status'] as String?;
    if (status == 'pending_driver_acceptance') {
      _pendingRideRequestDetails = rideData;
      notifyListeners();
    } else {
      // If it's an update for an existing ride (e.g., completed, cancelled) or not a new offer,
      // do not treat it as a new pending request.
      debugPrint("DriverProvider: Received ride data with status '$status', not setting as new pending ride.");
    }  }

  // Method to clear pending ride details
  void clearPendingRide() {
    _pendingRideRequestDetails = null;
    notifyListeners();
  }

  Future<void> updateDriverPosition(LatLng position, double? heading) async {
    // Implement your backend API call to update driver position
    final userId = _authService.currentUser?.uid;
    if (userId == null) return;
    try {
      await _firestoreService.updateDriverActiveLocation(
        userId,
        position, // Pass the LatLng object directly
        heading,
      );
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to update position: $e');
    }
  }

  // Context is needed if you plan to show SnackBars or navigate from here
  Future<void> acceptRideRequest(BuildContext context, String rideId, String customerId) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      throw Exception('Driver not logged in');
    }
    setLoading(true);
    try {
      HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('handleDriverRideAction');
      final result = await callable.call(<String, dynamic>{
        'rideRequestId': rideId,
        'action': 'accept',
        // customerId is implicitly known by the backend via rideId
      });
      debugPrint("Cloud function 'acceptRide' result: ${result.data}");

      clearPendingRide(); // Clear the request from the UI
      notifyListeners();
    } catch (e) {
      debugPrint('Error calling handleDriverRideAction (accept): $e');
      if (e is FirebaseFunctionsException) {
        throw Exception('Failed to accept ride: ${e.message}');
      }
      throw Exception('Failed to accept ride: ${e.toString()}');
    } finally {
      setLoading(false);
    }
  }

  Future<void> declineRideRequest(BuildContext context, String rideId, String customerId) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      throw Exception('Driver not logged in');
    }
    setLoading(true);
    try {
      HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('handleDriverRideAction');
      final result = await callable.call(<String, dynamic>{
        'rideRequestId': rideId,
        'action': 'decline',
      });
      debugPrint("Cloud function 'declineRide' result: ${result.data}");

      clearPendingRide(); // Clear the request from the UI
      notifyListeners();
    } catch (e) {
      debugPrint('Error calling handleDriverRideAction (decline): $e');
      if (e is FirebaseFunctionsException) {
        throw Exception('Failed to decline ride: ${e.message}');
      }
      throw Exception('Failed to decline ride: ${e.toString()}');
    } finally {
      setLoading(false);
    }
  }

  // Confirm arrival at pickup location
  Future<void> confirmArrival(BuildContext context, String rideId, String customerId) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      throw Exception('Driver not logged in');
    }
    setLoading(true);
    try {
      HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('handleDriverRideAction');
      final result = await callable.call(<String, dynamic>{
        'rideRequestId': rideId,
        'action': 'arrivedAtPickup',
      });
      debugPrint("Cloud function 'arrivedAtPickup' result: ${result.data}");
      // UI updates will come from Firestore stream listener for the ride request
      notifyListeners(); // Notify for isLoading state change
    } catch (e) {
      debugPrint('Error calling handleDriverRideAction (arrivedAtPickup): $e');
      if (e is FirebaseFunctionsException) {
        throw Exception('Failed to confirm arrival: ${e.message}');
      }
      throw Exception('Failed to confirm arrival: ${e.toString()}');
    } finally {
      setLoading(false);
    }
  }

  Future<void> startRide(BuildContext context, String rideId, String customerId) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      throw Exception('Driver not logged in');
    }
    setLoading(true);
    try {
      HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('handleDriverRideAction');
      final result = await callable.call(<String, dynamic>{
        'rideRequestId': rideId,
        'action': 'startRide',
      });
      debugPrint("Cloud function 'startRide' result: ${result.data}");
      notifyListeners();
    } catch (e) {
      debugPrint('Error calling handleDriverRideAction (startRide): $e');
      if (e is FirebaseFunctionsException) {
        throw Exception('Failed to start ride: ${e.message}');
      }
      throw Exception('Failed to start ride: ${e.toString()}');
    } finally {
      setLoading(false);
    }
  }

  Future<void> completeRide(
    BuildContext context,
    String rideId,
    String customerId, {
    double? actualDistanceKm,
    double? actualDrivingDurationMinutes,
    double? actualTotalWaitingTimeMinutes, // Placeholder for future implementation
  }) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      throw Exception('Driver not logged in');
    }
    setLoading(true);
    try {
      HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('handleDriverRideAction');
      // Define callableData before use
      final Map<String, dynamic> callableData = {
        'rideRequestId': rideId,
        'action': 'completeRide',
        // customerId is implicitly known by the backend via rideId
      };

      // Pass actual tracking data to the Cloud Function
      if (actualDistanceKm != null) callableData['actualDistanceKm'] = actualDistanceKm;
      if (actualDrivingDurationMinutes != null) callableData['actualDrivingDurationMinutes'] = actualDrivingDurationMinutes;
      if (actualTotalWaitingTimeMinutes != null) callableData['actualTotalWaitingTimeMinutes'] = actualTotalWaitingTimeMinutes;

      final result = await callable.call(callableData); // Call with the populated data map
      debugPrint("Cloud function 'completeRide' result: ${result.data}");
      // The Cloud Function now handles updating driver's status and Kijiwe queue.
      notifyListeners();
    } catch (e) {
      debugPrint('Error calling handleDriverRideAction (completeRide): $e');
      if (e is FirebaseFunctionsException) {
        throw Exception('Failed to complete ride: ${e.message}');
      }
      throw Exception('Failed to complete ride: ${e.toString()}');
    } finally {
      setLoading(false);
    }
  }

  Future<void> rateCustomer(BuildContext context, String customerId, double rating, String rideId, {String? comment}) async {
    final driverId = _authService.currentUser?.uid;
    if (driverId == null) {
      throw Exception("Driver not authenticated to rate.");
    }
    setLoading(true);
    try {
      HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('handleDriverRideAction');
      final result = await callable.call(<String, dynamic>{
        'rideRequestId': rideId,
        'action': 'rateCustomer',
        'rating': rating, // Key should be a String literal
        'comment': comment, // Key should be a String literal
        // customerId is implicitly known by the backend via rideId
      });
      debugPrint("Cloud function 'rateCustomer' result: ${result.data}");
      notifyListeners();
    } catch (e) {
      debugPrint('Error calling handleDriverRideAction (rateCustomer): $e');
      if (e is FirebaseFunctionsException) {
        throw Exception('Failed to rate customer: ${e.message}');
      }
      throw Exception('Failed to rate customer: ${e.toString()}');
    } finally {
      setLoading(false);
    }
  }

  Future<void> cancelRide(BuildContext context, String rideId, String customerId) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      throw Exception('Driver not logged in');
    }
    setLoading(true);
    try {
      HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('handleDriverRideAction');
      final result = await callable.call(<String, dynamic>{
        'rideRequestId': rideId,
        'action': 'cancelRideByDriver',
      });
      debugPrint("Cloud function 'cancelRideByDriver' result: ${result.data}");

      // Cloud Function handles driver status and Kijiwe queue.
      notifyListeners();
    } catch (e) {
      debugPrint('Error calling handleDriverRideAction (cancelRideByDriver): $e');
      if (e is FirebaseFunctionsException) {
        throw Exception('Failed to cancel ride: ${e.message}');
      }
      throw Exception('Failed to cancel ride: ${e.toString()}');
    } finally {
      setLoading(false);
    }
  }

  /// Calculates the fare for a given distance and duration.
  /// This can be used for both estimated and final fare calculations.
  double calculateFare(
      {required double distanceMeters, required int durationSeconds}) {
    // Use fetched fare config if available, otherwise use hardcoded fallbacks.
    if (_fareConfig == null) {
      debugPrint("DriverProvider: Fare config not loaded, using fallback calculation.");
      // These values should ideally be fetched from a remote config or constants file.
      const double baseFare = 1000.0; // TZS
      const double ratePerKm = 500.0; // TZS
      const double ratePerMinute = 50.0; // TZS
      const double minimumFare = 1000.0; // TZS

      final double distanceKm = distanceMeters / 1000.0;
      final double durationMinutes = durationSeconds / 60.0;

      double calculatedFare =
          baseFare + (distanceKm * ratePerKm) + (durationMinutes * ratePerMinute);

      // Ensure the fare is not below the minimum.
      calculatedFare = max(calculatedFare, minimumFare);

      // Round to a reasonable value, e.g., nearest 50 TZS.
      return (calculatedFare / 50).round() * 50.0;
    }

    // Use values from Firestore config, with fallbacks for safety.
    final double baseFare = (_fareConfig!['startingFare'] as num?)?.toDouble() ?? 1000.0;
    final double perKmRate = (_fareConfig!['farePerKilometer'] as num?)?.toDouble() ?? 500.0;
    final double perMinRate = (_fareConfig!['farePerMinuteDriving'] as num?)?.toDouble() ?? 50.0;
    final double minFare = (_fareConfig!['minimumFare'] as num?)?.toDouble() ?? 1500.0;
    final double roundingInc = (_fareConfig!['roundingIncrement'] as num?)?.toDouble() ?? 50.0;

    final double distanceKm = distanceMeters / 1000.0;
    final double durationMinutes = durationSeconds / 60.0;

    double calculatedFare =
        baseFare + (distanceKm * perKmRate) + (durationMinutes * perMinRate);

    // Ensure the fare is not below the minimum.
    calculatedFare = max(calculatedFare, minFare);

    // Round to the specified increment.
    if (roundingInc > 0) {
      calculatedFare = (calculatedFare / roundingInc).ceil() * roundingInc;
    }

    return calculatedFare;
  }
}