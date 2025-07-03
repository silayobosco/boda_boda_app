import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/Ride_Request_Model.dart';
import '../providers/ride_request_provider.dart';
import '../utils/ui_utils.dart';

class ScheduledRideDetailsScreen extends StatefulWidget {
  final RideRequestModel initialRide;

  const ScheduledRideDetailsScreen({super.key, required this.initialRide});

  @override
  State<ScheduledRideDetailsScreen> createState() => _ScheduledRideDetailsScreenState();
}

class _ScheduledRideDetailsScreenState extends State<ScheduledRideDetailsScreen> {
  // We will use a stream to get live updates for the ride
  @override
  Widget build(BuildContext context) {
    final rideProvider = Provider.of<RideRequestProvider>(context, listen: false);

    return StreamBuilder<RideRequestModel?>(
      stream: rideProvider.getScheduledRideStream(widget.initialRide.id!),
      initialData: widget.initialRide,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(appBar: AppBar(), body: Center(child: Text("Error: ${snapshot.error}")));
        }
        if (!snapshot.hasData) {
          // This can happen if the ride is deleted while the user is on this screen.
          return Scaffold(
            appBar: AppBar(title: const Text("Ride Not Found")),
            body: const Center(child: Text("This scheduled ride no longer exists.")),
          );
        }

        final ride = snapshot.data!;
        return _buildDetailsScaffold(context, ride);
      },
    );
  }

  Widget _buildDetailsScaffold(BuildContext context, RideRequestModel ride) {
    final theme = Theme.of(context);
    final rideProvider = Provider.of<RideRequestProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(ride.title ?? 'Scheduled Ride'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Cancel Ride',
            onPressed: () => _showCancelConfirmationDialog(context, ride.id!, rideProvider),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(theme, 'Ride Details'),
            _buildDetailItem(theme, Icons.schedule, 'Scheduled Time', DateFormat('E, MMM d, yyyy hh:mm a').format(ride.scheduledDateTime!.toLocal())),
            _buildDetailItem(theme, Icons.my_location, 'From', ride.pickupAddressName ?? 'N/A'),
            if (ride.stops.isNotEmpty)
              ...ride.stops.asMap().entries.map((entry) {
                final index = entry.key;
                final stop = entry.value;
                return _buildDetailItem(theme, Icons.location_on_outlined, 'Stop ${index + 1}', stop['addressName'] ?? 'N/A');
              }).toList(),
            _buildDetailItem(theme, Icons.flag, 'To', ride.dropoffAddressName ?? 'N/A'),
            
            if (ride.isRecurring == true) ...[
              verticalSpaceMedium,
              _buildSectionHeader(theme, 'Recurrence'),
              _buildDetailItem(theme, Icons.repeat, 'Frequency', ride.recurrenceType ?? 'N/A'),
              if (ride.recurrenceDaysOfWeek != null && ride.recurrenceDaysOfWeek!.isNotEmpty)
                _buildDetailItem(theme, Icons.calendar_view_week, 'Days', ride.recurrenceDaysOfWeek!.join(', ')),
              if (ride.recurrenceEndDate != null)
                _buildDetailItem(theme, Icons.event_busy, 'Ends On', DateFormat.yMMMd().format(ride.recurrenceEndDate!.toLocal())),
            ],

            if (ride.customerNoteToDriver != null && ride.customerNoteToDriver!.isNotEmpty) ...[
              verticalSpaceMedium,
              _buildSectionHeader(theme, 'Note to Driver'),
              Text(ride.customerNoteToDriver!, style: theme.textTheme.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
            ]
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: Implement Edit functionality
          // This will be complex, likely opening a new screen or a large dialog
          // similar to the scheduling dialog in customer_home.dart
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Editing scheduled rides is coming soon!')));
        },
        icon: const Icon(Icons.edit),
        label: const Text('Edit Ride'),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }

  Widget _buildDetailItem(ThemeData theme, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.secondary, size: 20),
          horizontalSpaceMedium,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodySmall),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCancelConfirmationDialog(BuildContext context, String rideId, RideRequestProvider rideProvider) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Scheduled Ride'),
        content: const Text('Are you sure you want to permanently cancel this scheduled ride?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await rideProvider.deleteScheduledRide(rideId);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Scheduled ride cancelled.')),
          );
          Navigator.of(context).pop(); // Go back to the list screen
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to cancel ride: $e')),
          );
        }
      }
    }
  }
}