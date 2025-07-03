import 'package:boda_boda/models/Ride_Request_Model.dart';
import 'dart:async';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart'; // Import the UserModel class
import 'package:latlong2/latlong.dart' as ll;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmf; // Import for google_maps_flutter.LatLng

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance; // Add this line
  final GeoFlutterFire geo = GeoFlutterFire();

  // Create (Add a new user)
  Future<void> createUser(UserModel user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set(user.toJson());
    } catch (e) {
      print("Error creating user: $e");
      rethrow; // Rethrow the error for handling in the UI
    }
  }

  // Read (Get user data)
  Future<UserModel?> getUser(String uid) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        return UserModel.fromJson(userDoc.data() as Map<String, dynamic>);
      }
      return null; // User not found
    } catch (e) {
      print("Error getting user: $e");
      rethrow;
    }
  }

  // Update (Update user data)
  Future<void> updateUser(UserModel user) async {
    try {
      await _firestore.collection('users').doc(user.uid).update(user.toJson());
    } catch (e) {
      print("Error updating user: $e");
      rethrow;
    }
  }

  // Delete (Delete user)
  Future<void> deleteUser(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).delete();
    } catch (e) {
      print("Error deleting user: $e");
      rethrow;
    }
  }

  Future<String> uploadProfileImage(String userId, File imageFile) async {
    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('$userId.jpg');

      await storageRef.putFile(imageFile);
      final imageUrl = await storageRef.getDownloadURL();
      return imageUrl;
    } catch (e) {
      debugPrint("Error uploading profile image: $e");
      rethrow;
    }
  }

  Future<void> updateUserSavedPlaces(String userId, List<Map<String, dynamic>> savedPlaces) async {
    try {
      // Convert any LatLng objects to GeoPoints before saving.
      final placesToSave = savedPlaces.map((place) {
        if (place['location'] is gmf.LatLng) {
          final gmf.LatLng loc = place['location'];
          return {
            ...place,
            'location': GeoPoint(loc.latitude, loc.longitude),
          };
        }
        return place; // Assume it's already a GeoPoint or null
      }).toList();

      await _firestore.collection('users').doc(userId).update({
        'customerProfile.savedPlaces': placesToSave,
      });
    } catch (e) {
      debugPrint("Error updating saved places: $e");
      rethrow;
    }
  }

  Future<void> updateUserProfileImageUrl(String userId, String imageUrl) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'profileImageUrl': imageUrl,
      });
    } catch (e) {
      debugPrint("Error updating profile image URL: $e");
      rethrow;
    }
  }
Future<String> createRideRequest(RideRequestModel rideRequest) async {
    try {
      DocumentReference docRef = await _firestore.collection('rideRequests').add(rideRequest.toJson());
      return docRef.id; // Return the ID of the newly created document  
      } catch (e) {
      print('Error creating ride request: $e');
      rethrow;
    }
  }

  Stream<List<RideRequestModel>> getRideRequests() {
    return _firestore.collection('rideRequests').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => RideRequestModel.fromJson(doc.data(), doc.id)).toList();
    });
  }

  // Stream scheduled rides for a customer
  Stream<List<RideRequestModel>> getScheduledRidesForCustomer(String customerId) {
    return _firestore
        .collection('scheduledRides') // Assuming 'scheduledRides' collection
        .where('customerId', isEqualTo: customerId)
        .where('status', isEqualTo: 'scheduled') // Or other relevant statuses
        .orderBy('scheduledDateTime', descending: false) // Example ordering
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => RideRequestModel.fromJson(doc.data(), doc.id)).toList();
    });
  }

  // Stream a single ride request document
  Stream<DocumentSnapshot> getRideRequestDocumentStream(String rideRequestId) {
    return _firestore.collection('rideRequests').doc(rideRequestId).snapshots();
  }


  Future<void> updateRideRequestStatus(String rideRequestId, String status, {String? driverId, String? kijiweId}) async {
    try {
      Map<String, dynamic> updateData = {'status': status};
      if (driverId != null) {
        updateData['driverId'] = driverId;
      }
      if (kijiweId != null) {
        updateData['kijiweId'] = kijiweId;
      }
      await _firestore.collection('rideRequests').doc(rideRequestId).update(updateData);
    } catch (e) {
      print('Error updating ride request status: $e');
      rethrow;
    }
  }

  Future<void> updateRideRequestFields(String rideRequestId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('rideRequests').doc(rideRequestId).update(data);
    } catch (e) {
      print('Error updating ride request fields: $e');
      rethrow;
    }
  }

  // Ride History

  // Fetches ride history for a customer
  Stream<List<RideRequestModel>> getCustomerRideHistory(String customerId) {
    return _firestore
        .collection('rideRequests') // Assuming history is derived from rideRequests
        .where('customerId', isEqualTo: customerId)
        .where('status', whereIn: ['completed', 'cancelled_by_customer', 'cancelled_by_driver']) // Example statuses for history
        .orderBy('requestTime', descending: true) // Or completedTime
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => RideRequestModel.fromJson(doc.data(), doc.id)).toList();
    });
  }

  // Fetches ride history for a driver
  Stream<List<RideRequestModel>> getDriverRideHistory(String driverId) {
    return _firestore
        .collection('rideRequests') // Assuming history is derived from rideRequests
        .where('driverId', isEqualTo: driverId)
        .where('status', whereIn: ['completed', 'cancelled_by_customer', 'cancelled_by_driver']) // Example statuses for history
        .orderBy('requestTime', descending: true) // Or completedTime
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => RideRequestModel.fromJson(doc.data(), doc.id)).toList();
    });
  }

  // scheduleRide (The old createRideHistory method might be repurposed or removed if history is derived)
  // If you have a separate 'rideHistory' collection, the old method was:
  /*
  Future<void> createRideHistory(RideHistoryModel rideHistory) async {
    try {
      await _firestore.collection('rideHistory').add(rideHistory.toJson());
    } catch (e) {
      print('Error creating ride history: $e');
      rethrow;
    }
  }

  Stream<List<RideHistoryModel>> getRideHistory(String userId) { // This was generic, now split
     return _firestore
        .collection('rideHistory')
        .where('customerId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => RideHistoryModel.fromJson(doc.data(), doc.id)).toList();
    });
  }
  */

  // scheduleRide

  // User Location Updates

  Future<void> updateUserLocation(String userId, ll.LatLng location) async {
    try {
      // This updates the general user location.
      await _firestore.collection('users').doc(userId).update({
        'location': GeoPoint(location.latitude, location.longitude),
      });
      // If this user is a driver, also update their driverProfile.currentLocation
    } catch (e) {
      print('Error updating user location: $e');
      rethrow;
    }
  }

  Stream<DocumentSnapshot> getUserLocationStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots();
  }

  // Specifically for driver's active location and heading
  Future<void> updateDriverActiveLocation(String driverId, gmf.LatLng location, double? heading) async {
    try {
      Map<String, dynamic> dataToUpdate = {
        'driverProfile.currentLocation': GeoPoint(location.latitude, location.longitude),
      };
      if (heading != null) {
        dataToUpdate['driverProfile.currentHeading'] = heading;
      }
      await _firestore.collection('users').doc(driverId).update(dataToUpdate);
    } catch (e) {
      print('Error updating driver active location: $e');
      rethrow;
    }
  }

  // Stream for a user document, which can be used to get driver's profile updates
  Stream<DocumentSnapshot> getUserDocumentStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots();
  }

  Stream<List<UserModel>> getDriversLocationsStream() {
    return _firestore.collection('users').where('role', isEqualTo: 'Driver').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => UserModel.fromJson(doc.data())).toList();
    });
  }

  // Kijiwe Queue Management
Future<void> joinKijiweQueue(String kijiweId, String userId) async {
  // The queue is an array of maps within the Kijiwe document itself.
  final kijiweRef = _firestore.collection('kijiwe').doc(kijiweId);
  try {
    // Queue is now an array of strings (driverIds)
    await kijiweRef.update({
      'queue': FieldValue.arrayUnion([userId])
    });
    debugPrint("Successfully added driver '$userId' to queue for Kijiwe '$kijiweId'");
  } catch (e) {
    debugPrint("Error joining queue for Kijiwe '$kijiweId' (user '$userId'): $e");
    rethrow;
  }
}

Future<void> leaveKijiweQueue(String kijiweId, String userId) async {
  final kijiweRef = _firestore.collection('kijiwe').doc(kijiweId);
  try {
    // Queue is now an array of strings (driverIds)
    await kijiweRef.update({
      'queue': FieldValue.arrayRemove([userId])
    });
    debugPrint("Successfully removed driver '$userId' from queue for Kijiwe '$kijiweId'");
  } catch (e) {
    debugPrint("Error leaving queue for Kijiwe '$kijiweId' (user '$userId'): $e");
    rethrow;
  }
}

Stream<DocumentSnapshot> getKijiweQueueStream(String kijiweId) {
  return _firestore.collection('kijiwe').doc(kijiweId).snapshots();
}

  // this method retrieves the queue data for a specific Kijiwe
  // It returns a list of maps, each representing a driver in the queue
  Future<List<String>> getKijiweQueueData(String kijiweId) async {
    final docSnap = await _firestore.collection('kijiwe').doc(kijiweId).get();
    if (docSnap.exists && docSnap.data() != null && docSnap.data()!.containsKey('queue')) {
      // Queue is now a list of strings
      return List<String>.from(docSnap.data()!['queue'] as List);
    }
    return [];
  }

  // Method to get driver's total earnings for today
  Future<double> getDriverDailyEarnings(String driverId) async {
    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final endOfToday = startOfToday.add(const Duration(days: 1));

      final querySnapshot = await _firestore
          .collection('rideRequests')
          .where('driverId', isEqualTo: driverId)
          .where('status', isEqualTo: 'completed')
          .where('completedTime', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .where('completedTime', isLessThan: Timestamp.fromDate(endOfToday))
          .get();

      double totalEarnings = 0.0;
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        totalEarnings += (data['driverEarnings'] as num?)?.toDouble() ?? 0.0;
      }
      return totalEarnings;
    } catch (e) {
      debugPrint('Error fetching driver daily earnings: $e');
      return 0.0; // Return 0 on error
    }
  }

  // Get rideId based on kijiweId and userId
  Future<String?> getRideId(String kijiweId, String userId) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('rides')
          .where('kijiweId', isEqualTo: kijiweId)
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first.id;
      }
      return null;
    } catch (e) {
      print('Error fetching ride ID: $e');
      return null;
    }
  }

  // Get user role
  Future<String?> getUserRole(String userId) async {
    DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
    if (userDoc.exists) {
      return userDoc['role'];
    }
    return null;
  }

  // Get user currentUserId
  Future<String?> getCurrentUserId() async {
    final user = _auth.currentUser;
    if (user != null) {
      return user.uid;
    }
    return null;
  }

  // Get all Kijiwe documents
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> getAllKijiwes() async {
    try {
      final querySnapshot = await _firestore.collection('kijiwe').get();
      return querySnapshot.docs;
    } catch (e) {
      debugPrint("Error fetching all kijiwes: $e");
      rethrow;
    }
  }

  // Get nearby Kijiwes using GeoFlutterFire
  Stream<List<DocumentSnapshot>> getNearbyKijiwes(ll.LatLng center, double radiusInKm) {
    final collectionRef = getKijiweCollectionRef();
    final geoPointCenter = GeoPoint(center.latitude, center.longitude);

    // This stream can throw an error if any document in the result set has a null 'position.geopoint'.
    // The error should be handled by the listener in the UI.
    return geo.collection(collectionRef: collectionRef).within(
          center: geo.point(latitude: geoPointCenter.latitude, longitude: geoPointCenter.longitude),
          radius: radiusInKm,
          field: 'position', // The field in your document that contains the geohash/geopoint
          strictMode: true,
        );
  }

  // Helper to get Kijiwe collection reference for GeoFlutterFire
  CollectionReference<Map<String, dynamic>> getKijiweCollectionRef() {
    return _firestore.collection('kijiwe');
  }
  // Method to get adminId of a driver's Kijiwe
  Future<String?> getKijiweAdminIdForDriver(String driverId) async {
    final driverDoc = await _firestore.collection('users').doc(driverId).get();
    final kijiweId = driverDoc.data()?['driverProfile']?['kijiweId'] as String?;
    if (kijiweId != null) {
      final kijiweDoc = await _firestore.collection('kijiwe').doc(kijiweId).get();
      return kijiweDoc.data()?['adminId'] as String?;
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getKijiweList() async {
    try {
      final snapshot = await _firestore.collection('kijiwe').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] ?? 'Unnamed Kijiwe',
        };
      }).toList();
    } catch (e) {
      debugPrint('Error fetching kijiwe list from service: $e');
      rethrow;
    }
  }

  Future<String> registerDriver({
    required String userId,
    required String vehicleType,
    required String licenseNumber,
    required bool createNewKijiwe,
    String? newKijiweName,
    gmf.LatLng? newKijiweLocation,
    String? existingKijiweId,
    String? profileImageUrl,
  }) async {
    final geo = GeoFlutterFire();
    String kijiweIdToUse;

    WriteBatch batch = _firestore.batch();

    if (createNewKijiwe) {
      if (newKijiweName == null || newKijiweName.trim().isEmpty || newKijiweLocation == null) {
        throw ArgumentError("New Kijiwe name and location are required.");
      }

      final trimmedKijiweName = newKijiweName.trim();
      final existingKijiweQuery = await _firestore.collection('kijiwe').where('name', isEqualTo: trimmedKijiweName).limit(1).get();
      if (existingKijiweQuery.docs.isNotEmpty) {
        throw Exception("A Kijiwe with the name '$trimmedKijiweName' already exists.");
      }

      GeoFirePoint geoFirePoint = geo.point(latitude: newKijiweLocation.latitude, longitude: newKijiweLocation.longitude);
      final newKijiweDocRef = _firestore.collection('kijiwe').doc();
      batch.set(newKijiweDocRef, {
        'name': trimmedKijiweName,
        'position': geoFirePoint.data,
        'unionId': null,
        'adminId': userId,
        'permanentMembers': [userId],
        'createdAt': FieldValue.serverTimestamp(),
      });
      kijiweIdToUse = newKijiweDocRef.id;
    } else {
      if (existingKijiweId == null) {
        throw ArgumentError("Existing Kijiwe ID is required.");
      }
      kijiweIdToUse = existingKijiweId;
      final kijiweRef = _firestore.collection('kijiwe').doc(kijiweIdToUse);
      batch.update(kijiweRef, {
        'permanentMembers': FieldValue.arrayUnion([userId]),
      });
    }
    //
    final driverProfilePayload = {
      'driverId': userId, 'vehicleType': vehicleType, 'licenseNumber': licenseNumber, 'kijiweId': kijiweIdToUse,
      'registeredAt': FieldValue.serverTimestamp(), 'approved': true, 'isOnline': true, 'status': 'waitingForRide',
      'completedRidesCount': 0, 'cancelledByDriverCount': 0, 'declinedByDriverCount': 0,
      'sumOfRatingsReceived': 0, 'totalRatingsReceivedCount': 0, 'averageRating': 0.0,
    };

    final userRef = _firestore.collection('users').doc(userId);
    final userUpdatePayload = {'role': 'Driver', 'driverProfile': driverProfilePayload};
    if (profileImageUrl != null) {
      userUpdatePayload['profileImageUrl'] = profileImageUrl;
    }

    batch.update(userRef, userUpdatePayload);

    if (driverProfilePayload['isOnline'] == true) {
      final kijiweRef = _firestore.collection('kijiwe').doc(kijiweIdToUse);
      batch.update(kijiweRef, {'queue': FieldValue.arrayUnion([userId])});
    }

    await batch.commit();
    return kijiweIdToUse;
  }
}
