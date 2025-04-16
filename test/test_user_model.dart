import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:boda_boda/models/user_model.dart';


Future<void> main() async {
  // Initialize Firebase
  await Firebase.initializeApp();

  // Test Firestore document fetching
  String testUserId = "your_test_user_id"; // Replace with a valid user ID from Firestore
  DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(testUserId).get();

  if (userDoc.exists) {
    print("Firestore Document Data: ${userDoc.data()}");

    // Test UserModel.fromJson
    UserModel user = UserModel.fromJson(userDoc.data() as Map<String, dynamic>);
    print("UserModel Data:");
    print("UID: ${user.uid}");
    print("Name: ${user.name}");
    print("Phone Number: ${user.phoneNumber}");
    print("Date of Birth: ${user.dob}");
    print("Gender: ${user.gender}");
    print("Location: ${user.location}");
    print("Profile Image URL: ${user.profileImageUrl}");
    print("Email: ${user.email}");
    print("Role: ${user.role}");

    // Test UserModel.toJson
    Map<String, dynamic> userMap = user.toJson();
    print("Converted Back to Firestore-Compatible Map:");
    print(userMap);
  } else {
    print("User document does not exist.");
  }
}