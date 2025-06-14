import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/Ride_Request_Model.dart'; // Assuming ScheduledRideModel or adapt RideRequestModel
import '../providers/ride_request_provider.dart'; // To fetch scheduled rides
import '../services/auth_service.dart'; // To get current user ID
import '../utils/ui_utils.dart'; // For styles and spacing

class ScheduledRidesListWidget extends StatelessWidget {
  // final String userId; // Consider passing userId

  const ScheduledRidesListWidget({super.key /*, required this.userId */});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final String? currentUserId = authService.currentUser?.uid;

    if (currentUserId == null) {
      return const Center(child: Text("User not authenticated."));
    }

    return StreamBuilder<List<RideRequestModel>>(
      stream: Provider.of<RideRequestProvider>(context, listen: false).getScheduledRides(currentUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: appTextStyle(color: theme.colorScheme.error)));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text('No scheduled rides found.', style: theme.textTheme.bodyMedium));
        }

        final scheduledRides = snapshot.data!;

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: scheduledRides.length,
          itemBuilder: (context, index) {
            final ride = scheduledRides[index];
            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: Icon(Icons.schedule, color: theme.colorScheme.secondary),
                title: Text(
                  'Scheduled for: ${ride.scheduledDateTime?.toLocal().toString().substring(0, 16) ?? 'N/A'}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('To: ${ride.dropoffAddressName ?? 'Destination'}'),
                onTap: () {
                  // TODO: Navigate to Scheduled Ride Details or allow cancellation
                },
              ),
            );
          },
        );
      },
    );
  }
}