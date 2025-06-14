import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart'; // To get current user's ID
import '../utils/ui_utils.dart'; // For styling
//import '../services/firestore_service.dart'; // For fetching user role
import 'package:intl/intl.dart'; // For date formatting

class ChatScreen extends StatefulWidget {
  final String rideRequestId;
  final String recipientId; // UID of the other user (customer or driver)
  final String recipientName;

  const ChatScreen({
    super.key,
    required this.rideRequestId,
    required this.recipientId,
    required this.recipientName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late String _currentUserId;
  String? _currentUserRole; // To store the fetched role

  @override
  void initState() {
    super.initState();
    // Safely access currentUserId
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser?.uid != null) {
      _currentUserId = authService.currentUser!.uid;
    } else {
      // Fallback or error handling if user is not logged in.
      // For a chat screen, this would ideally prevent the screen from loading
      // or show an error message. For now, setting to an empty string.
      _currentUserId = ''; 
      debugPrint("ChatScreen: Error - Current user is null. Chat functionality might be impaired.");
    }
    _fetchCurrentUserRole();
    // TODO: Implement logic to mark messages as read when screen is opened
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentUserRole() async {
    if (_currentUserId.isEmpty) return;
    try {
      // Assuming FirestoreService has a method to get user data or role
      // If not, we can directly query Firestore here.
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(_currentUserId).get();
      if (userDoc.exists && userDoc.data() != null) {
        if (mounted) {
          setState(() {
            _currentUserRole = userDoc.data()!['role'] as String?;
          });
        }
      }
    } catch (e) { debugPrint("ChatScreen: Error fetching user role: $e"); }
  }
  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    if (_currentUserId.isEmpty) {
      // Prevent sending message if user ID is not available
      debugPrint("ChatScreen: Cannot send message, current user ID is not available.");
      return;
    }
    if (_currentUserRole == null) {
      await _fetchCurrentUserRole(); // Attempt to fetch role if not already available
      if (_currentUserRole == null) {
        debugPrint("ChatScreen: Cannot send message, user role is not available.");
        // Optionally show a SnackBar to the user
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not send message. User role unknown.")));
        return;
      }
    }
    final messageText = _messageController.text.trim();
    _messageController.clear();

    await FirebaseFirestore.instance
        .collection('rideChats')
        .doc(widget.rideRequestId)
        .collection('messages')
        .add({
      'senderId': _currentUserId,
      'senderRole': _currentUserRole, // Use the fetched role
      'text': messageText,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false, // Initially false
    });

    // TODO: Trigger FCM notification to the recipient

    // Scroll to bottom after sending
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check mounted before interacting with scrollController
      if (mounted && _scrollController.hasClients) { 
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent, // Correct for reversed list
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat with ${widget.recipientName}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rideChats')
                  .doc(widget.rideRequestId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true) // Show newest messages at the bottom
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No messages yet. Start the conversation!'));
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final messages = snapshot.data!.docs;

                // Scroll to bottom when new messages arrive or view is built
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  // Check mounted before interacting with scrollController
                  if (mounted && _scrollController.hasClients) { 
                    _scrollController.jumpTo(_scrollController.position.minScrollExtent); // Correct for reversed list
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // To keep input field at bottom and messages loading from bottom-up
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final messageData = messages[index].data() as Map<String, dynamic>;
                    final bool isMe = messageData['senderId'] == _currentUserId;
                    return _buildMessageItem(
                      messageData['text'] as String? ?? '',
                      messageData['timestamp'] as Timestamp?,
                      isMe,
                    );
                  },
                );
              },
            ),          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: appInputDecoration(hintText: 'Type a message...'),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: theme.colorScheme.primary),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(String text, Timestamp? timestamp, bool isMe) {
    final theme = Theme.of(context);
    final timeFormat = DateFormat('hh:mm a'); // e.g., 10:30 AM
    final String displayTime = timestamp != null ? timeFormat.format(timestamp.toDate()) : '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: isMe ? theme.colorScheme.primary : theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: isMe ? const Radius.circular(12) : const Radius.circular(0),
            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(12),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              style: TextStyle(
                color: isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSecondaryContainer,
              ),
            ),
            if (displayTime.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                displayTime,
                style: TextStyle(
                  fontSize: 10,
                  color: isMe
                      ? theme.colorScheme.onPrimary.withOpacity(0.7)
                      : theme.colorScheme.onSecondaryContainer.withOpacity(0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}