import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/Ride_Request_Model.dart';
import '../providers/ride_request_provider.dart'; // To fetch ride history
import '../services/auth_service.dart'; // To get current user ID
import '../utils/ui_utils.dart'; // For styles and spacing
import 'ride_history_details_screen.dart'; // Import the details screen

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

        final rideHistory = snapshot.data!;

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: rideHistory.length,
          itemBuilder: (context, index) {
            final ride = rideHistory[index];
            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: _buildStatusIcon(ride.status, theme),
                title: Text('To: ${ride.dropoffAddressName ?? 'Destination'}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                subtitle: Text('On: ${ride.completedTime != null ? DateFormat.yMMMd().add_jm().format(ride.completedTime!) : DateFormat.yMMMd().add_jm().format(ride.requestTime!)}'),
                trailing: Text('TZS ${ride.fare?.toStringAsFixed(0) ?? 'N/A'}', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => RideHistoryDetailsScreen(ride: ride)));
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusIcon(String status, ThemeData theme) {
    IconData iconData;
    Color color;
    switch (status) {
      case 'completed':
        iconData = Icons.check_circle;
        color = successColor;
        break;
      case 'cancelled_by_customer':
      case 'cancelled_by_driver':
        iconData = Icons.cancel;
        color = errorColor;
        break;
      default:
        iconData = Icons.history;
        color = theme.hintColor;
    }
    return Icon(iconData, color: color);
  }
}