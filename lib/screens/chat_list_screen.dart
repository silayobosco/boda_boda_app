import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/Ride_Request_Model.dart'; // Assuming you have this model
import '../services/auth_service.dart'; // To get current user
import '../widgets/chat_list_item.dart'; // Import the new ChatListItem
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

                return ListView.builder(
                  itemCount: rideDocs.length,
                  itemBuilder: (context, index) {
                    final rideDoc = rideDocs[index];
                    // Assuming RideRequestModel.fromJson can handle this data
                    final ride = RideRequestModel.fromJson(rideDoc.data() as Map<String, dynamic>, rideDoc.id);

                    // Only show chat option if there's a driver assigned
                    if (ride.driverId == null || ride.driverId!.isEmpty) {
                      return ListTile(
                        title: Text(ride.dropoffAddressName ?? 'Ride to Destination'),
                        subtitle: Text('Ride Status: ${ride.status} - No driver assigned yet.'),
                        leading: Icon(Icons.directions_car, color: theme.colorScheme.secondary),
                      );
                    }
                    // Use the new ChatListItem widget
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
