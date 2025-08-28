import 'package:flutter/material.dart';
import '../ride_history_list_widget.dart';

class DriverRideHistoryScreen extends StatelessWidget {
  final String driverId;

  const DriverRideHistoryScreen({super.key, required this.driverId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Ride History'),
      ),
      body: RideHistoryListWidget(role: 'Driver', userId: driverId),
    );
  }
}
