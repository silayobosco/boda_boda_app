import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/Ride_Request_Model.dart';
import '../screens/chat_screen.dart'; // For navigation

class ChatListItem extends StatefulWidget {
  final RideRequestModel ride;
  final String currentUserId;
  final String currentUserRole;

  const ChatListItem({
    super.key,
    required this.ride,
    required this.currentUserId,
    required this.currentUserRole,
  });

  @override
  State<ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<ChatListItem> {
  Map<String, dynamic>? _lastMessage;
  bool _isLoadingLastMessage = true;

  @override
  void initState() {
    super.initState();
    _fetchLastMessage();
  }

  Future<void> _fetchLastMessage() async {
    if (widget.ride.id == null) {
      if (mounted) {
        setState(() {
          _isLoadingLastMessage = false;
        });
      }
      return;
    }
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('rideChats')
          .doc(widget.ride.id)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (mounted) {
        setState(() {
          if (querySnapshot.docs.isNotEmpty) {
            _lastMessage = querySnapshot.docs.first.data();
          }
          _isLoadingLastMessage = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching last message for ride ${widget.ride.id}: $e");
      if (mounted) {
        setState(() {
          _isLoadingLastMessage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDriver = widget.currentUserRole == 'Driver';
    final otherParticipantName = isDriver ? widget.ride.customerName : widget.ride.driverName;
    final otherParticipantId = isDriver ? widget.ride.customerId : widget.ride.driverId;
    final otherParticipantImageUrl = isDriver ? widget.ride.customerProfileImageUrl : widget.ride.driverProfileImageUrl;

    String subtitleText = 'Ride to: ${widget.ride.dropoffAddressName ?? 'Destination'}';
    String lastMessageTime = '';

    if (_isLoadingLastMessage) {
      subtitleText = 'Loading last message...';
    } else if (_lastMessage != null) {
      final messageText = _lastMessage!['text'] as String? ?? '';
      final messageTimestamp = _lastMessage!['timestamp'] as Timestamp?;
      final senderId = _lastMessage!['senderId'] as String?;

      final prefix = senderId == widget.currentUserId ? "You: " : "";
      subtitleText = '$prefix$messageText';

      if (messageTimestamp != null) {
        lastMessageTime = DateFormat('hh:mm a').format(messageTimestamp.toDate());
      }
    } else {
      subtitleText = 'No messages yet.';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: otherParticipantImageUrl != null && otherParticipantImageUrl.isNotEmpty
            ? NetworkImage(otherParticipantImageUrl)
            : null,
        child: otherParticipantImageUrl == null || otherParticipantImageUrl.isEmpty
            ? const Icon(Icons.person)
            : null,
      ),
      title: Text(otherParticipantName ?? (isDriver ? 'Customer' : 'Driver')),
      subtitle: Text(
        subtitleText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (lastMessageTime.isNotEmpty)
            Text(
              lastMessageTime,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          // TODO: Add unread indicator icon if needed
        ],
      ),
      onTap: () {
        if (widget.ride.id != null && otherParticipantId != null) {
          final bool isRideActiveForChat = ['accepted', 'goingToPickup', 'arrivedAtPickup', 'onRide'].contains(widget.ride.status);
          // Allow contacting admin if ride is completed within the last 24 hours
          final bool canContactAdmin = widget.ride.status == 'completed' &&
              widget.ride.completedTime != null &&
              DateTime.now().difference(widget.ride.completedTime!).inHours < 24;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                rideRequestId: widget.ride.id!,
                recipientId: otherParticipantId,
                recipientName: otherParticipantName ?? (isDriver ? 'Customer' : 'Driver'),
                isChatActive: isRideActiveForChat,
                canContactAdmin: canContactAdmin,
              ),
            ),
          );
        }
      },
    );
  }
}
