import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/Ride_Request_Model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../widgets/chat_list_item.dart';
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
        title: const Text('Chats'),
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
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline, size: 60, color: Theme.of(context).hintColor),
                            verticalSpaceMedium,
                            const Text(
                              'No active chats',
                              style: TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                            const Text(
                              'Chats for active rides will appear here.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      );
                    }

                    final allRides = snapshot.data!;
                    final activeChats = allRides.where((ride) => ['accepted', 'goingToPickup', 'arrivedAtPickup', 'onRide'].contains(ride.status)).toList();
                    final pastChats = allRides.where((ride) => ['completed', 'cancelled_by_customer', 'cancelled_by_driver'].contains(ride.status)).toList();

                    return CustomScrollView(
                      slivers: [
                        if (activeChats.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text('Active', style: Theme.of(context).textTheme.titleLarge),
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final ride = activeChats[index];
                                return ChatListItem(
                                  ride: ride,
                                  currentUserId: _currentUserId!,
                                  currentUserRole: _currentUserRole!,
                                );
                              },
                              childCount: activeChats.length,
                            ),
                          ),
                        ],
                        if (pastChats.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(16, activeChats.isNotEmpty ? 24 : 16, 16, 8),
                              child: Text('Past', style: Theme.of(context).textTheme.titleLarge),
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final ride = pastChats[index];
                                return ChatListItem(
                                  ride: ride,
                                  currentUserId: _currentUserId!,
                                  currentUserRole: _currentUserRole!,
                                );
                              },
                              childCount: pastChats.length,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
    );
  }
}