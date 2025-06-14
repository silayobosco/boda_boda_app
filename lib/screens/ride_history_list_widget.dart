import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/Ride_Request_Model.dart'; // Assuming RideHistoryModel is part of this or a separate model
import '../providers/ride_request_provider.dart'; // To fetch ride history
import '../services/auth_service.dart'; // To get current user ID
import '../utils/ui_utils.dart'; // For styles and spacing

class RideHistoryListWidget extends StatelessWidget {
  final String role;
  // final String userId; // Consider passing userId if not using a global provider for it

  const RideHistoryListWidget({super.key, required this.role /*, required this.userId */});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final String? currentUserId = authService.currentUser?.uid;

    if (currentUserId == null) {
      return const Center(child: Text("User not authenticated."));
    }

    return StreamBuilder<List<RideRequestModel>>(
      stream: Provider.of<RideRequestProvider>(context, listen: false).getRideHistory(currentUserId, role),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: appTextStyle(color: theme.colorScheme.error)));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text('No ride history found.', style: theme.textTheme.bodyMedium));
        }

        final rides = snapshot.data!;

        return ListView.builder(
          padding: const EdgeInsets.all(8.0), // Use ui_utils spacing if preferred
          itemCount: rides.length,
          itemBuilder: (context, index) {
            final ride = rides[index];
            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // From ui_utils.appBoxDecoration
              child: ListTile(
                leading: Icon(
                  role == 'Customer' ? Icons.person_pin_circle_outlined : Icons.drive_eta_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  'To: ${ride.dropoffAddressName ?? 'Destination'}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'From: ${ride.pickupAddressName ?? 'Pickup'}\nDate: ${ride.requestTime?.toLocal().toString().substring(0, 16) ?? 'N/A'} - Status: ${ride.status}',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: Text(
                  ride.fare != null ? '\$${ride.fare!.toStringAsFixed(2)}' : 'N/A',
                  style: appTextStyle(color: successColor, fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  // TODO: Navigate to Ride Details Screen
                },
              ),
            );
          },
        );
      },
    );
  }
}