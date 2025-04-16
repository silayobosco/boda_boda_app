import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart'; // Import the UserModel class
import 'package:latlong2/latlong.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
      return snapshot.docs.map((doc) => RideRequestModel.fromJson(doc.data() as Map<String, dynamic>, doc.id)).toList();
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
      return snapshot.docs.map((doc) => RideHistoryModel.fromJson(doc.data() as Map<String, dynamic>, doc.id)).toList();
    });
  }

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
    return _firestore.collection('users').where('role', isEqualTo: 'driver').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => UserModel.fromJson(doc.data() as Map<String, dynamic>)).toList();
    });
  }
}
