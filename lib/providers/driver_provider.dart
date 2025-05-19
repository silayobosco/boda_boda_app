import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../screens/home_screen.dart'; // Import HomeScreen
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart'; // Import geoflutterfire3
import 'package:latlong2/latlong.dart' as latlong2; // Import for latlong2.LatLng

class DriverProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  bool _isOnline = false;
  String? _currentKijiweId;
  bool _isLoading = false;

  bool get isLoading => _isLoading;
  bool get isOnline => _isOnline;
  String? get currentKijiweId => _currentKijiweId;

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<void> loadDriverData() async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      _isOnline = false;
      _currentKijiweId = null;
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
        } else { // Driver profile doesn't exist
          _isOnline = false;
          _currentKijiweId = null;
        }
      } else { // User document doesn't exist
        _isOnline = false;
        _currentKijiweId = null;
      }
    } catch (e) {
      debugPrint("Error loading driver data: $e");
      _isOnline = false; // Reset on error
      _currentKijiweId = null;
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
      GeoPoint geoPoint = GeoPoint(newKijiweLocation.latitude, newKijiweLocation.longitude);
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
      'approved': true,
      'isOnline': true, // Driver will be online and in queue immediately
      'status': 'waitingForRide', // Initial status when registering and going online
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

  Future<void> updateDriverPosition(LatLng position) async {
    // Implement your backend API call to update driver position
    final userId = _authService.currentUser?.uid;
    if (userId == null) return;
    try {
      // Convert google_maps_flutter.LatLng to latlong2.LatLng
      final latlong2Position = latlong2.LatLng(
        position.latitude,
        position.longitude,
      );
      await _firestoreService.updateUserLocation(userId, latlong2Position);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to update position: $e');
    }
  }

  Future<void> acceptRideRequest(String rideId, String customerId) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) throw Exception('Driver not logged in');
    setLoading(true);
    try {
      // Update RideRequest status in Firestore (via RideRequestProvider or directly if simpler for now)
      await _updateDriverProfileInFirestore( // Call internal method
        userId: userId,
        isOnline: true, // Still online
        statusString: "goingToPickup",
      );
      // Remove driver from Kijiwe queue as they are now on a ride
      if (_currentKijiweId != null) {
        await _firestoreService.leaveKijiweQueue(_currentKijiweId!, userId);
      }
      // Update the ride request status in Firestore
      await _firestoreService.updateRideRequestStatus(
        rideId,
        'accepted',
        driverId: userId,
      );
      // Potentially update local state if needed for UI
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to accept ride: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> declineRideRequest(String rideId, String customerId) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) throw Exception('Driver not logged in');
    setLoading(true);
    try {
      // Update RideRequest status in Firestore (via RideRequestProvider or directly if simpler for now)
      await _firestoreService.updateRideRequestStatus(
        rideId,
        'declined',
        driverId: userId,
      );
      // Potentially update local state if needed for UI
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to decline ride: $e');
    } finally {
      setLoading(false);
    }
  }

  // Confirm arrival at pickup location
  Future<void> confirmArrival(String rideId, String customerId) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) throw Exception('Driver not logged in');
    setLoading(true);
    try {
      await _updateDriverProfileInFirestore( // Call internal method
        userId: userId,
        isOnline: true, // Still online
        statusString: "arrivedAtPickup",
      );
      // Update the ride request status in Firestore
      await _firestoreService.updateRideRequestStatus(
        rideId,
        'arrivedAtPickup',
        driverId: userId,
      );
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to confirm arrival: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> startRide(String rideId, String customerId) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) throw Exception('Driver not logged in');
    setLoading(true);
    try {
      await _updateDriverProfileInFirestore( // Call internal method
        userId: userId,
        isOnline: true, // Still online
        statusString: "onRide",
      );
      // Update the ride request status in Firestore
      await _firestoreService.updateRideRequestStatus(
        rideId,
        'onRide',
        driverId: userId,
      );
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to start ride: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> completeRide(String rideId, String customerId) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) throw Exception('Driver not logged in');
    setLoading(true);
    try {
      await _updateDriverProfileInFirestore( // Call internal method
        userId: userId,
        isOnline: true, // Still online, ready for next ride
        statusString: "waitingForRide", // Or "returningToKijiwe" then "waitingForRide"
      );
      // Update the ride request status in Firestore
      await _firestoreService.updateRideRequestStatus(
        rideId,
        'completed',
        driverId: userId,
      );
      // Optionally, update the ride document with a completion time separately:
      await FirebaseFirestore.instance.collection('rideRequests').doc(rideId).update({
        'completedAt': FieldValue.serverTimestamp(),
      });      
      // Optionally, you might want to update the driver's earnings or other metrics
      // For example, you could update a 'totalEarnings' field in the driver profile
      // Optionally, you might want to update the ride history or other related data
      // For example, you could create a ride history entry here
      // Increment completedRides
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'driverProfile.completedRides': FieldValue.increment(1),
      });
      // If driver is still online and kijiweId is set, add them back to the queue
      if (_isOnline && _currentKijiweId != null) {
        await _firestoreService.joinKijiweQueue(_currentKijiweId!, userId);
      }
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to complete ride: $e');
    } finally {
      setLoading(false);
    }
  }

  Future<void> rateRide(String rideId, double rating) async {
    try {
      // await ApiService.rateRide(rideId, rating);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to rate ride: $e');
    }
  }

  Future<void> cancelRide(String rideId, String customerId) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) throw Exception('Driver not logged in');
    setLoading(true);
    try {
      // Update driver's status back to available or as appropriate
      await _updateDriverProfileInFirestore( // Call internal method
        userId: userId,
        isOnline: true, // Still online
        statusString: "waitingForRide",
      );
      // Update the ride request status in Firestore
      await _firestoreService.updateRideRequestStatus(
        rideId,
        'cancelled',
        driverId: userId,
      );
      // If driver is still online and kijiweId is set, add them back to the queue
      if (_isOnline && _currentKijiweId != null) {
        await _firestoreService.joinKijiweQueue(_currentKijiweId!, userId);
      }
      // send notification to customer
      // await ApiService.sendNotificationToCustomer(customerId, "Ride Cancelled", "Your ride has been cancelled by the driver.");
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to cancel ride: $e');
    } finally {
      setLoading(false);
    }
  }
}