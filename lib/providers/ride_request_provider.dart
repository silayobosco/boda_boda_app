import 'package:boda_boda/models/Ride_Request_Model.dart';
import 'package:boda_boda/models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Add this import
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as google_maps_flutter;
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import 'package:cloud_functions/cloud_functions.dart';

// import 'dart:convert'; // No longer needed for client-side FCM
// import 'package:http/http.dart' as http; // No longer needed for client-side FCM


class RideRequestProvider extends ChangeNotifier {
  final FirestoreService _firestoreService; //= FirestoreService();
  final AuthService authService = AuthService(); 
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
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
    String? customerNote, // Add customerNote parameter
    String? estimatedDistanceText, // New parameter for estimated distance string
    double? estimatedFare, // New parameter for estimated fare value
    String? estimatedDurationText, // New parameter for estimated duration string
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

    // Fetch Customer details for denormalization
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

    // Calculate Customer's average rating (handling potential nulls)
    final customerProfile = userModel.customerProfile;
    double averageRating = 0.0; // Default value
    if (customerProfile != null) {
      final sumOfRatings = (customerProfile['sumOfRatingsReceived'] as num?)?.toDouble() ?? 0.0;
      final totalRatings = (customerProfile['totalRatingsReceivedCount'] as num?)?.toInt() ?? 0;
      if (totalRatings > 0) {
        averageRating = sumOfRatings / totalRatings;
      }
    }

    // Prepare a formatted Customer details string
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

    // Parse estimated distance and duration
    double? estimatedDistanceKm;
    if (estimatedDistanceText != null) {
      final valueMatch = RegExp(r'([\d\.]+)').firstMatch(estimatedDistanceText);
      if (valueMatch != null) {
        double numericValue = double.tryParse(valueMatch.group(1) ?? '0') ?? 0;
        if (estimatedDistanceText.toLowerCase().contains("km")) {
          estimatedDistanceKm = numericValue;
        } else if (estimatedDistanceText.toLowerCase().contains("m")) {
          estimatedDistanceKm = numericValue / 1000.0;
        } else {
          estimatedDistanceKm = numericValue; // Assume km if no unit
        }
      }
    }
    double? estimatedDurationMinutes;
    if (estimatedDurationText != null) {
      final hourMatch = RegExp(r'(\d+)\s*hr').firstMatch(estimatedDurationText);
      if (hourMatch != null) estimatedDurationMinutes = (double.tryParse(hourMatch.group(1) ?? '0') ?? 0) * 60;
      final minMatch = RegExp(r'(\d+)\s*min').firstMatch(estimatedDurationText);
      if (minMatch != null) estimatedDurationMinutes = (estimatedDurationMinutes ?? 0) + (double.tryParse(minMatch.group(1) ?? '0') ?? 0);
      if (estimatedDurationMinutes == 0 && estimatedDurationText.contains("min")) { // Handle "X min" case
        final simpleMinMatch = RegExp(r'([\d\.]+)').firstMatch(estimatedDurationText);
        if (simpleMinMatch != null) estimatedDurationMinutes = double.tryParse(simpleMinMatch.group(1) ?? '0') ?? 0;
      }
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
      customerNoteToDriver: customerNote, // Store the note in the ride request document
      estimatedDistanceKm: estimatedDistanceKm,
      // estimatedFare: estimatedFare, // This field in model is for FCM estimate to Driver
      customerCalculatedEstimatedFare: estimatedFare, // Save Customer's app calculated estimate
      estimatedDurationMinutes: estimatedDurationMinutes,
    );

    // Create the request in Firestore
    // Pass the RideRequestModel instance directly.
    // FirestoreService.createRideRequest will call toJson() on this model.
    String rideRequestId = await _firestoreService.createRideRequest(
      rideRequestData
    );

    // If a Customer note was provided, add it as the first message in the chat
    if (customerNote != null && customerNote.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('rideChats')
            .doc(rideRequestId)
            .collection('messages')
            .add({
          'senderId': currentUser.uid,
          'senderRole': 'Customer', // Assuming the role is Customer here
          'text': customerNote,
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
        debugPrint("RideRequestProvider: Initial Customer note added to chat for ride $rideRequestId");
      } catch (e) {
        debugPrint("RideRequestProvider: Error adding initial Customer note to chat: $e");
        // Non-fatal error, ride request is already created.
      }
    }

    // Increment Customer's requestedRidesCount
    if (currentUser.uid.isNotEmpty) {
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({
        'customerProfile.requestedRidesCount': FieldValue.increment(1),
      }).catchError((e) {
        debugPrint("Error incrementing requestedRidesCount for Customer ${currentUser.uid}: $e");
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
      driverId: driverId, // driverId is explicitly passed when a Driver is involved
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
    // Increment Customer's cancelledByCustomerCount
    batch.update(customerUserRef, {'customerProfile.cancelledByCustomerCount': FieldValue.increment(1)});

    await batch.commit();
    notifyListeners();
  }

  Future<void> updateCustomerNote(String rideRequestId, String note) async {
    await _firestoreService.updateRideRequestFields(
      rideRequestId,
      {'customerNoteToDriver': note},
    );
    // No notifyListeners needed if UI listens to the ride stream directly for this field.
  }

  Future<void> editScheduledRide(String rideId, Map<String, dynamic> rideUpdateData) async {
    final HttpsCallable callable = _functions.httpsCallable('manageScheduledRide');
    try {
      // Ensure DateTime objects are converted to ISO 8601 strings for JSON serialization
      Map<String, dynamic> payload = Map.from(rideUpdateData); 

      if (payload['scheduledDateTime'] is DateTime) {
        payload['scheduledDateTime'] = (payload['scheduledDateTime'] as DateTime).toIso8601String();
      }
      if (payload['recurrenceEndDate'] is DateTime) {
        payload['recurrenceEndDate'] = (payload['recurrenceEndDate'] as DateTime).toIso8601String();
      }
      // Convert google_maps_flutter.LatLng to a map for GeoPoint conversion in CF
      if (payload['pickup'] != null && payload['pickup'] is google_maps_flutter.LatLng) {
          final gmfLatLng = payload['pickup'] as google_maps_flutter.LatLng;
          payload['pickup'] = {'latitude': gmfLatLng.latitude, 'longitude': gmfLatLng.longitude};
      }
      if (payload['dropoff'] != null && payload['dropoff'] is google_maps_flutter.LatLng) {
          final gmfLatLng = payload['dropoff'] as google_maps_flutter.LatLng;
          payload['dropoff'] = {'latitude': gmfLatLng.latitude, 'longitude': gmfLatLng.longitude};
      }
      if (payload['stops'] != null && payload['stops'] is List) {
          payload['stops'] = (payload['stops'] as List).map((stop) {
              if (stop is Map && stop['location'] is google_maps_flutter.LatLng) {
                  final gmfLatLng = stop['location'] as google_maps_flutter.LatLng;
                  // Ensure other stop properties like 'name' and 'addressName' are preserved
                  return {
                    'name': stop['name'],
                    'addressName': stop['addressName'],
                    'location': {'latitude': gmfLatLng.latitude, 'longitude': gmfLatLng.longitude}
                  };
              }
              return stop; // Return as is if not a LatLng that needs conversion
          }).toList();
      }

      final response = await callable.call(<String, dynamic>{
        'action': 'edit',
        'rideId': rideId,
        'rideData': payload,
      });
      debugPrint("Edit scheduled ride result: ${response.data}");
      // Consider calling notifyListeners() if your UI needs to react to this change directly
      // or rely on Firestore stream updates for the scheduledRides collection.
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Functions Error editing scheduled ride: ${e.code} - ${e.message}');
      throw Exception('Failed to edit scheduled ride: ${e.message}');
    } catch (e) {
      debugPrint('General Error editing scheduled ride: $e');
      throw Exception('An unexpected error occurred while editing the ride.');
    }
  }

  Future<void> deleteScheduledRide(String rideId) async {
    final HttpsCallable callable = _functions.httpsCallable('manageScheduledRide');
    try {
      final response = await callable.call(<String, dynamic>{'action': 'delete', 'rideId': rideId});
      debugPrint("Delete scheduled ride result: ${response.data}");
    } catch (e) {
      debugPrint('Error deleting scheduled ride: $e');
      throw Exception('Failed to delete scheduled ride: ${e.toString()}');
    }
  }

  // The rateUser method is now split.
  // Driver rating Customer is handled by DriverProvider via Cloud Function.
  Future<void> rateUser({
    required String rideId,
    required String ratedUserId, 
    required String ratedUserRole, 
    required double rating,
    String? comment,
  }) async {
    // This method is now primarily for CUSTOMER rating a DRIVER.
    // If a Driver is rating a Customer, that logic is in DriverProvider.
    if (ratedUserRole == 'Customer') {
      throw Exception("Driver rating Customer is handled by DriverProvider.");
    }
    final raterUserId = authService.currentUser?.uid;
    if (raterUserId == null) throw Exception("Rater not authenticated");

    final rideRequestRef = FirebaseFirestore.instance.collection('rideRequests').doc(rideId);
    // final ratedUserRef = FirebaseFirestore.instance.collection('users').doc(ratedUserId); // REMOVE: Customer cannot update Driver's profile directly

    Map<String, dynamic> rideUpdateData = {};
    //Map<String, dynamic> userProfileUpdate = {};

    if (ratedUserRole == 'Driver') { // Customer is rating the Driver
      rideUpdateData['customerRatingToDriver'] = rating;
      if (comment != null && comment.isNotEmpty) {
        rideUpdateData['customerCommentToDriver'] = comment;
      }
      // REMOVE: Driver's aggregate rating stats update. This should be handled by a Cloud Function.
    } else {
      throw Exception("Invalid ratedUserRole for this rating method.");
    }

    // Update only the ride request document
    await rideRequestRef.update(rideUpdateData);

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

  // Method to get ride history based on role
  Stream<List<RideRequestModel>> getRideHistory(String userId, String role) {
    if (role == 'Customer') {
      return _firestoreService.getCustomerRideHistory(userId);
    } else if (role == 'Driver') {
      return _firestoreService.getDriverRideHistory(userId);
    }
    return Stream.value([]); // Return empty stream for unknown roles or if userId is null
  }

  // Method to get scheduled rides for a Customer
  Stream<List<RideRequestModel>> getScheduledRides(String customerId) {
    // Assuming scheduled rides are only for customers for now
    return _firestoreService.getScheduledRidesForCustomer(customerId);
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