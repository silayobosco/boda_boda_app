import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'customer_home.dart';
import 'driver_home.dart';
import 'admin_home.dart';
import 'additional_info_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _navigatedToAdditionalInfo = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: getUserRole(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          _errorMessage = "Error: ${snapshot.error}";
          return Center(child: Text(_errorMessage!));
        }

        if (!snapshot.hasData || snapshot.data == null) {
          if (!_navigatedToAdditionalInfo) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _navigatedToAdditionalInfo = true;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => AdditionalInfoScreen(
                    userUid: FirebaseAuth.instance.currentUser!.uid,
                  ),
                ),
              );
            });
            return const Center(child: CircularProgressIndicator());
          }
          return const Center(child: CircularProgressIndicator());
        }

        String role = snapshot.data!;
        if (role == "Customer") return const CustomerHome();
        if (role == "Driver") return const DriverHome();
        if (role == "Admin") return const AdminHome();

        // Invalid Role: Redirect to Login
        _errorMessage = "Invalid Role: $role";
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pushReplacementNamed(context, '/login');
        });

        return Center(child: Text(_errorMessage!));
      },
    );
  }

  Future<String?> getUserRole() async {
    String uid = FirebaseAuth.instance.currentUser!.uid;
    DocumentSnapshot userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();

    if (userDoc.exists && userDoc.data() != null) {
      return userDoc['role'] as String?;
    }
    return null;
  }
}