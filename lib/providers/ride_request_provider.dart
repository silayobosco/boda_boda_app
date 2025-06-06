import 'package:boda_boda/models/Ride_Request_Model.dart';
import 'package:boda_boda/models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Add this import
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google_maps_flutter;
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
// import 'dart:convert'; // No longer needed for client-side FCM
// import 'package:http/http.dart' as http; // No longer needed for client-side FCM


class RideRequestProvider extends ChangeNotifier {
  final FirestoreService _firestoreService; //= FirestoreService();
  final AuthService authService = AuthService(); 
  List<RideRequestModel> _rideRequests = [];
  List<RideRequestModel> get rideRequests => _rideRequests;

  RideRequestProvider({
    required FirestoreService firestoreService,
    // AuthService is no longer injected, it uses its own instance.
  }) : _firestoreService = firestoreService {
    _listenToRideRequests();
  }

  String? get currentUserId {
    return authService.currentUser?.uid;
  }

  Future<UserModel?> _getCurrentUserModel() async {
    if (currentUserId == null) return null;
    return await _firestoreService.getUser(currentUserId!);
  }

  void _listenToRideRequests() {
    _firestoreService.getRideRequests().listen((List<RideRequestModel> rideRequests) {
      _rideRequests = rideRequests;
      notifyListeners(); 
    });
  }
  Future<String> createRideRequest({
    required LatLng pickup,
    required String pickupAddressName,
    required LatLng dropoff,
    required String dropoffAddressName,
    required List<Map<String, dynamic>> stops, // Expecting {'name': String, 'location': latlong2.LatLng, 'addressName': String}
  }) async {
    final currentUser = authService.currentUser; // Use local authService instance
    final userModel = await _getCurrentUserModel();

    if (currentUser == null) {
      throw Exception('User not authenticated');
    }
    if (userModel == null) {
      throw Exception('User profile not found');
    }

    // Fetch customer details for denormalization
    String customerGender = userModel.gender ?? 'Unknown';
    int? customerAge;
    if (userModel.dob != null) {
      final birthDate = userModel.dob!; // Safe due to null check
      final currentDate = DateTime.now();
      customerAge = currentDate.year - birthDate.year;
      // Adjust age if birthday hasn't occurred yet this year
      if (birthDate.month > currentDate.month ||
          (birthDate.month == currentDate.month && birthDate.day > currentDate.day)) {
        customerAge--;
      }
    }
    String customerAgeRange = (customerAge != null && customerAge >=0) ? '${(customerAge ~/ 10) * 10}s' : 'Unknown';

    // Calculate customer's average rating (handling potential nulls)
    final customerProfile = userModel.customerProfile;
    double averageRating = 0.0; // Default value
    if (customerProfile != null) {
      final sumOfRatings = (customerProfile['sumOfRatingsReceived'] as num?)?.toDouble() ?? 0.0;
      final totalRatings = (customerProfile['totalRatingsReceivedCount'] as num?)?.toInt() ?? 0;
      if (totalRatings > 0) {
        averageRating = sumOfRatings / totalRatings;
      }
    }

    // Prepare a formatted customer details string
    List<String> detailsParts = [];
    if (customerGender != 'Unknown') {
      detailsParts.add(customerGender); // Just the value
    }
    if (customerAgeRange != 'Unknown') {
      detailsParts.add(customerAgeRange); // Just the value, e.g., "20s"
    }
    if (averageRating > 0.0) { // Only show rating if it's not the default 0.0 or if there are ratings
      detailsParts.add('Rating: ${averageRating.toStringAsFixed(1)}');
    }
    String formattedCustomerDetails;
    if (detailsParts.isEmpty) {
      formattedCustomerDetails = "Customer details not available.";
    } else {
      formattedCustomerDetails = detailsParts.join(', ');
    }

    // Construct the RideRequestModel with all necessary data.
    // The model's toJson() method will handle converting LatLng to GeoPoint for stops
    // and requestTime: null to FieldValue.serverTimestamp().
    final RideRequestModel rideRequestData = RideRequestModel(
      customerId: currentUser.uid,
      pickup: google_maps_flutter.LatLng(pickup.latitude, pickup.longitude),
      dropoff: google_maps_flutter.LatLng(dropoff.latitude, dropoff.longitude),
      stops: stops.map((s) => {
        'name': s['name'],
        // Ensure the location passed to the model is gmf.LatLng
        'location': google_maps_flutter.LatLng((s['location'] as LatLng).latitude, (s['location'] as LatLng).longitude),
        'addressName': s['addressName'] // Model now includes addressName in stops
      }).toList(),
      status: 'pending_match',
      requestTime: null, // This will be handled by toJson to become FieldValue.serverTimestamp()
      // Denormalized fields
      customerName: userModel.name,
      customerProfileImageUrl: userModel.profileImageUrl,
      pickupAddressName: pickupAddressName,
      dropoffAddressName: dropoffAddressName,
      customerDetails: formattedCustomerDetails, // Include formatted details
    );

    // Create the request in Firestore
    // Pass the RideRequestModel instance directly.
    // FirestoreService.createRideRequest will call toJson() on this model.
    String rideRequestId = await _firestoreService.createRideRequest(
      rideRequestData
    );

    // Increment customer's requestedRidesCount
    if (currentUser.uid.isNotEmpty) {
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({
        'customerProfile.requestedRidesCount': FieldValue.increment(1),
      }).catchError((e) {
        debugPrint("Error incrementing requestedRidesCount for customer ${currentUser.uid}: $e");
        // Decide if this error should be rethrown or just logged
      });
    }

    notifyListeners();
    return rideRequestId;
  }

  // This method might be simplified or removed if all status updates are driven by Cloud Functions
  // or specific user actions (like cancelRideByCustomer).
  Future<void> updateRideRequestStatus(String rideRequestId, String newStatus, {String? driverId}) async {
    await _firestoreService.updateRideRequestStatus(
      rideRequestId, 
      newStatus, // Use the newStatus parameter
      driverId: driverId, // driverId is explicitly passed when a driver is involved
    );
    notifyListeners();
  }

  // Driver-initiated actions (accept, decline, confirmArrival, startRide, completeRide, cancelRideByDriver)
  // have been moved to DriverProvider and are handled by the 'handleDriverRideAction' Cloud Function.
  // They are removed from this provider.

  Future<void> cancelRideByCustomer(String rideRequestId) async {
    final customer = authService.currentUser;
    if (customer == null) throw Exception('Customer not logged in');
    WriteBatch batch = FirebaseFirestore.instance.batch();
    final rideRef = FirebaseFirestore.instance.collection('rideRequests').doc(rideRequestId);
    final customerUserRef = FirebaseFirestore.instance.collection('users').doc(customer.uid);

    batch.update(rideRef, {'status': 'cancelled_by_customer'});
    // Increment customer's cancelledByCustomerCount
    batch.update(customerUserRef, {'customerProfile.cancelledByCustomerCount': FieldValue.increment(1)});

    await batch.commit();
    notifyListeners();
  }

  // The rateUser method is now split.
  // Driver rating customer is handled by DriverProvider via Cloud Function.
  Future<void> rateUser({
    required String rideId,
    required String ratedUserId, 
    required String ratedUserRole, 
    required double rating,
    String? comment,
  }) async {
    // This method is now primarily for CUSTOMER rating a DRIVER.
    // If a driver is rating a customer, that logic is in DriverProvider.
    if (ratedUserRole == 'customer') {
      throw Exception("Driver rating customer is handled by DriverProvider.");
    }
    final raterUserId = authService.currentUser?.uid;
    if (raterUserId == null) throw Exception("Rater not authenticated");

    WriteBatch batch = FirebaseFirestore.instance.batch();
    final rideRequestRef = FirebaseFirestore.instance.collection('rideRequests').doc(rideId);
    final ratedUserRef = FirebaseFirestore.instance.collection('users').doc(ratedUserId);

    Map<String, dynamic> rideUpdateData = {};
    Map<String, dynamic> userProfileUpdate = {};

    if (ratedUserRole == 'driver') { // Customer is rating the driver
      rideUpdateData['customerRatingToDriver'] = rating;
      if (comment != null && comment.isNotEmpty) {
        rideUpdateData['customerCommentToDriver'] = comment;
      }
      // Update driver's aggregate rating stats
      userProfileUpdate['driverProfile.sumOfRatingsReceived'] = FieldValue.increment(rating);
      userProfileUpdate['driverProfile.totalRatingsReceivedCount'] = FieldValue.increment(1);
      // Average rating calculation should be handled by a Cloud Function (trigger on user document update)
    } else {
      throw Exception("Invalid ratedUserRole for this rating method.");
    }

    batch.update(rideRequestRef, rideUpdateData);
    batch.update(ratedUserRef, userProfileUpdate);
    await batch.commit();

    debugPrint("Rating of $rating for $ratedUserRole ($ratedUserId) on ride $rideId submitted by $raterUserId. Comment: $comment");
    notifyListeners();
  }

  // Stream a single ride request
  Stream<RideRequestModel?> getRideStream(String rideRequestId) {
    return _firestoreService.getRideRequestDocumentStream(rideRequestId).map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return RideRequestModel.fromJson(snapshot.data() as Map<String, dynamic>, snapshot.id);
      }
      return null;
    });
  }

  // Add this new method to get current user's assigned rides
  Stream<List<RideRequestModel>> getAssignedRides() {
    final userId = authService.currentUser?.uid; // Use local authService instance
    if (userId == null) return Stream.value([]);
    
    return _firestoreService.getRideRequests().map((requests) {
      return requests.where((r) => r.driverId == userId).toList();
    });
  }

  //get rideId
  Future<String?> getRideId(String kijiweId) async {
    final userId = authService.currentUser?.uid; // Use local authService instance
    if (userId != null) {
      return await _firestoreService.getRideId(kijiweId, userId);
    }
    return null;
  }

  // Add this method to get the queue for a specific Kijiwe
  Future<List<String>> getKijiweQueueData(String kijiweId) async {
    return await _firestoreService.getKijiweQueueData(kijiweId);
  }

  Stream<DocumentSnapshot> getQueueStream(String kijiweId) {
    return _firestoreService.getKijiweQueueStream(kijiweId);
  }

  // Client-side matching logic (_findAndAssignToNearestKijiweDriver) and
  // client-side FCM sending (_sendFCMNotificationToDriver) have been removed.
  // These responsibilities are now handled by Cloud Functions.
}