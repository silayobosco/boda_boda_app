import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/login_screen.dart';
import '../screens/driver_registration_screen.dart';

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
          _buildDriverButton(context),
        ],
      ),
    );
  }

    Widget _buildDriverButton(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      // Or return a disabled button, or nothing
      return const SizedBox.shrink();
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(
            leading: Icon(Icons.hourglass_empty),
            title: Text("Loading..."),
            enabled: false,
          );
        }

        if (snapshot.hasError) {
          debugPrint("Error fetching user for drawer button: ${snapshot.error}");
          return const ListTile(
            leading: Icon(Icons.error_outline),
            title: Text("Error loading status"),
            enabled: false,
          );
        }

        String currentRole = 'Customer'; // Default role
        Map<String, dynamic>? driverProfile;

        if (snapshot.hasData && snapshot.data!.exists) {
          final userData = snapshot.data!.data();
          if (userData != null) {
            currentRole = userData['role'] as String? ?? 'Customer';
            if (userData.containsKey('driverProfile') && userData['driverProfile'] is Map) {
              driverProfile = userData['driverProfile'] as Map<String, dynamic>?;
            }
          }
        }
        // If snapshot.data doesn't exist, user is treated as 'Customer'.

        final bool isCurrentlyDriver = currentRole == 'Driver'; // Check if the current role is 'Driver'
        // Check if they have a completed driver profile (using kijiweId as indicator)
        final bool hasCompletedDriverProfile = driverProfile?['kijiweId'] != null && (driverProfile!['kijiweId'] as String).isNotEmpty;

        final String buttonTitle = isCurrentlyDriver
            ? 'Switch to Customer' // If currently a Driver, offer to switch to Customer
            : hasCompletedDriverProfile // If not currently Driver, check if they have a completed profile
                ? 'Switch to Driver' // If they have a profile, offer to switch to Driver role
                : 'Become a Driver'; // If no profile, offer to register as a Driver

        return ListTile(
          leading: const Icon(Icons.switch_account),
          title: Text(buttonTitle),
          onTap: () async {
            // Close the drawer first if it's open
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }

            final userDocRef = FirebaseFirestore.instance.collection('users').doc(currentUser.uid);

            try {
              if (isCurrentlyDriver) {
                // Action: Switch from Driver to Customer
                await userDocRef.update({'role': 'Customer'});
                if (context.mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const HomeScreen()),
                  );
                }
              } else {
                // Action: Become a Driver (or switch from Customer to Driver)
                // Check for kijiweId in driverProfile
                final String? kijiweId = driverProfile?['kijiweId'] as String?;

                if (kijiweId != null && kijiweId.isNotEmpty) {
                  // Driver profile seems complete enough, just switch role
                  await userDocRef.update({'role': 'Driver'});
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const HomeScreen()),
                    );
                  }
                } else {
                  // Incomplete driver profile or no profile, navigate to registration
                  if (context.mounted) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const DriverRegistrationScreen()),
                    );
                  }
                }
              }
            } catch (e) {
              debugPrint("Error switching role: $e");
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to switch role: ${e.toString()}')),
                );
              }
            }
          },
        );
      },
    );
  }
}