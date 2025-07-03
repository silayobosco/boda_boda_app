import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../utils/ui_utils.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final String? rideRequestId;
  final String? directChatId;
  final String recipientId; // UID of the other user (customer or driver)
  final String recipientName;
  final bool isChatActive;
  final bool canContactAdmin;

  const ChatScreen({
    super.key,
    required this.rideRequestId,
    required this.recipientId,
    required this.recipientName,
    this.isChatActive = true,
    this.canContactAdmin = false,
  }) : directChatId = null;

  const ChatScreen.direct({
    super.key,
    required this.directChatId,
    required this.recipientId,
    required this.recipientName,
  })  : rideRequestId = null,
        isChatActive = true,
        canContactAdmin = false;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  late final DocumentReference _chatDocRef;
  String? _currentUserId;
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _currentUserId = authService.currentUser?.uid;

    // Initialize _chatDocRef first, as other methods in initState depend on it.
    if (widget.rideRequestId != null) {
      _chatDocRef = FirebaseFirestore.instance
          .collection('rideChats')
          .doc(widget.rideRequestId);
    } else {
      _chatDocRef = FirebaseFirestore.instance
          .collection('directChats')
          .doc(widget.directChatId);
    }

    if (_currentUserId == null) {
      debugPrint("ChatScreen: CRITICAL - Current user is null. Chat will not function.");
    } else {
      _fetchCurrentUserRole();
      _markMessagesAsRead(); // Mark messages as read when entering the screen
    }
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
      await _chatDocRef.collection('messages')
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

  Future<void> _markMessagesAsRead() async {
    if (_currentUserId == null) return;

    // Query for unread messages from the other user
    final querySnapshot = await _chatDocRef
        .collection('messages')
        .where('senderId', isNotEqualTo: _currentUserId)
        .where('isRead', isEqualTo: false)
        .get();

    if (querySnapshot.docs.isEmpty) {
      // No unread messages to mark.
      return;
    }

    // Use a batch to update all documents at once for efficiency
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in querySnapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    try {
      await batch.commit();
      debugPrint("ChatScreen: Marked ${querySnapshot.docs.length} messages as read.");
    } catch (e) {
      debugPrint("ChatScreen: Error marking messages as read: $e");
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
          if (widget.canContactAdmin)
            IconButton(
              icon: const Icon(Icons.support_agent_outlined),
              onPressed: _contactKijiweAdmin,
              tooltip: 'Contact Kijiwe Admin',
            ),
        ],      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _chatDocRef.collection('messages')
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
                    enabled: widget.isChatActive,
                    decoration: appInputDecoration(hintText: widget.isChatActive ? 'Type a message...' : 'Chat is disabled for this ride.'),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: theme.colorScheme.primary),
                  onPressed: widget.isChatActive ? _sendMessage : null,
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
              if (displayTime.isNotEmpty) // Show time and read receipt
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(displayTime, style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.7))),
                        if (isMe) ...[
                          horizontalSpaceSmall,
                          Icon(
                            messageData['isRead'] == true ? Icons.done_all : Icons.done,
                            size: 16,
                            color: messageData['isRead'] == true ? accentColor : textColor.withOpacity(0.7),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
            ],
          ),
      ),
    );
  }

  Future<void> _contactKijiweAdmin() async {
    // This logic assumes the recipient of the chat is the driver
    final String driverId = widget.recipientId;
    final String? adminId = await _firestoreService.getKijiweAdminIdForDriver(driverId);

    if (!mounted) return;

    if (adminId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not find Kijiwe admin for this driver.')),
      );
      return;
    }

    // Show a dialog to compose the message
    final messageController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Message Kijiwe Admin"),
        content: TextField(
          controller: messageController,
          decoration: appInputDecoration(hintText: "Your message..."),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              final text = messageController.text.trim();
              if (text.isNotEmpty) {
                // Send the message with the current user's ID but a special role
                // to distinguish it in the chat UI.
                await FirebaseFirestore.instance.collection('rideChats').doc(widget.rideRequestId).collection('messages').add({
                  'senderId': _currentUserId,
                  'senderRole': 'KijiweAdmin', // This indicates it's a message *to* the admin, but we'll style it as if from them for clarity
                  'text': text,
                  'timestamp': FieldValue.serverTimestamp(),
                  'isRead': false,
                });
                Navigator.pop(dialogContext);
              }
            },
            child: const Text("Send"),
          ),
        ],
      ),
    );
  }
}