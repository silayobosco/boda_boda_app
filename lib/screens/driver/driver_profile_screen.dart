import 'dart:async';

import 'package:boda_boda/models/ride_request_model.dart';
import 'package:boda_boda/providers/ride_request_provider.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../ride_history_list_widget.dart';
import '../../models/user_model.dart';
import '../../services/user_service.dart';

class DriverProfileScreen extends StatefulWidget {
  final String driverId;

  const DriverProfileScreen({super.key, required this.driverId});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final UserService _userService = UserService();
  late Stream<UserModel?> _driverStream;
  final Completer<GoogleMapController> _mapController = Completer();

  @override
  void initState() {
    super.initState();
    _driverStream = _userService.getUserModelStream(widget.driverId);
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      throw 'Could not launch $launchUri';
    }
  }

  Future<void> _sendSMS(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'sms',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      throw 'Could not launch $launchUri';
    }
  }

  void _showConfirmationDialog(
      {required String title,
      required String content,
      required VoidCallback onConfirm}) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Confirm'),
              onPressed: () {
                onConfirm();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Driver Profile'),
          actions: [
            StreamBuilder<UserModel?>(
              stream: _driverStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox.shrink();
                }
                final driver = snapshot.data!;
                return Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.message),
                      onPressed: () {
                        if (driver.phoneNumber != null) {
                          _sendSMS(driver.phoneNumber!);
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.call),
                      onPressed: () {
                        if (driver.phoneNumber != null) {
                          _makePhoneCall(driver.phoneNumber!);
                        }
                      },
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'suspend') {
                          _showConfirmationDialog(
                            title: driver.isSuspended
                                ? 'Unsuspend Driver'
                                : 'Suspend Driver',
                            content:
                                'Are you sure you want to ${driver.isSuspended ? 'unsuspend' : 'suspend'} this driver?',
                            onConfirm: () async {
                              await _userService.suspendDriver(
                                  widget.driverId, !driver.isSuspended);
                            },
                          );
                        } else if (value == 'remove') {
                          _showConfirmationDialog(
                            title: 'Remove Driver',
                            content:
                                'Are you sure you want to remove this driver?',
                            onConfirm: () async {
                              await _userService.deleteDriver(widget.driverId);
                              if (mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                          );
                        }
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'suspend',
                          child: Text(driver.isSuspended
                              ? 'Unsuspend Driver'
                              : 'Suspend Driver'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'remove',
                          child: Text('Remove Driver'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Profile'),
              Tab(text: 'Ride History'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildProfileTab(),
            _buildRideHistoryTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    return StreamBuilder<UserModel?>(
      stream: _driverStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return const Center(child: Text('Driver not found.'));
        }

        final driver = snapshot.data!;
        final driverProfile = driver.driverProfile ?? {};
        final currentLocation = driverProfile['currentLocation'] as GeoPoint?;
        final status = driverProfile['status'] as String?;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(driver),
              const Divider(height: 32),
              if (currentLocation != null)
                _buildMapView(currentLocation, status),
              if (status != null && status != 'offline' && status != 'waitingForRide')
                Consumer<RideRequestProvider>(
                  builder: (context, rideRequestProvider, child) {
                    return _buildCurrentRideCard(driver.uid!, rideRequestProvider);
                  }
                ),
              const SizedBox(height: 16),
              _buildDriverStats(driverProfile),
              const Divider(height: 32),
              _buildProfileInfo(driver, driverProfile),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(UserModel driver) {
    return Column(
      children: [
        Center(
          child: CircleAvatar(
            radius: 60,
            backgroundImage: driver.profileImageUrl != null &&
                    driver.profileImageUrl!.isNotEmpty
                ? NetworkImage(driver.profileImageUrl!)
                : null,
            child: driver.profileImageUrl == null ||
                    driver.profileImageUrl!.isEmpty
                ? const Icon(Icons.person, size: 60)
                : null,
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            driver.name ?? 'No Name',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            driver.isSuspended ? 'Suspended' : 'Active',
            style: TextStyle(
              color: driver.isSuspended ? Colors.red : Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapView(GeoPoint location, String? status) {
    final latLng = LatLng(location.latitude, location.longitude);
    return SizedBox(
      height: 250,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: latLng, zoom: 15),
          onMapCreated: (GoogleMapController controller) {
            if (!_mapController.isCompleted) {
              _mapController.complete(controller);
            }
          },
          markers: {
            Marker(
              markerId: const MarkerId('driverLocation'),
              position: latLng,
              infoWindow: InfoWindow(title: 'Driver Location', snippet: status ?? 'Status unknown'),
            ),
          },
        ),
      ),
    );
  }

  Widget _buildCurrentRideCard(String driverId, RideRequestProvider rideRequestProvider) {
    return StreamBuilder<RideRequestModel?>(
      stream: rideRequestProvider.getCurrentRideForDriver(driverId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }
        final ride = snapshot.data!;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('On a Ride', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                _buildProfileInfoRow(context, Icons.person, 'Customer', ride.customerName ?? 'N/A'),
                _buildProfileInfoRow(context, Icons.location_on, 'From', ride.pickupAddressName ?? 'N/A'),
                _buildProfileInfoRow(context, Icons.flag, 'To', ride.dropoffAddressName ?? 'N/A'),
                _buildProfileInfoRow(context, Icons.money, 'Fare', ride.fare?.toStringAsFixed(2) ?? 'N/A'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDriverStats(Map<String, dynamic> driverProfile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem('Completed', driverProfile['completedRidesCount']?.toString() ?? '0'),
        _buildStatItem('Cancelled', driverProfile['cancelledByDriverCount']?.toString() ?? '0'),
        _buildStatItem('Declined', driverProfile['declinedByDriverCount']?.toString() ?? '0'),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.titleLarge),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _buildProfileInfo(UserModel driver, Map<String, dynamic> driverProfile) {
    return Column(
      children: [
        _buildProfileInfoRow(context, Icons.online_prediction, 'Online Status', (driverProfile['isOnline'] ?? false) ? 'Online' : 'Offline'),
        _buildProfileInfoRow(context, Icons.info_outline, 'Current Status', driverProfile['status'] ?? 'N/A'),
        _buildProfileInfoRow(context, Icons.motorcycle, 'Vehicle', driverProfile['vehicleType'] ?? 'Not provided'),
        _buildProfileInfoRow(context, Icons.badge, 'License', driverProfile['licenseNumber'] ?? 'Not provided'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Icon(Icons.group_work, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kijiwe', style: Theme.of(context).textTheme.bodySmall),
                  if (driverProfile['kijiweId'] != null)
                    KijiweNameWidget(kijiweId: driverProfile['kijiweId'])
                  else
                    Text('Not provided', style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ],
          ),
        ),
        _buildProfileInfoRow(context, Icons.email, 'Email', driver.email ?? 'Not provided'),
        _buildProfileInfoRow(context, Icons.phone, 'Phone', driver.phoneNumber ?? 'Not provided'),
        _buildProfileInfoRow(
          context,
          Icons.cake,
          'Date of Birth',
          driver.dob != null ? DateFormat.yMMMd().format(driver.dob!) : 'Not provided',
        ),
        _buildProfileInfoRow(context, Icons.person_outline, 'Gender', driver.gender ?? 'Not provided'),
        _buildProfileInfoRow(context, Icons.star, 'Rating', driver.driverAverageRating?.toStringAsFixed(1) ?? 'N/A'),
      ],
    );
  }

  Widget _buildProfileInfoRow(
      BuildContext context, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRideHistoryTab() {
    return RideHistoryListWidget(role: 'Driver', userId: widget.driverId);
  }
}

class KijiweNameWidget extends StatelessWidget {
  final String kijiweId;

  const KijiweNameWidget({super.key, required this.kijiweId});

  Future<String> _getKijiweName(String kijiweId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('Kijiwes').doc(kijiweId).get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['name'] as String? ?? 'Unknown Kijiwe';
      }
    } catch (e) {
      print('Error getting kijiwe name: $e');
    }
    return 'Unknown Kijiwe';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _getKijiweName(kijiweId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Text('Loading...');
        }
        return Text(snapshot.data ?? 'Unknown Kijiwe', style: Theme.of(context).textTheme.bodyLarge);
      },
    );
  }
}