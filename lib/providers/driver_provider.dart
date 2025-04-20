import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';


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
    try {
      // Simulate API call - replace with your actual backend call
      await Future.delayed(Duration(milliseconds: 300));
      
      _isOnline = !_isOnline;
      if (_isOnline) {
        // Start listening for ride requests
        if (_currentKijiweId != null) {
          _listenForRideRequests(context, _currentKijiweId!);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Kijiwe ID is not set')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to toggle status: ${e.toString()}')),
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Check if the user is already online
  void _listenForRideRequests(BuildContext context, String kijiweId) async {
  final userId = _authService.currentUser?.uid;
    if (userId == null) return;
    try {
      _isOnline = !_isOnline;
      notifyListeners();

      await _firestoreService.updateDriverStatus(
        userId: userId,
        available: _isOnline,
        kijiweId: kijiweId,
      );

      if (_isOnline) {
        await _firestoreService.joinKijiweQueue(kijiweId, userId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You are now online and in the Kijiwe queue')),
        );
      } else {
        await _firestoreService.leaveKijiweQueue(kijiweId, userId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You are now offline')),
        );
      }
    } catch (e) {
      _isOnline = !_isOnline; // Revert on error
      notifyListeners();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error changing status: $e')),
      );
    }
  }

  Future<void> registerAsDriver({
    required BuildContext context,
    required String vehicleType,
    required String licenseNumber,
    required String kijiweId,
    required String userId,
  }) async {
    final userId = _authService.currentUser?.uid;
    if (userId == null) return;

    try {
      await _firestoreService.registerAsDriver(
        userId: userId,
        vehicleType: vehicleType,
        licenseNumber: licenseNumber,
        kijiweId: kijiweId,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully registered as driver')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error registering: $e')),
      );
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