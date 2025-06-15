import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/Ride_Request_Model.dart'; // Assuming you have this model
import '../services/auth_service.dart'; // To get current user
import '../widgets/chat_list_item.dart'; // Import the new ChatListItem
import 'chat_screen.dart'; // Import ChatScreen for admin chat
//import 'package:intl/intl.dart'; // For date formatting

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = Provider.of<AuthService>(context, listen: false).currentUser;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Chats'),
      ),
      body: _currentUser == null
          ? const Center(child: Text('Please log in to see your chats.'))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rideRequests')
                  .where('customerId', isEqualTo: _currentUser!.uid)
                  // Optionally, filter by statuses that make sense for active/recent chats
                  // .where('status', whereIn: ['accepted', 'goingToPickup', 'arrivedAtPickup', 'onRide', 'completed'])
                  .orderBy('requestTime', descending: true) // Show most recent rides first
                  .limit(20) // Limit the number of chats shown initially
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No recent ride chats found.'));
                }

                final rideDocs = snapshot.data!.docs;

                return ListView.separated(
                  itemCount: rideDocs.length + 1, // +1 for the Admin Chat ListTile
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // Admin Chat ListTile
                      const adminUid = "YOUR_ADMIN_UID_HERE"; // Replace with actual Admin UID
                      if (adminUid == "YOUR_ADMIN_UID_HERE") {
                        // Placeholder if admin UID is not set, to avoid errors.
                        // In a real app, you might fetch this from a config or hide the option.
                        return const ListTile(
                          leading: Icon(Icons.support_agent),
                          title: Text('Chat with Admin'),
                          subtitle: Text('Admin support not configured.'),
                          enabled: false,
                        );
                      }
                      return ListTile(
                        leading: Icon(Icons.support_agent, color: theme.colorScheme.primary),
                        title: const Text('Chat with Admin Support'),
                        trailing: Icon(Icons.chevron_right, color: theme.hintColor),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(
                                // Use a conventional ID for admin chats
                                rideRequestId: 'admin_chat_${_currentUser!.uid}',
                                recipientId: adminUid,
                                recipientName: 'Admin Support',
                              ),
                            ),
                          );
                        },
                      );
                    }
                    // Ride Chat ListItems
                    final rideDoc = rideDocs[index - 1]; // Adjust index for rideDocs
                    final ride = RideRequestModel.fromJson(rideDoc.data() as Map<String, dynamic>, rideDoc.id);

                    if (ride.driverId == null || ride.driverId!.isEmpty) {
                      return ListTile(
                        title: Text(ride.dropoffAddressName ?? 'Ride to Destination'),
                        subtitle: Text('Ride Status: ${ride.status} - No driver assigned yet.'),
                        leading: Icon(Icons.directions_car, color: theme.colorScheme.secondary),
                      );
                    }
                    return ChatListItem(
                      ride: ride,
                      currentUserId: _currentUser!.uid,
                    );
                  },
                );
              },
            ),
          );
  }
}
