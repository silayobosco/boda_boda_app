import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../screens/additional_info_screen.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  User? get currentUser => _auth.currentUser;

  // ... (registerUser, loginUser, logout functions remain the same)

  // ✅ Universal Google Sign-In (Detects Web or Mobile)
  Future<User?> signInWithGoogle(BuildContext context) async {
    if (kIsWeb) {
      return await signInWithGoogleWeb(context);
    } else {
      return await signInWithGoogleMobile(context);
    }
  }

  // ✅ Web Google Sign-In
  Future<User?> signInWithGoogleWeb(BuildContext context) async {
    try {
      GoogleAuthProvider googleProvider = GoogleAuthProvider();
      UserCredential userCredential =
          await _auth.signInWithPopup(googleProvider);
      User? user = userCredential.user;
      if (user != null) {
        await _handleGoogleSignInUser(user, context);
      }
      return user;
    } catch (e) {
      print("Google Sign-In Web Error: $e");
      return null;
    }
  }

  // ✅ Mobile Google Sign-In (Android & iOS)
  Future<User?> signInWithGoogleMobile(BuildContext context) async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      User? user = userCredential.user;
      if (user != null) {
        await _handleGoogleSignInUser(user, context);
      }
      return user;
    } catch (e) {
      print("Google Sign-In Mobile Error: $e");
      return null;
    }
  }

  Future<void> _handleGoogleSignInUser(User user, BuildContext context) async {
    DocumentSnapshot userDoc =
        await _firestore.collection('users').doc(user.uid).get();

    if (!userDoc.exists) {
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'name': user.displayName,
        'email': user.email,
        'photoURL': user.photoURL,
        'role': 'customer', // set default role to customer
        'phoneNumber': null,
        'dob': null,
        'gender': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AdditionalInfoScreen(userUid: user.uid), // Pass user UID
        ),
      );
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb) {
      await _googleSignIn.signOut();
    }
  }
}