import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/login_screen.dart';
import '../screens/about_us_screen.dart';
import '../screens/help_and_support_screen.dart';
import '../screens/driver_registration_screen.dart';
import '../screens/chat_list_screen.dart'; // Import ChatListScreen
import '../localization/locales.dart';

class AppDrawer extends StatelessWidget {
  final String userRole;

  const AppDrawer({super.key, required this.userRole});

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    final theme = Theme.of(context); // Define theme here

    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 20), // Adjusted padding for status bar
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 40, // Adjust the size of the profile picture
                  backgroundImage: user?.photoURL != null && user!.photoURL!.isNotEmpty
                      ? NetworkImage(user.photoURL!)
                      : null,
                  backgroundColor: theme.colorScheme.onPrimary.withOpacity(0.2),
                  child: user?.photoURL == null || user!.photoURL!.isEmpty
                      ? Icon(Icons.person, size: 40, color: theme.colorScheme.onPrimary)
                      : null,
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
                      return Text(
                        AppLocale.loading.getString(context),
                        style: TextStyle(color: theme.colorScheme.onPrimary),
                      );
                    }
                    if (snapshot.hasError) {
                      return Text(
                        AppLocale.errorLoadingUserData.getString(context),
                        style: TextStyle(color: theme.colorScheme.onPrimary),
                      );
                    }
                    if (!snapshot.hasData || !snapshot.data!.exists) {
                      return Text(
                        AppLocale.unknownUser.getString(context),
                        style: TextStyle(color: theme.colorScheme.onPrimary),
                      );
                    }
                    return Text(
                      snapshot.data!['name'] ?? "Unknown User",
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 5), // Spacing between name and email
                Text(
                  user?.email ?? AppLocale.noEmail.getString(context),
                  style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.8), fontSize: 14),
                ),
              ],
            ),
          ),
          ListTile( // Move "Profile" and other links up, before the driver button
            leading: const Icon(Icons.person),
            title: Text(AppLocale.profile.getString(context)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text(AppLocale.chats.getString(context)),
            onTap: () {
              Navigator.of(context).pop(); // Close drawer
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ChatListScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(AppLocale.settings.getString(context)),
            onTap: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: Text(AppLocale.helpSupport.getString(context)),
            onTap: () {
              Navigator.of(context).pop(); // Close drawer
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => HelpAndSupportScreen(userRole: userRole)),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(AppLocale.aboutUs.getString(context)),
            onTap: () {
              Navigator.of(context).pop(); // Close drawer
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutUsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.exit_to_app),
            title: Text(AppLocale.logout.getString(context)),
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
            leading: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            title: Text("Loading..."), // This is fine as it's temporary
            enabled: false,
          );
        }

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          // If there's an error or no data, don't allow switching roles
          return ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(AppLocale.unableToLoadDriverStatus.getString(context)),
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
            ? AppLocale.switchToCustomer.getString(context)
            : hasCompletedDriverProfile
                ? AppLocale.switchToDriver.getString(context)
                : AppLocale.becomeADriver.getString(context);

        // Only show the button if the user has a completed driver profile or is already a driver
        if (!isCurrentlyDriver && !hasCompletedDriverProfile) {
          // Only allow registration, not switching, if not completed
          return ListTile(
            leading: const Icon(Icons.directions_bike),
            title: Text(AppLocale.becomeADriver.getString(context)),
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
                  SnackBar(content: Text('${AppLocale.failedToSwitchRole.getString(context)}: ${e.toString()}')),
                );
              }
            }
          },
        );
      },
    );
  }
}