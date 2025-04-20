import 'package:boda_boda/models/Ride_Request_Model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart'; // Import the UserModel class
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance; // Add this line

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
Future<void> createRideRequest(RideRequestModel rideRequest) async {
    try {
      await _firestore.collection('rideRequests').add(rideRequest.toJson());
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

  Future<void> updateRideRequestStatus(String rideRequestId, String status, {String? driverId}) async {
    try {
      Map<String, dynamic> updateData = {'status': status};
      if (driverId != null) {
        updateData['driverId'] = driverId;
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
  await _firestore.collection('KijiweQueues').doc(kijiweId).update({
    'driverIds': FieldValue.arrayUnion([userId])
  });
}

Future<void> leaveKijiweQueue(String kijiweId, String userId) async {
  await _firestore.collection('KijiweQueues').doc(kijiweId).update({
    'driverIds': FieldValue.arrayRemove([userId])
  });
}

Stream<DocumentSnapshot> getKijiweQueueStream(String kijiweId) {
  return _firestore.collection('KijiweQueues').doc(kijiweId).snapshots();
}

Future<void> updateDriverAvailability(String userId, bool available) async {
  await _firestore.collection('Users').doc(userId).update({
    'driverDetails.available': available
  });
}

// Add this method to get the queue for a specific Kijiwe
  Future<List<DocumentSnapshot>> getKijiweQueue(String kijiweId) async {
    final queueCollection = FirebaseFirestore.instance
        .collection('kijiwes')
        .doc(kijiweId)
        .collection('queue');
    final querySnapshot = await queueCollection.get();
    return querySnapshot.docs;
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

  // Register as driver
  // This function updates the user's role to 'driver' and adds driver details to Firestore
  Future<void> registerAsDriver({
    required String userId,
    required String vehicleType,
    required String licenseNumber,
    required String kijiweId,
  }) async {
    await _firestore.collection('users').doc(userId).update({
      'role': 'Driver',
      'driverDetails': {
        'vehicle': vehicleType,
        'licenseNumber': licenseNumber,
        'kijiweId': kijiweId,
        'available': false,
        'rating': 0,
        'status': 'offline'
      }
    });
  }

  Future<void> updateDriverStatus({
    required String userId,
    required bool available,
    String? kijiweId,
  }) async {
    final updateData = {
      'driverDetails.available': available,
      'driverDetails.status': available ? 'available' : 'offline',
      if (kijiweId != null) 'driverDetails.kijiweId': kijiweId,
    };

    await _firestore.collection('users').doc(userId).update(updateData);
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
}

