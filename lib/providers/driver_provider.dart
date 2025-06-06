import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../screens/home_screen.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart';  
import 'package:cloud_functions/cloud_functions.dart'; 

class DriverProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  // RideRequestProvider is typically accessed via Provider.of in widgets, or passed if needed for direct calls
  bool _isOnline = false;
  String? _currentKijiweId;
  bool _isLoading = false;
  Map<String, dynamic>? _pendingRideRequestDetails;
  Map<String, dynamic>? _driverProfileData; // To store driver-specific profile data

  bool get isLoading => _isLoading;
  bool get isOnline => _isOnline;
  String? get currentKijiweId => _currentKijiweId;
  Map<String, dynamic>? get pendingRideRequestDetails => _pendingRideRequestDetails;
  Map<String, dynamic>? get driverProfileData => _driverProfileData; // Getter for driver profile

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
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
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        if (data.containsKey('driverProfile')) {
          final driverProfile = data['driverProfile'] as Map<String, dynamic>;
          _isOnline = driverProfile['isOnline'] ?? false;
          _currentKijiweId = driverProfile['kijiweId'] as String?;
          _driverProfileData = Map<String, dynamic>.from(driverProfile); // Store the profile
        } else { // Driver profile doesn't exist
          _isOnline = false;
          _currentKijiweId = null;
          _driverProfileData = null;
        }
      } else { // User document doesn't exist
        _isOnline = false;
        _currentKijiweId = null;
        _driverProfileData = null;
      }
    } catch (e) {
      debugPrint("Error loading driver data: $e");
      _isOnline = false; // Reset on error
      _currentKijiweId = null;
      _driverProfileData = null;
    } finally {
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
  required BuildContext context,
  required String userId,
  required String vehicleType,
  required String licenseNumber,
  required final bool createNewKijiwe,
  final String? newKijiweName,
  final LatLng? newKijiweLocation,
  final String? existingKijiweId,
}) async {
  setLoading(true);
  try {
    final firestore = FirebaseFirestore.instance;
    final geo = GeoFlutterFire(); 
    String kijiweIdToUse;
    String kijiweNameToDisplay = "";

    if (createNewKijiwe) {
      if (newKijiweName == null || newKijiweName.trim().isEmpty || newKijiweLocation == null) {
        throw ArgumentError("New Kijiwe name and location are required when creating a new Kijiwe.");
      }

      // Check for Kijiwe name uniqueness
      final trimmedKijiweName = newKijiweName.trim();
      final existingKijiweQuery = await firestore.collection('kijiwe').where('name', isEqualTo: trimmedKijiweName).limit(1).get();
      if (existingKijiweQuery.docs.isNotEmpty) {
        throw Exception("A Kijiwe with the name '$trimmedKijiweName' already exists. Please choose a different name or select the existing one.");
      }

      // Create GeoPoint for GeoFlutterFire
      GeoFirePoint geoFirePoint = geo.point(latitude: newKijiweLocation.latitude, longitude: newKijiweLocation.longitude);

      // Create the new Kijiwe
      final newKijiweDocRef = firestore.collection('kijiwe').doc();
      await newKijiweDocRef.set({
        'name': trimmedKijiweName,
        'position': geoFirePoint.data, // Store geohash and geopoint
        'unionId': null, // As per your example structure
        'adminId': userId, // The driver creating it becomes the admin
        'permanentMembers': [userId], // Driver is the first permanent member
        'createdAt': FieldValue.serverTimestamp(),
      });
      kijiweIdToUse = newKijiweDocRef.id;
      kijiweNameToDisplay = trimmedKijiweName;
    } else {
      if (existingKijiweId == null) {
        throw ArgumentError("Existing Kijiwe ID is required when not creating a new Kijiwe.");
      }
      kijiweIdToUse = existingKijiweId;
      // You might want to fetch the Kijiwe name here if needed for the success message,
      // but for simplicity, we'll omit that for now.
    }
    final kijiweRef = firestore.collection('kijiwe').doc(kijiweIdToUse);

    // 1. Prepare driverProfile data
    // Driver is immediately 'approved'.
    // 'isOnline' is set to true, so they will be added to the queue.
    Map<String, dynamic> driverProfilePayload = {
      'driverId': userId,
      'vehicleType': vehicleType,
      'licenseNumber': licenseNumber,
      'kijiweId': kijiweIdToUse,
      'registeredAt': FieldValue.serverTimestamp(),
      'approved': true, // Driver is immediately 'approved'.
      'isOnline': true, // Driver will be online and in queue immediately
      'status': 'waitingForRide', // Initial status when registering and going online
      // Initialize new counter fields
      'completedRidesCount': 0,
      'cancelledByDriverCount': 0,
      'declinedByDriverCount': 0,
      'sumOfRatingsReceived': 0,
      'totalRatingsReceivedCount': 0,
      'averageRating': 0.0, // Or null, depending on how you want to handle no ratings
    };

    // 2. Update user document: set role to 'Driver' and add/update driverProfile
    await firestore.collection('users').doc(userId).update({
      'role': 'Driver', // Capitalized as requested
      'driverProfile': driverProfilePayload,
    });

    // Update provider's internal state immediately after successful registration
    _currentKijiweId = kijiweIdToUse;
    _isOnline = driverProfilePayload['isOnline'] ?? false;

    // 3. Add driver to the selected kijiwe's permanent members list (if not already added during creation)
    // FieldValue.arrayUnion is idempotent, so it's safe to call even if userId is already there.
    if (!createNewKijiwe) { // Only needed if selecting an existing Kijiwe
      await kijiweRef.update({
        'permanentMembers': FieldValue.arrayUnion([userId]),
      });
    }

    // 4. Add to kijiwe queue if 'isOnline' is true in their profile
    // (We've set it to true in driverProfilePayload)
    // The driver is added to an array field (e.g., 'ueues') in the Kijiwe document.
    if (driverProfilePayload['isOnline'] == true) { // Queue is now an array of strings
      await kijiweRef.update({
        'queue': FieldValue.arrayUnion([userId])
      });
    }

    if (context.mounted) {
      String successMessage = "Registration successful! You are now a Driver.";
      if (createNewKijiwe) {
        successMessage += " Kijiwe '$kijiweNameToDisplay' created.";
      }
      if (driverProfilePayload['isOnline'] == true) {
        successMessage += " You have been added to the Kijiwe queue.";
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      // Navigate to HomeScreen after successful registration
      // Using pushReplacement to prevent going back to the registration screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  } catch (e) {
    debugPrint('Driver registration failed: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: ${e.toString()}')),
      );
    }
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
}