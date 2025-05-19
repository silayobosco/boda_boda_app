import 'package:boda_boda/models/Ride_Request_Model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart'; // Import the UserModel class
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart';

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

  // Ride History

  Future<void> createRideHistory(RideHistoryModel rideHistory) async {
    try {
      await _firestore.collection('rideHistory').add(rideHistory.toJson());
    } catch (e) {
      print('Error creating ride history: $e');   
      rethrow;
    }
  }

  Stream<List<RideHistoryModel>> getRideHistory(String userId) {
    return _firestore
        .collection('rideHistory')
        .where('customerId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => RideHistoryModel.fromJson(doc.data(), doc.id)).toList();
    });
  }

  // scheduleRide

  // User Location Updates

  Future<void> updateUserLocation(String userId, LatLng location) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'location': GeoPoint(location.latitude, location.longitude),
      });
    } catch (e) {
      print('Error updating user location: $e');
      rethrow;
    }
  }

  Stream<DocumentSnapshot> getUserLocationStream(String userId) {
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

  // Helper to get Kijiwe collection reference for GeoFlutterFire
  CollectionReference<Map<String, dynamic>> getKijiweCollectionRef() {
    return _firestore.collection('kijiwe');
  }
}
