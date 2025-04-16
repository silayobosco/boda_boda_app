import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/profile_screen.dart';
import '../screens/login_screen.dart';

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
          ListTile(
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
        ],
      ),
    );
  }
}
