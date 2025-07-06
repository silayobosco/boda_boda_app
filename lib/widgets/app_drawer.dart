import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:provider/provider.dart';
import '../screens/profile_screen.dart';
import '../screens/login_screen.dart';
import '../screens/about_us_screen.dart';
import '../screens/help_and_support_screen.dart';
import '../providers/driver_provider.dart';
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
          const Spacer(), // Pushes the logout button to the bottom
          const Divider(),
          _buildLogoutButton(context),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.exit_to_app),
      title: Text(AppLocale.logout.getString(context)),
      onTap: () {
        // Close the drawer first
        Navigator.of(context).pop();
        // Show confirmation dialog
        _showLogoutConfirmationDialog(context);
      },
    );
  }

  void _showLogoutConfirmationDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocale.logout.getString(context)),
        content: Text(AppLocale.logout_confirmation.getString(context)),
        actions: [
          TextButton(
            child: Text(AppLocale.dialog_cancel.getString(context), style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.7))),
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: Text(AppLocale.logout.getString(context)),
            onPressed: () async {
              // Close dialog
              Navigator.of(dialogContext).pop();

              // Capture context-dependent objects before async gap
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

              try {
                // If user is a driver, make them offline first
                if (userRole == 'Driver') {
                  final driverProvider = Provider.of<DriverProvider>(context, listen: false);
                  if (driverProvider.isOnline) {
                    await driverProvider.toggleOnlineStatus();
                  }
                }

                // Sign out from Firebase
                await FirebaseAuth.instance.signOut();

                // Navigate to login screen
                if (!context.mounted) return;
                navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
              } catch (e) {
                debugPrint("Error during logout: $e");
                if (context.mounted) {
                  scaffoldMessenger.showSnackBar(SnackBar(content: Text('${AppLocale.error_logging_out.getString(context)}: ${e.toString()}')));
                }
              }
            },
          ),
        ],
      ),
    );
  }
}