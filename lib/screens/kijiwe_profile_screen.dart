import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/ui_utils.dart'; // For spacing and styling
import 'chat_screen.dart';

class KijiweProfileScreen extends StatefulWidget {
  final String kijiweId;

  const KijiweProfileScreen({super.key, required this.kijiweId});

  @override
  State<KijiweProfileScreen> createState() => _KijiweProfileScreenState();
}

class _KijiweProfileScreenState extends State<KijiweProfileScreen> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _kijiweFuture;

  @override
  void initState() {
    super.initState();
    _kijiweFuture = FirebaseFirestore.instance
        .collection('kijiwe')
        .doc(widget.kijiweId)
        .get();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kijiwe Profile'),
      ),
      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: _kijiweFuture,
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

          final kijiweData = snapshot.data!.data()!;
          final kijiweName = kijiweData['name'] as String? ?? 'Unnamed Kijiwe';
          final members = kijiweData['permanentMembers'] as List<dynamic>? ?? [];
          final queue = kijiweData['queue'] as List<dynamic>? ?? [];
          final position = kijiweData['position']?['geopoint'] as GeoPoint?;
          final adminId = kijiweData['adminId'] as String?;

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Text(
                kijiweName,
                style: theme.textTheme.headlineMedium,
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
              Card(
                child: ListTile(
                  leading: const Icon(Icons.group_outlined),
                  title: const Text('Permanent Members'),
                  trailing: Text(
                    '${members.length}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.motorcycle_outlined),
                  title: const Text('Drivers Online'),
                  trailing: Text(
                    '${queue.length}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ),
              if (adminId != null) ...[
                verticalSpaceLarge,
                _buildAdminProfileSection(adminId, theme),
              ],
              verticalSpaceLarge,
              ElevatedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('This feature is coming soon!')),
                ),
                icon: const Icon(Icons.add_task_outlined),
                label: const Text('Request Ride From This Kijiwe'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAdminProfileSection(String adminId, ThemeData theme) {
    final currentUserId =
        Provider.of<AuthService>(context, listen: false).currentUser?.uid;

    return FutureBuilder<UserModel?>(
      future: FirestoreService().getUser(adminId),
      builder: (context, adminSnapshot) {
        if (!adminSnapshot.hasData) {
          return const Center(child: Text("Loading leader info..."));
        }
        if (adminSnapshot.data == null) {
          return const SizedBox.shrink(); // Don't show if admin profile not found
        }

        final adminProfile = adminSnapshot.data!;

        // Don't show contact button if the user is the admin
        final bool isCurrentUserTheAdmin = currentUserId == adminId;

        return Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kijiwe Leader', style: theme.textTheme.titleLarge),
                verticalSpaceMedium,
                ListTile(
                  leading: CircleAvatar(
                    backgroundImage: adminProfile.profileImageUrl != null
                        ? NetworkImage(adminProfile.profileImageUrl!)
                        : null,
                    child: adminProfile.profileImageUrl == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(adminProfile.name ?? 'Kijiwe Leader'),
                  subtitle: const Text('Admin'),
                ),
                if (!isCurrentUserTheAdmin) ...[
                  verticalSpaceMedium,
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        List<String> ids = [currentUserId!, adminProfile.uid!];
                        ids.sort();
                        final directChatId = ids.join('_');
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => ChatScreen.direct(
                                    directChatId: directChatId,
                                    recipientId: adminProfile.uid!,
                                    recipientName: adminProfile.name ?? 'Kijiwe Leader')));
                      },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Contact Leader'),
                    ),
                  ),
                ]
              ],
            ),
          ),
        );
      },
    );
  }
}