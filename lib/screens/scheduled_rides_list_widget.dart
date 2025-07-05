import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:provider/provider.dart';
import '../models/Ride_Request_Model.dart'; // Assuming ScheduledRideModel or adapt RideRequestModel
import '../providers/ride_request_provider.dart'; // To fetch scheduled rides
import '../services/auth_service.dart'; // To get current user ID
import '../localization/locales.dart';
import '../utils/ui_utils.dart'; // For styles and spacing
import 'scheduled_ride_details_screen.dart'; // Import the new details screen

class ScheduledRidesListWidget extends StatelessWidget {
  // final String userId; // Consider passing userId

  const ScheduledRidesListWidget({super.key /*, required this.userId */});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final String? currentUserId = authService.currentUser?.uid;

    if (currentUserId == null) {
      return Center(child: Text(AppLocale.userNotAuthenticated.getString(context)));
    }

    return StreamBuilder<List<RideRequestModel>>(
      stream: Provider.of<RideRequestProvider>(context, listen: false).getScheduledRides(currentUserId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('${AppLocale.error_prefix.getString(context)}${snapshot.error}', style: appTextStyle(color: theme.colorScheme.error)));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text(AppLocale.no_scheduled_rides_found.getString(context), style: theme.textTheme.bodyMedium));
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
                  '${AppLocale.scheduled_for_prefix.getString(context)}${ride.scheduledDateTime?.toLocal().toString().substring(0, 16) ?? AppLocale.not_available_abbreviation.getString(context)}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('${AppLocale.to_prefix.getString(context)}${ride.dropoffAddressName ?? AppLocale.destination.getString(context)}'),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ScheduledRideDetailsScreen(initialRide: ride),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}