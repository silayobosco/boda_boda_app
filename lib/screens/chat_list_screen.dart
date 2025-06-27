import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/Ride_Request_Model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'chat_screen.dart';
import '../utils/ui_utils.dart'; // For styling

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  String? _currentUserId;
  String? _currentUserRole;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    // Use listen:false in initState
    final authService = Provider.of<AuthService>(context, listen: false);
    _currentUserId = authService.currentUser?.uid;
    if (_currentUserId != null) {
      _currentUserRole = await _firestoreService.getUserRole(_currentUserId!);
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Stream<List<RideRequestModel>> _getActiveChatsStream() {
    if (_currentUserId == null || _currentUserRole == null) {
      return Stream.value([]);
    }

    final fieldToQuery = _currentUserRole == 'Driver' ? 'driverId' : 'customerId';
    const activeStatuses = ['accepted', 'goingToPickup', 'arrivedAtPickup', 'onRide'];
    const pastStatuses = ['completed', 'cancelled_by_customer', 'cancelled_by_driver'];
    
    return FirebaseFirestore.instance
        .collection('rideRequests')
        .where(fieldToQuery, isEqualTo: _currentUserId)
        .where('status', whereIn: [...activeStatuses, ...pastStatuses]) // Combine both status sets
        .orderBy('requestTime', descending: true) // Order by request time to show recent rides first
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RideRequestModel.fromJson(doc.data(), doc.id))
            .toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Chats'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentUserId == null || _currentUserRole == null
              ? const Center(child: Text('Could not load user data.'))
              : StreamBuilder<List<RideRequestModel>>(
                  stream: _getActiveChatsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey),
                            verticalSpaceMedium,
                            Text(
                              'No active chats',
                              style: TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                            Text(
                              'Chats for active rides will appear here.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }

                    final activeRides = snapshot.data!;

                    return ListView.builder(
                      itemCount: activeRides.length,
                      itemBuilder: (context, index) {
                        final ride = activeRides[index];
                        final isDriver = _currentUserRole == 'Driver';
                        
                        final recipientId = isDriver ? ride.customerId : ride.driverId;
                        final recipientName = isDriver ? ride.customerName : ride.driverName;
                        final recipientImageUrl = isDriver ? ride.customerProfileImageUrl : ride.driverProfileImageUrl;
                        
                        // A ride might be accepted before driver details are fully denormalized.
                        if (recipientId == null || recipientName == null) {
                          return const ListTile(
                            leading: CircleAvatar(child: Icon(Icons.person)),
                            title: Text("Loading chat..."),
                            subtitle: Text("Ride accepted"),
                          );
                        }

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: recipientImageUrl != null && recipientImageUrl.isNotEmpty
                                ? NetworkImage(recipientImageUrl)
                                : null,
                            child: recipientImageUrl == null || recipientImageUrl.isEmpty
                                ? const Icon(Icons.person)
                                : null
                          ),
                          title: Text(recipientName),
                          subtitle: Text('Ride to: ${ride.dropoffAddressName ?? 'Destination'}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(
                                  rideRequestId: ride.id!,
                                  recipientId: recipientId,
                                  recipientName: recipientName,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
    );
  }
}