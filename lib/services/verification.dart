import '../screens/additional_info_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthVerificationService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ✅ Email Verification
  Future<void> sendEmailVerification() async {
    User? user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
      print("Verification email sent.");
    }
  }

  // ✅ Phone Verification
  Future<void> verifyPhoneNumber(
    BuildContext context,
    String phoneNumber,
  ) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
        print("Phone number automatically verified!");
      },
      verificationFailed: (FirebaseAuthException e) {
        print("Phone verification failed: ${e.message}");
      },
      codeSent: (String verificationId, int? resendToken) {
        print("OTP sent to $phoneNumber");
        // Store verificationId for manual entry
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        print("Phone verification timeout.");
      },
    );
  }
}

void navigateToAdditionalInfo(BuildContext context, User user) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => AdditionalInfoScreen(userUid: user.uid)),
  );
}
