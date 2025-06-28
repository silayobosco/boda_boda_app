import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/login_screen.dart';
import '../screens/driver_registration_screen.dart';
import '../screens/chat_list_screen.dart'; // Import ChatListScreen

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context); // Define theme here

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
            leading: Icon(Icons.chat_bubble_outline, color: theme.colorScheme.secondary),
            title: Text('Chats', style: theme.textTheme.titleMedium),
            onTap: () {
              Navigator.of(context).pop(); // Close drawer
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ChatListScreen()));
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
              final navigator = Navigator.of(context); // Capture navigator before await
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) return; // Check if widget is still in the tree
              navigator.pushReplacement( // Use the captured navigator
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

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          // If there's an error or no data, don't allow switching roles
          return const ListTile(
            leading: Icon(Icons.error_outline),
            title: Text("Unable to load driver status"),
            enabled: false,
          );
        }

        String currentRole = 'Customer';
        Map<String, dynamic>? driverProfile;

        final userData = snapshot.data!.data();
        if (userData != null) {
          currentRole = userData['role'] as String? ?? 'Customer';
          if (userData.containsKey('driverProfile') && userData['driverProfile'] is Map) {
            driverProfile = userData['driverProfile'] as Map<String, dynamic>?;
          }
        }

        final bool isCurrentlyDriver = currentRole == 'Driver';
        final bool hasCompletedDriverProfile = driverProfile?['kijiweId'] != null && (driverProfile!['kijiweId'] as String).isNotEmpty;

        final String buttonTitle = isCurrentlyDriver
            ? 'Switch to Customer'
            : hasCompletedDriverProfile
                ? 'Switch to Driver'
                : 'Become a Driver';

        // Only show the button if the user has a completed driver profile or is already a driver
        if (!isCurrentlyDriver && !hasCompletedDriverProfile) {
          // Only allow registration, not switching, if not completed
          return ListTile(
            leading: const Icon(Icons.directions_bike),
            title: const Text('Become a Driver'),
            onTap: () {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DriverRegistrationScreen()),
              );
            },
          );
        }

        return ListTile(
          leading: const Icon(Icons.switch_account),
          title: Text(buttonTitle),
          onTap: () async {
            // Capture context-dependent objects before the async gap
            final navigator = Navigator.of(context);
            final scaffoldMessenger = ScaffoldMessenger.of(context);

            if (navigator.canPop()) navigator.pop(); // Pop the drawer first

            final userDocRef = FirebaseFirestore.instance.collection('users').doc(currentUser.uid);

            try {
              if (isCurrentlyDriver) {
                await userDocRef.update({'role': 'Customer'});
              } else {
                await userDocRef.update({'role': 'Driver'});
              }
              // After the await, check if the widget is still mounted before navigating
              if (!context.mounted) return;
              navigator.pushReplacement(
                MaterialPageRoute(builder: (context) => const HomeScreen()),
              );
            } catch (e) {
              debugPrint("Error switching role: $e");
              if (context.mounted) { // Check mounted before showing SnackBar
                scaffoldMessenger.showSnackBar(
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