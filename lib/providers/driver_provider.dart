import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../screens/home_screen.dart'; // Import HomeScreen
import 'package:cloud_firestore/cloud_firestore.dart';


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

  Future<void> toggleOnlineStatus(BuildContext context) async {
    setLoading(true);
    try {
      final newOnlineStatus = !_isOnline;

      if (newOnlineStatus && _currentKijiweId == null) {
        // Can't go online without a Kijiwe ID
        // No change to _isOnline, just show message and stop loading
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kijiwe ID is not set. Cannot go online.')),
          );
        }
        setLoading(false);
        return;
      }

      // Optimistically update the local state for immediate UI feedback
      final originalOnlineStatus = _isOnline;
      _isOnline = newOnlineStatus;
      notifyListeners();

      // Perform Firestore operations
      // If going online, _currentKijiweId must be non-null (checked above)
      // If going offline, _currentKijiweId is needed to leave the queue correctly
      if (_currentKijiweId != null) {
        await _updateFirestoreAndQueueForOnlineStatus(context, newOnlineStatus, _currentKijiweId!);
      } else if (!newOnlineStatus) {
        // This case implies going offline when _currentKijiweId was already null.
        // This might indicate a previous state inconsistency, but we ensure offline status.
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You are now offline.')),
          );
        }
      }
    } catch (e) {
      _isOnline = !_isOnline; // Revert optimistic update on error
      notifyListeners();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to toggle status: ${e.toString()}')),
        );
      }
    } finally {
      setLoading(false);
    }
  }

  // Renamed and refactored internal method to handle Firestore updates for online status
  Future<void> _updateFirestoreAndQueueForOnlineStatus(
    BuildContext context,
    bool newStatus,
    String kijiweId,
  ) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) {
      throw Exception('User not authenticated. Cannot update online status.');
    }

    try {
      await _firestoreService.updateDriverStatus(
        userId: userId,
        available: newStatus,
        kijiweId: kijiweId,
      );

      if (newStatus) {
        await _firestoreService.joinKijiweQueue(kijiweId, userId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You are now online and in the Kijiwe queue.')),
          );
        }
      } else {
        await _firestoreService.leaveKijiweQueue(kijiweId, userId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You are now offline.')),
          );
        }
      }
    } catch (e) {
      // The calling method (toggleOnlineStatus) will handle reverting _isOnline state.
      debugPrint('Error in _updateFirestoreAndQueueForOnlineStatus: $e');
      throw Exception('Failed to update status in Firestore: $e'); // Re-throw to be caught by caller
    }
  }

  Future<void> registerAsDriver({
  required BuildContext context,
  required String userId,
  required String vehicleType,
  required String licenseNumber,
  // Kijiwe parameters:
  // If createNewKijiwe is true, newKijiweName and newKijiweLocation must be provided.
  // Otherwise, existingKijiweId must be provided.
  required final bool createNewKijiwe,
  final String? newKijiweName,
  final LatLng? newKijiweLocation,
  final String? existingKijiweId,
}) async {
  setLoading(true);
  try {
    final firestore = FirebaseFirestore.instance;
    String kijiweIdToUse;
    String kijiweNameToDisplay = "";

    if (createNewKijiwe) {
      if (newKijiweName == null || newKijiweName.trim().isEmpty || newKijiweLocation == null) {
        throw ArgumentError("New Kijiwe name and location are required when creating a new Kijiwe.");
      }
      // Create the new Kijiwe
      final newKijiweDocRef = firestore.collection('kijiwe').doc();
      await newKijiweDocRef.set({
        'name': newKijiweName.trim(),
        'location': GeoPoint(newKijiweLocation.latitude, newKijiweLocation.longitude),
        'unionId': null, // As per your example structure
        'adminId': userId, // The driver creating it becomes the admin
        'permanentMembers': [userId], // Driver is the first permanent member
        'createdAt': FieldValue.serverTimestamp(),
      });
      kijiweIdToUse = newKijiweDocRef.id;
      kijiweNameToDisplay = newKijiweName.trim();
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
    };

    // 2. Update user document: set role to 'Driver' and add/update driverProfile
    await firestore.collection('users').doc(userId).update({
      'role': 'Driver', // Capitalized as requested
      'driverProfile': driverProfilePayload,
    });

    // 3. Add driver to the selected kijiwe's permanent members list (if not already added during creation)
    // FieldValue.arrayUnion is idempotent, so it's safe to call even if userId is already there.
    if (!createNewKijiwe) { // Only needed if selecting an existing Kijiwe
      await kijiweRef.update({
        'permanentMembers': FieldValue.arrayUnion([userId]),
      });
    }

    // 4. Add to kijiwe queue if 'isOnline' is true in their profile
    // (We've set it to true in driverProfilePayload)
    if (driverProfilePayload['isOnline'] == true) {
      await kijiweRef.collection('queue').doc(userId).set({
        'driverId': userId,
        'timestamp': FieldValue.serverTimestamp(),
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
    try {
      // Example:
      // await ApiService.updateDriverPosition(position);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to update position: $e');
    }
  }

  Future<void> acceptRideRequest(String rideId) async {
    try {
      // await ApiService.acceptRide(rideId);
      // Update your provider state
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to accept ride: $e');
    }
  }

  Future<void> declineRideRequest(String rideId) async {
    try {
      // await ApiService.declineRide(rideId);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to decline ride: $e');
    }
  }

  Future<void> confirmArrival(String rideId) async {
    try {
      // await ApiService.confirmArrival(rideId);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to confirm arrival: $e');
    }
  }

  Future<void> startRide(String rideId) async {
    try {
      // await ApiService.startRide(rideId);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to start ride: $e');
    }
  }

  Future<void> completeRide(String rideId) async {
    try {
      // await ApiService.completeRide(rideId);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to complete ride: $e');
    }
  }

  Future<void> cancelRide(String rideId) async {
    try {
      // await ApiService.cancelRide(rideId);
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to cancel ride: $e');
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
  
}