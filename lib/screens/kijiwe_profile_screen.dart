import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/ui_utils.dart'; // For spacing and styling
import 'chat_screen.dart';
import '../localization/locales.dart';

class KijiweProfileScreen extends StatefulWidget {
  final String kijiweId;

  const KijiweProfileScreen({super.key, required this.kijiweId});

  @override
  State<KijiweProfileScreen> createState() => _KijiweProfileScreenState();
}

class _KijiweProfileScreenState extends State<KijiweProfileScreen> {
  String? _currentUserId;
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final userId = authService.currentUser?.uid;
    if (userId != null) {
      final role = await firestoreService.getUserRole(userId);
      if (mounted) {
        setState(() {
          _currentUserId = userId;
          _currentUserRole = role;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocale.kijiweProfile.getString(context)),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: firestoreService.getKijiweQueueStream(widget.kijiweId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Kijiwe not found.'));
          }

          final kijiweData = snapshot.data!.data() as Map<String, dynamic>;
          final kijiweName = kijiweData['name'] as String? ?? 'Unnamed Kijiwe';
          final List<String> queue = List<String>.from(kijiweData['queue'] ?? []);
          final List<String> permanentMembers = List<String>.from(kijiweData['permanentMembers'] ?? []);
          final position = kijiweData['position']?['geopoint'] as GeoPoint?;
          final adminId = kijiweData['adminId'] as String?;

          // Separate online members (in queue) from offline permanent members
          final otherMembers = permanentMembers.where((id) => !queue.contains(id)).toList();

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Text(
                kijiweName,
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              verticalSpaceMedium,
              if (position != null)
                SizedBox(
                  height: 200,
                  child: AbsorbPointer(
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(position.latitude, position.longitude),
                        zoom: 15,
                      ),
                      markers: {
                        Marker(
                          markerId: MarkerId(widget.kijiweId),
                          position: LatLng(position.latitude, position.longitude),
                        ),
                      },
                    ),
                  ),
                ),
              verticalSpaceLarge,
              ExpansionTile(
                title: Text(AppLocale.kijiweQueue.getString(context), style: theme.textTheme.titleLarge),
                leading: const Icon(Icons.motorcycle_outlined),
                initiallyExpanded: true,
                children: queue.isEmpty
                    ? [const ListTile(title: Text('No drivers currently online in the queue.'))]
                    : queue.map((memberId) => _buildMemberTile(memberId, memberId == adminId, true)).toList(),
              ),
              ExpansionTile(
                title: Text(AppLocale.otherMembers.getString(context), style: theme.textTheme.titleLarge),
                leading: const Icon(Icons.group_outlined),
                children: otherMembers.isEmpty
                    ? [const ListTile(title: Text('No other permanent members.'))]
                    : otherMembers.map((memberId) => _buildMemberTile(memberId, memberId == adminId, false)).toList(),
              ),
              verticalSpaceLarge,
              if (_currentUserRole == 'Customer')
                ElevatedButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('This feature is coming soon!')),
                  ),
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('Request Ride From This Kijiwe'),
                  style: theme.elevatedButtonTheme.style?.copyWith(
                    padding: MaterialStateProperty.all(const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _calculateAgeGroup(DateTime? dob) {
    if (dob == null) return 'Unknown';
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    if (age < 18) return 'Unknown';
    return '${(age ~/ 10) * 10}s';
  }

  Widget _buildMemberTile(String memberId, bool isAdmin, bool isOnline) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final bool canContact = _currentUserRole == 'Driver' && _currentUserId != memberId;

    return FutureBuilder<UserModel?>(
      future: firestoreService.getUser(memberId),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const ListTile(title: Text('Loading member...'), leading: CircleAvatar(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        if (!userSnapshot.hasData || userSnapshot.data == null) {
          return ListTile(title: Text('Unknown Member ($memberId)'));
        }
        if (userSnapshot.hasError) {
          return ListTile(title: Text('Error loading member ($memberId)'));
        }
        final user = userSnapshot.data!;
        final ageGroup = _calculateAgeGroup(user.dob);
        final licensePlate = user.driverProfile?['licenseNumber'] ?? 'N/A';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: user.profileImageUrl != null ? NetworkImage(user.profileImageUrl!) : null,
              child: user.profileImageUrl == null ? const Icon(Icons.person) : null,
            ),
            title: Text(user.name ?? 'No Name'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.driverProfile?['vehicleType'] ?? 'No vehicle info'),
                if (_currentUserRole == 'Driver') ...[
                  Text('${user.gender ?? 'N/A'} • $ageGroup'),
                  Text('${AppLocale.licensePlate.getString(context)}: $licensePlate'),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isAdmin)
                  Chip(
                    avatar: Icon(Icons.shield, size: 16, color: Theme.of(context).colorScheme.onSecondary),
                    label: Text(AppLocale.kijiweAdmin.getString(context)),
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSecondary),
                  ),
                if (canContact)
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline),
                    tooltip: AppLocale.chat.getString(context),
                    onPressed: () {
                      if (_currentUserId == null) return;
                      List<String> ids = [_currentUserId!, memberId];
                      ids.sort();
                      final directChatId = ids.join('_');
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen.direct(
                            directChatId: directChatId,
                            recipientId: memberId,
                            recipientName: user.name ?? 'Driver',
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}