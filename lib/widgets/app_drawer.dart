import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/profile_screen.dart';
import '../screens/login_screen.dart';
import '../screens/driver_registration_screen.dart';
import '../utils/ui_utils.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;

    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity, // Ensure the header spans the full width
            color: Colors.blue, // Background color for the header
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 40, // Adjust the size of the profile picture
                  backgroundImage: NetworkImage(
                    user?.photoURL ?? "https://via.placeholder.com/150",
                  ),
                  backgroundColor:
                      Colors.white, // Optional: Add a background color
                ),
                const SizedBox(height: 10), // Spacing between picture and name
                FutureBuilder<DocumentSnapshot>(
                  future:
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(user?.uid)
                          .get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Text(
                        "Loading...",
                        style: TextStyle(color: Colors.white),
                      );
                    }
                    if (snapshot.hasError) {
                      return const Text(
                        "Error loading user data",
                        style: TextStyle(color: Colors.white),
                      );
                    }
                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return const Text(
                        "Unknown User",
                        style: TextStyle(color: Colors.white),
                      );
                    }
                    return Text(
                      snapshot.data!['name'] ?? "Unknown User",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 5), // Spacing between name and email
                Text(
                  user?.email ?? "No email",
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
          ListTile( // Move "Profile" and other links up, before the driver button
            leading: const Icon(Icons.person),
            title: const Text("Profile"),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text("Settings"),
            onTap: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: const Text("Logout"),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
          ),
          const Spacer(), // Push the driver button to the bottom
          // "Become a Driver" or "Switch Role" Button
          _buildDriverButton(context, user),
        ],
      ),
    );
  }

  Widget _buildDriverButton(BuildContext context, User? user) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('drivers')
          .doc(user?.uid)
          .get(),
      builder: (context, snapshot) {
        String buttonText = "Become a Driver";
        VoidCallback? onPressed;

        if (snapshot.connectionState == ConnectionState.waiting) {
          buttonText = "Checking Driver Status...";
        } else if (snapshot.hasData && snapshot.data!.exists) {
          // User IS a driver, check their current role
          final isDriverActive = snapshot.data!['is_active'] ?? false; // Example field
          buttonText = isDriverActive ? "Switch to Customer" : "Switch to Driver";
          onPressed = () {
            // TODO: Implement role switching logic (e.g., update a 'role' field in the user or driver document)
            // For now, just print a message
            print("Role switch button pressed. Implement role switch here.");
          };
        } else {
          // User is NOT a driver
          onPressed = () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => DriverRegistrationScreen()),
            );
          };
        }

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            onPressed: onPressed,
            child: Text(buttonText),
          ),
        );
      },
    );
  }
}

