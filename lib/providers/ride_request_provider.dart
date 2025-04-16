import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart'; // Import data models

class RideRequestProvider extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  List<RideRequestModel> _rideRequests = [];
  List<RideRequestModel> get rideRequests => _rideRequests;

  RideRequestProvider() {
    _listenToRideRequests();
  }

  void _listenToRideRequests() {
    _firestoreService.getRideRequests().listen((List<RideRequestModel> rideRequests) {
      _rideRequests = rideRequests;
      notifyListeners();
    });
  }

  Future<void> createRideRequest(RideRequestModel rideRequest) async {
    await _firestoreService.createRideRequest(rideRequest);
  }

  Future<void> updateRideRequestStatus(String rideRequestId, String status, {String? driverId}) async {
    await _firestoreService.updateRideRequestStatus(rideRequestId, status, driverId: driverId);
  }
}