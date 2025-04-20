import 'package:boda_boda/models/Ride_Request_Model.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Add this import
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import '/services/auth_service.dart';

class RideRequestProvider extends ChangeNotifier {
  final FirestoreService _firestoreService; //= FirestoreService();
  final AuthService _authService; 
  final AuthService authService = AuthService(); 
  List<RideRequestModel> _rideRequests = [];
  List<RideRequestModel> get rideRequests => _rideRequests;

  RideRequestProvider({
    required FirestoreService firestoreService,
    required AuthService authService,
  }) : _firestoreService = firestoreService,
       _authService = authService {
    _listenToRideRequests();
  }

  String? get currentUserId {
    User? user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    return user.uid;
  } else {
    return null; // No user is currently signed in
  }
  }

  void _listenToRideRequests() {
    _firestoreService.getRideRequests().listen((List<RideRequestModel> rideRequests) {
      _rideRequests = rideRequests;
      notifyListeners(); 
    });
  }

  Future<void> createRideRequest(RideRequestModel rideRequest) async {
    final currentUser = _authService.currentUser; // Get current user from AuthService
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }
    
    final updatedRequest = rideRequest.copyWith(
      customerId: currentUser.uid, // Use currentUser.uid instead of currentUserId
    );
    await _firestoreService.createRideRequest(updatedRequest);
  }

  Future<void> updateRideRequestStatus(String rideRequestId, String status, {String? driverId}) async {
    // If no driverId provided and status is "accepted", use current user
    final currentUser = _authService.currentUser;
    final assignedDriverId = driverId ?? 
        (status == "accepted" ? currentUser?.uid : null);
    
    await _firestoreService.updateRideRequestStatus(
      rideRequestId, 
      status, 
      driverId: assignedDriverId,
    );
  }

  // Add this new method to get current user's assigned rides
  Stream<List<RideRequestModel>> getAssignedRides() {
    final userId = _authService.currentUser?.uid;
    if (userId == null) return Stream.value([]);
    
    return _firestoreService.getRideRequests().map((requests) {
      return requests.where((r) => r.driverId == userId).toList();
    });
  }

  Future<void> joinQueue(String kijiweId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      await _firestoreService.joinKijiweQueue(kijiweId, userId);
      await _firestoreService.updateDriverAvailability(userId, true);
    }
  }

  Future<void> leaveQueue(String kijiweId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      await _firestoreService.leaveKijiweQueue(kijiweId, userId);
      await _firestoreService.updateDriverAvailability(userId, false);
    }
  }

  //get rideId
  Future<String?> getRideId(String kijiweId) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      return await _firestoreService.getRideId(kijiweId, userId);
    }
    return null;
  }

  // Add this method to get the queue for a specific Kijiwe
  Future<List<DocumentSnapshot>> getKijiweQueue(String kijiweId) async {
    return await _firestoreService.getKijiweQueue(kijiweId);
  }

  Stream<DocumentSnapshot> getQueueStream(String kijiweId) {
    return _firestoreService.getKijiweQueueStream(kijiweId);
  }
}