import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../screens/additional_info_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  User? get currentUser => _auth.currentUser;
  
  // Request notification permissions and get/save FCM token
  Future<void> initializeFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // Request permission
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted notification permission');
      await getAndSaveFCMToken();

      // Listen for token refreshes
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        debugPrint('FCM Token refreshed: $newToken');
        saveFCMTokenToFirestore(newToken);
      });

    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      debugPrint('User granted provisional notification permission');
      // Handle provisional authorization if needed
    } else {
      debugPrint('User declined or has not accepted notification permission');
    }
  }

  Future<void> getAndSaveFCMToken() async {
    String? token;
    if (!kIsWeb) { // FCM token generation is different for web
      token = await FirebaseMessaging.instance.getToken();
    }
    // For web, you might need to use getToken(vapidKey: "YOUR_VAPID_KEY")
    // Ensure your UserModel and FirestoreService can handle saving this token.
    debugPrint("FCM Token: $token");
    if (token != null) {
      await saveFCMTokenToFirestore(token);
    }
  }

  Future<void> saveFCMTokenToFirestore(String token) async {
    User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      try {
        await _firestore.collection('users').doc(currentUser.uid).update({'fcmToken': token});
        debugPrint('FCM token saved to Firestore for user ${currentUser.uid}');
      } catch (e) {
        debugPrint('Error saving FCM token to Firestore: $e');
      }
    }
  }

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
      // Save FCM token after sign-in
      await initializeFCM(); // Initialize FCM after successful login
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