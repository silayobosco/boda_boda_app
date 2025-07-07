import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../screens/profile_screen.dart';
import '../screens/about_us_screen.dart';
import '../screens/help_and_support_screen.dart';
import '../screens/chat_list_screen.dart'; // Import ChatListScreen
import '../utils/account_utils.dart'; // Import the new utility
import '../localization/locales.dart';

class AppDrawer extends StatelessWidget {
  final String userRole;
  final String userName;
  final String? userEmail;
  final String? photoUrl;

  const AppDrawer({
    super.key, 
    required this.userRole,
    required this.userName,
    this.userEmail,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
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
                  backgroundImage: photoUrl != null && photoUrl!.isNotEmpty
                      ? NetworkImage(photoUrl!)
                      : null,
                  backgroundColor: theme.colorScheme.onPrimary.withOpacity(0.2),
                  child: photoUrl == null || photoUrl!.isEmpty
                      ? Icon(Icons.person, size: 40, color: theme.colorScheme.onPrimary)
                      : null,
                ),
                const SizedBox(height: 10), // Spacing between picture and name
                Text(
                  userName,
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5), // Spacing between name and email
                Text(
                  userEmail ?? AppLocale.noEmail.getString(context),
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
        AccountUtils.showLogoutConfirmationDialog(context, userRole: userRole);
      },
    );
  }
}