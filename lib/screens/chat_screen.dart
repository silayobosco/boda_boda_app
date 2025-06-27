import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../utils/ui_utils.dart';
import 'package:intl/intl.dart';

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
  String? _currentUserId;
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _currentUserId = authService.currentUser?.uid;

    if (_currentUserId == null) {
      debugPrint("ChatScreen: CRITICAL - Current user is null. Chat will not function.");
    } else {
      _fetchCurrentUserRole();
    }
    // TODO: Implement logic to mark messages as read when screen is opened
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchCurrentUserRole() async {
    if (_currentUserId == null) return;
    try {
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
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    if (_currentUserId == null) {
      debugPrint("ChatScreen: Cannot send message, current user ID is not available.");
      return;
    }

    if (_currentUserRole == null) {
      await _fetchCurrentUserRole();
      if (_currentUserRole == null) {
        debugPrint("ChatScreen: Cannot send message, user role is not available.");
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not send message. User role unknown.")));
        return;
      }
    }

    _messageController.clear();

    try {
      await FirebaseFirestore.instance
          .collection('rideChats')
          .doc(widget.rideRequestId)
          .collection('messages')
          .add({
        'senderId': _currentUserId,
        'senderRole': _currentUserRole,
        'text': messageText,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      // Scroll to bottom after sending
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.minScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      debugPrint("Error sending message: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message. Please check permissions and try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_currentUserId == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text("Error: User not authenticated.")));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Chat with ${widget.recipientName}'),
        actions: [
          if (_currentUserRole == 'Customer')
            IconButton(
              icon: const Icon(Icons.support_agent_outlined),
              onPressed: () {
                // This is where you would implement the logic from the previous suggestion
                // to get the Kijiwe Admin ID and show a dialog to send a message.
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contact Kijiwe Admin - Not implemented yet.')),
                );
              },
              tooltip: 'Contact Kijiwe Admin',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('rideChats')
                  .doc(widget.rideRequestId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
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

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final messageData = messages[index].data() as Map<String, dynamic>;
                    final bool isMe = messageData['senderId'] == _currentUserId;
                    final bool isKijiweAdmin = messageData['senderRole'] == 'KijiweAdmin';

                    return _buildMessageItem(messageData, isMe, isKijiweAdmin);
                  },
                );
              },
            ),
          ),
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

  Widget _buildMessageItem(Map<String, dynamic> messageData, bool isMe, bool isKijiweAdmin) {
    final theme = Theme.of(context);
    final timeFormat = DateFormat('hh:mm a'); // e.g., 10:30 AM

    final text = messageData['text'] as String? ?? '';
    final timestamp = messageData['timestamp'] as Timestamp?;
    final displayTime = timestamp != null ? timeFormat.format(timestamp.toDate()) : '';

    Color bubbleColor;
    Color textColor;
    Alignment alignment;
    String? senderLabel;

    if (isKijiweAdmin) {
      bubbleColor = theme.colorScheme.tertiaryContainer;
      textColor = theme.colorScheme.onTertiaryContainer;
      alignment = Alignment.centerLeft;
      senderLabel = "Kijiwe Admin";
    } else if (isMe) {
      bubbleColor = theme.colorScheme.primary;
      textColor = theme.colorScheme.onPrimary;
      alignment = Alignment.centerRight;
    } else {
      bubbleColor = theme.colorScheme.surfaceVariant;
      textColor = theme.colorScheme.onSurfaceVariant;
      alignment = Alignment.centerLeft;
    }

    return Container(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (senderLabel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Text(
                    senderLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: textColor.withOpacity(0.8),
                    ),
                  ),
                ),
              Text(text, style: TextStyle(color: textColor, fontSize: 16)),
              if (displayTime.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(displayTime, style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7))),
                ),
            ],
          ),
      ),
    );
  }
}