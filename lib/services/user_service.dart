import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart'; // Import UserModel

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> createUserDocument(UserModel user) async {
    try {
      await _firestore.collection('users').doc(user.uid).set(user.toJson());
    } catch (e) {
      print("Error creating user document: $e");
      rethrow;
    }
  }

  Future<void> updateUserProfile(
    String userId,
    Map<String, dynamic> data,
  ) async {
    try {
      await _firestore.collection('users').doc(userId).update(data);
    } catch (e) {
      print('Error updating user profile: $e');
      rethrow;
    }
  }

  Future<UserModel?> getUserModel(String userId) async {
    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        return UserModel.fromJson(userDoc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      print('Error getting user document: $e');
      rethrow;
    }
  }
}
