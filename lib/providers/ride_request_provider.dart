import 'package:boda_boda/models/Ride_Request_Model.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Add this import
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import 'package:geolocator/geolocator.dart'; // For distance calculation
import 'package:geoflutterfire3/geoflutterfire3.dart'; // For Geo-queries
import '/services/auth_service.dart';
import 'dart:convert'; // For jsonEncode
import 'package:http/http.dart' as http; // For HTTP requests


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

  void _listenToRideRequests() {
    _firestoreService.getRideRequests().listen((List<RideRequestModel> rideRequests) {
      _rideRequests = rideRequests;
      notifyListeners(); 
    });
  }

  Future<void> createRideRequest(RideRequestModel rideRequest) async {
    final currentUser = authService.currentUser; // Use local authService instance
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }
    
    // Ensure customerId is set, status is 'pending_match' initially
    final initialRideRequestData = rideRequest.copyWith(
      customerId: currentUser.uid,
      status: 'pending_match', // Initial status before matching
      // kijiweId will be determined by the matching logic
    );

    // Create the request in Firestore and get its ID
    // String rideRequestId = await _firestoreService.createRideRequest(initialRideRequestData); // Cloud Function will pick this up
    await _firestoreService.createRideRequest(initialRideRequestData);

    // The Cloud Function 'matchRideRequest' will now handle the matching.
    // Remove the client-side attempt to find and assign a driver.
    // await _findAndAssignToNearestKijiweDriver(initialRideRequestData.copyWith(id: rideRequestId));
  }

  Future<void> updateRideRequestStatus(String rideRequestId, String status, {String? driverId}) async {
    // If no driverId provided and status is "accepted", use current user
    final currentUser = authService.currentUser; // Use local authService instance
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

  Future<void> _findAndAssignToNearestKijiweDriver(RideRequestModel rideRequest) async {
    if (rideRequest.id == null) {
      debugPrint("Ride request ID is null, cannot perform matching.");
      return;
    }

    const double searchRadiusKm = 10.0; // Configurable: e.g., 10km, adjust as needed
    const int maxKijiwesToTry = 4; // Try up to 4 nearest Kijiwes

    try {
      final geo = _firestoreService.geo; // Get GeoFlutterFire instance
      final kijiweCollectionRef = _firestoreService.getKijiweCollectionRef(); // Get Kijiwe collection reference

      final GeoFirePoint centerPoint = geo.point(
        latitude: rideRequest.pickup.latitude,
        longitude: rideRequest.pickup.longitude,
      );
      debugPrint("RideRequestProvider: Searching for Kijiwes around centerPoint: Lat ${centerPoint.latitude}, Lng ${centerPoint.longitude} for ride ${rideRequest.id}");

      // Perform the geo-query
      // Adjust stream type to dynamic for DocumentSnapshot data if explicit typing isn't fully propagated
      Stream<List<DocumentSnapshot<dynamic>>> stream = geo
          .collection(collectionRef: kijiweCollectionRef) // Remove explicit type argument here
          .within(center: centerPoint, radius: searchRadiusKm, field: 'position', strictMode: false);

      // kijiweDocsInRadius will now be List<DocumentSnapshot<dynamic>>
      List<DocumentSnapshot<dynamic>> kijiweDocsInRadius = await stream.first;

      if (kijiweDocsInRadius.isEmpty) {
        debugPrint("No Kijiwes found within ${searchRadiusKm}km of pickup for ride ${rideRequest.id}.");
        await _firestoreService.updateRideRequestStatus(rideRequest.id!, 'no_kijiwes_nearby', kijiweId: null); // Pass kijiweId as null or handle appropriately
        return;
      }

      // Calculate actual distances for Kijiwes found in radius and sort them
      List<Map<String, dynamic>> kijiwesWithDistance = [];
      debugPrint("_findAndAssignToNearestKijiweDriver: Found ${kijiweDocsInRadius.length} kijiwes in radius. Processing them...");
      for (var kijiweDoc in kijiweDocsInRadius) {
        final String kijiweIdForLog = kijiweDoc.id;
        // Explicitly cast the data from the DocumentSnapshot<dynamic>
        final kijiweData = kijiweDoc.data() as Map<String, dynamic>?;
        if (kijiweData == null) {
          debugPrint("Kijiwe $kijiweIdForLog: Data is null. Skipping.");
          continue;
        }
        debugPrint("Kijiwe $kijiweIdForLog: Data found: $kijiweData");

        GeoPoint? kijiweGeoPoint;
        final positionField = kijiweData['position']; // Get the field first

        if (positionField == null) {
          debugPrint("Kijiwe $kijiweIdForLog: 'position' field is null. Skipping.");
          continue;
        }

        if (positionField is Map<String, dynamic>) {
          final geoPointField = positionField['geoPoint'];
          if (geoPointField is GeoPoint) {
            kijiweGeoPoint = geoPointField;
            debugPrint("Kijiwe $kijiweIdForLog: Successfully extracted geoPoint: $kijiweGeoPoint");
          } else {
            debugPrint("Kijiwe $kijiweIdForLog: 'position.geoPoint' field is not a GeoPoint. Type is ${geoPointField?.runtimeType}. Value: $geoPointField. Skipping.");
          }
        } else {
          debugPrint("Kijiwe $kijiweIdForLog: 'position' field is not a Map. Type is ${positionField.runtimeType}. Value: $positionField. Skipping.");
        }

        if (kijiweGeoPoint != null) {
          double distanceInMeters = Geolocator.distanceBetween(
            rideRequest.pickup.latitude,
            rideRequest.pickup.longitude,
            kijiweGeoPoint.latitude,
            kijiweGeoPoint.longitude,
          );
          kijiwesWithDistance.add({
            'doc': kijiweDoc,
            'distance': distanceInMeters,
            'name': kijiweData['name'] ?? 'Unnamed Kijiwe',
          });
        } else {
          debugPrint("Kijiwe $kijiweIdForLog: kijiweGeoPoint is null after checks. Not adding to kijiwesWithDistance.");
        }
      }

      if (kijiwesWithDistance.isEmpty) {
        debugPrint("Could not find a suitable nearest Kijiwe for ride ${rideRequest.id}.");
        await _firestoreService.updateRideRequestStatus(rideRequest.id!, 'no_kijiwe_match_with_location', kijiweId: null);
        return;
      }

      // Sort by distance (ascending)
      kijiwesWithDistance.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

      int kijiwesTried = 0;
      for (var kijiweEntry in kijiwesWithDistance) {
        if (kijiwesTried >= maxKijiwesToTry) break;

        // kijiweEntry['doc'] is DocumentSnapshot<dynamic>
        final kijiweDoc = kijiweEntry['doc'] as DocumentSnapshot<dynamic>;
        final String selectedKijiweId = kijiweDoc.id;
        final kijiweData = kijiweDoc.data();
        if (kijiweData == null) continue;

        final List<dynamic> queueDynamic = kijiweData['queue'] as List<dynamic>? ?? [];
        final List<String> queue = queueDynamic.map((item) => item.toString()).toList();
        final double distanceToKijiwe = kijiweEntry['distance'] as double;

        debugPrint("Trying Kijiwe ${kijiweEntry['name']} (ID: $selectedKijiweId), Distance: ${distanceToKijiwe.toStringAsFixed(0)}m, Queue size: ${queue.length} for ride ${rideRequest.id}");

      if (queue.isEmpty) {
        debugPrint("Queue for nearest Kijiwe $selectedKijiweId is empty.");
        // And update the ride request with the found kijiweId but no driver
        await _firestoreService.updateRideRequestStatus(rideRequest.id!, 'kijiwe_queue_empty', kijiweId: selectedKijiweId);
        // Optionally, you can also update the ride request status to 'no_drivers_available'
        // This will be handled in the next iteration if no driver is found
        // await _firestoreService.updateRideRequestStatus(rideRequest.id!, 'no_drivers_available', kijiweId: selectedKijiweId);
        await _firestoreService.updateRideRequestStatus(rideRequest.id!, rideRequest.status ?? 'pending_match', kijiweId: selectedKijiweId);
        kijiwesTried++;
        continue; // Try next Kijiwe
      }

      // Iterate through the queue to find an available driver
      for (String driverId in queue) { // Queue is now List<String>
        final driverUserDocRef = FirebaseFirestore.instance.collection('users').doc(driverId);
        final driverUserSnapshot = await driverUserDocRef.get();

        if (driverUserSnapshot.exists && driverUserSnapshot.data() != null) {
          // Cast driver user data
          final driverUserData = driverUserSnapshot.data()! as Map<String, dynamic>;
          final driverProfile = driverUserData['driverProfile'] as Map<String, dynamic>?;

          // Assuming drivers in queue are already vetted for isOnline and waitingForRide status
          if (driverProfile != null) { // It's still good practice to ensure the profile map exists
            // Found a suitable driver!
            debugPrint("Matching ride ${rideRequest.id} to driver $driverId from Kijiwe $selectedKijiweId");

            WriteBatch batch = FirebaseFirestore.instance.batch();

            // 1. Update RideRequest: assign driver, kijiweId, and set status
            final rideRequestRef = FirebaseFirestore.instance.collection('rideRequests').doc(rideRequest.id!);
            batch.update(rideRequestRef, {'driverId': driverId, 'status': 'pending_driver_acceptance', 'kijiweId': selectedKijiweId});

            // 2. Update Driver's profile: set status
            batch.update(driverUserDocRef, {'driverProfile.status': 'pending_ride_acceptance'});

            // 3. DO NOT remove driver from Kijiwe queue here.
            // This will be handled by DriverProvider when the driver accepts the ride.

            await batch.commit();
            debugPrint("Successfully assigned ride ${rideRequest.id} to driver $driverId from Kijiwe $selectedKijiweId and updated queue.");
            
            // Send FCM notification directly
            final String? driverFcmToken = driverUserData['fcmToken'] as String?;
            if (driverFcmToken != null && driverFcmToken.isNotEmpty) {
              // Construct the RideRequestModel with all details for the notification payload
              final rideDetailsForNotification = rideRequest.copyWith(status: 'pending_driver_acceptance', driverId: driverId, kijiweId: selectedKijiweId);
              await _sendFCMNotificationToDriver(driverFcmToken, rideDetailsForNotification);
            } else {
              debugPrint("Driver $driverId does not have an FCM token. Cannot send notification.");
            }
            return; // Exit after assigning to the first available driver
          }
        }
      } // End of driver loop for a Kijiwe
        debugPrint("No available (online and waiting) drivers found in Kijiwe $selectedKijiweId for ride ${rideRequest.id}.");
        kijiwesTried++;
      } // End of Kijiwe loop

      // If loop completes, no driver was found in the tried Kijiwes
      debugPrint("No suitable driver found for ride ${rideRequest.id} after checking $kijiwesTried Kijiwes.");
      await _firestoreService.updateRideRequestStatus(rideRequest.id!, 'no_drivers_available', kijiweId: kijiwesWithDistance.isNotEmpty ? (kijiwesWithDistance.first['doc'] as DocumentSnapshot).id : null);

    } catch (e, s) {
      debugPrint("Error in _findAndAssignToNearestKijiweDriver for ride ${rideRequest.id}: $e\n$s");
      try {
        await _firestoreService.updateRideRequestStatus(rideRequest.id!, 'matching_error');
      } catch (e2) {
        debugPrint("Additionally, failed to update ride status to matching_error: $e2");
      }
      // Handle error, maybe set ride status to 'matching_failed' or retry later.
    }
  }

  Future<void> _sendFCMNotificationToDriver(String fcmToken, RideRequestModel rideDetails) async {
    // !!! WARNING: Storing your FCM Server Key in the client-side code is highly insecure !!!
    // !!! It should ideally be handled by a backend server or Cloud Function. !!!
    // !!! This is for demonstration purposes only and not recommended for production. !!!
    // !!! Replace 'YOUR_FCM_SERVER_KEY_HERE' with your actual FCM Server Key. !!!
    const String fcmServerKey = 'AIzaSyDAkdhRB9BsOIV693PZ4nPOXfklh9A4nAM'; 

    if (fcmServerKey == 'YOUR_FCM_SERVER_KEY_HERE') {
      debugPrint("FCM Server Key not configured in RideRequestProvider. Cannot send notification.");
      // In a real app, you might throw an error or handle this more gracefully.
      return;
    }

    final Map<String, dynamic> notificationPayload = {
      'to': fcmToken,
      'notification': {
        'title': 'New Ride Request!',
        'body': 'You have a new ride assignment. Tap to view details.',
        'sound': 'default', // Optional: for default notification sound
      },
      'data': { // Custom data payload for your app to handle
        'rideRequestId': rideDetails.id,
        'customerId': rideDetails.customerId,
        'pickupLat': rideDetails.pickup.latitude.toString(),
        'pickupLng': rideDetails.pickup.longitude.toString(),
        'dropoffLat': rideDetails.dropoff.latitude.toString(),
        'dropoffLng': rideDetails.dropoff.longitude.toString(),
        'status': rideDetails.status, // This will be 'pending_driver_acceptance'
        'click_action': 'FLUTTER_NOTIFICATION_CLICK', // Important for Flutter when app is in background/terminated
        // Add any other data your driver app needs to handle the notification
      },
      'priority': 'high', // Ensures timely delivery, especially for data messages
    };

    try {
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'key=$fcmServerKey',
        },
        body: jsonEncode(notificationPayload),
      );

      if (response.statusCode == 200) {
        debugPrint('FCM notification sent successfully to token: $fcmToken. Response: ${response.body}');
      } else {
        debugPrint('Failed to send FCM notification to $fcmToken. Status: ${response.statusCode}. Body: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error sending FCM notification to $fcmToken: $e');
    }
  }
}