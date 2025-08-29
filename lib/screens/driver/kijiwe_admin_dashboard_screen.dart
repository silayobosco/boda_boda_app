import 'package:boda_boda/screens/driver/driver_profile_screen.dart';
import 'package:boda_boda/screens/driver/driver_ride_history_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/user_model.dart';
import '../../providers/driver_provider.dart';
import '../../services/firestore_service.dart';
import '../../utils/ui_utils.dart';

class KijiweAdminDashboardScreen extends StatefulWidget {
  const KijiweAdminDashboardScreen({super.key});

  @override
  State<KijiweAdminDashboardScreen> createState() =>
      _KijiweAdminDashboardScreenState();
}

class _KijiweAdminDashboardScreenState
    extends State<KijiweAdminDashboardScreen> {
  int _totalDrivers = 0;
  int _activeDrivers = 0;
  int _ridesToday = 0;
  int _totalCustomers = 0;
  String _kijiweName = 'Loading...';
  bool _isLoading = true;
  String? _kijiweId;

  @override
  void initState() {
    super.initState();
    _fetchKijiweDashboardData();
  }

  Future<void> _fetchKijiweDashboardData() async {
    setState(() => _isLoading = true);

    try {
      final driverProvider =
          Provider.of<DriverProvider>(context, listen: false);
      final kijiweId = driverProvider.currentKijiweId;

      if (kijiweId == null) {
        setState(() {
          _isLoading = false;
          _kijiweName = 'No Kijiwe Assigned';
        });
        return;
      }
      _kijiweId = kijiweId;

      final firestore = FirebaseFirestore.instance;

      // Get kijiwe details
      final kijiweDoc =
          await firestore.collection('kijiwe').doc(kijiweId).get();
      if (kijiweDoc.exists) {
        final kijiweData = kijiweDoc.data()!;
        _kijiweName = kijiweData['name'] ?? 'Unknown Kijiwe';
      }

      // Get drivers in this kijiwe
      final driversQuery = await firestore
          .collection('users')
          .where('driverProfile.kijiweId', isEqualTo: kijiweId)
          .get();

      final drivers = driversQuery.docs;
      _totalDrivers = drivers.length;
      _activeDrivers = drivers
          .where((doc) =>
              doc.data().containsKey('driverProfile') &&
              doc['driverProfile']['isOnline'] == true)
          .length;

      // Get customers who have used this kijiwe
      final customersQuery = await firestore
          .collection('users')
          .where('role', isEqualTo: 'customer')
          .get();

      // Filter customers who have rides from this kijiwe
      final customers = customersQuery.docs;
      _totalCustomers = customers.length;

      // Get rides today for this kijiwe
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final ridesQuery = await firestore
          .collection('rideHistory')
          .where('kijiweId', isEqualTo: kijiweId)
          .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
          .where('timestamp', isLessThan: endOfDay)
          .get();

      _ridesToday = ridesQuery.size;
    } catch (e) {
      debugPrint('Error fetching kijiwe dashboard data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchKijiweDashboardData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Kijiwe Name Header
              Card(
                elevation: 4,
                color: theme.colorScheme.primary,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.groups,
                        size: 40,
                        color: theme.colorScheme.onPrimary,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _kijiweName,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Kijiwe Dashboard',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onPrimary
                                    .withAlpha(200),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              verticalSpaceLarge,

              // Stats Grid
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildDriversStatCard(theme),
                  _buildStatCard(
                      theme,
                      'Rides Today',
                      _ridesToday.toString(),
                      Icons.motorcycle_outlined,
                      Colors.orange),
                  _buildStatCard(
                      theme,
                      'Total Customers',
                      _totalCustomers.toString(),
                      Icons.people_outline,
                      Colors.purple),
                ],
              ),
              verticalSpaceLarge,

              // Reports Section
              Text('Reports & Analytics', style: theme.textTheme.titleLarge),
              verticalSpaceMedium,
              _buildReportSection(
                title: 'Total Rides (This Kijiwe)',
                fetchData: _fetchTotalRides,
                icon: Icons.motorcycle_outlined,
                color: Colors.blue,
              ),
              _buildReportSection(
                title: 'Total Earnings (This Kijiwe)',
                fetchData: _fetchTotalEarnings,
                icon: Icons.attach_money,
                color: Colors.green,
              ),
              _buildReportSection(
                title: 'Rides This Month',
                fetchData: _fetchMonthlyRides,
                icon: Icons.calendar_month,
                color: Colors.orange,
              ),
              _buildReportSection(
                title: 'Average Rating',
                fetchData: _fetchAverageRating,
                icon: Icons.star,
                color: Colors.amber,
              ),
              _buildReportSection(
                title: 'Active Drivers Today',
                fetchData: _fetchActiveDriversToday,
                icon: Icons.people,
                color: Colors.purple,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(ThemeData theme, String title, String value,
      IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 32, color: color),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(title, style: theme.textTheme.bodyMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriversStatCard(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          if (_kijiweId != null) {
            _showDriverList(context, _kijiweId!);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.drive_eta_outlined,
                  size: 32, color: theme.colorScheme.primary),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_totalDrivers',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text('Total Drivers', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.wifi,
                        size: 16,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$_activeDrivers Active',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDriverList(BuildContext context, String kijiweId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.9,
        builder: (context, scrollController) =>
            _DriverListDialog(kijiweId: kijiweId, scrollController: scrollController),
      ),
    );
  }

  Widget _buildReportSection({
    required String title,
    required Future<String> Function() fetchData,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<String>(
              future: fetchData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  );
                } else {
                  return Text(
                    snapshot.data ?? 'N/A',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _fetchTotalRides() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('rideHistory')
          .where('kijiweId', isEqualTo: _kijiweId)
          .get();
      return snapshot.size.toString();
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  Future<String> _fetchTotalEarnings() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('rideHistory')
          .where('kijiweId', isEqualTo: _kijiweId)
          .get();
      
      double totalEarnings = snapshot.docs.fold(0.0, (total, doc) {
        final fare = doc.data()['fare'];
        if (fare != null) {
          return total + (fare is int ? fare.toDouble() : (fare as num).toDouble());
        }
        return total;
      });
      
      return 'TZS ${totalEarnings.toStringAsFixed(2)}';
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  Future<String> _fetchMonthlyRides() async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 1);
      
      final snapshot = await FirebaseFirestore.instance
          .collection('rideHistory')
          .where('kijiweId', isEqualTo: _kijiweId)
          .where('timestamp', isGreaterThanOrEqualTo: startOfMonth)
          .where('timestamp', isLessThan: endOfMonth)
          .get();
      
      return snapshot.size.toString();
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  Future<String> _fetchAverageRating() async {
    try {
      // Use rideRequests collection since it has rating fields
      final snapshot = await FirebaseFirestore.instance
          .collection('rideRequests')
          .where('kijiweId', isEqualTo: _kijiweId)
          .where('status', isEqualTo: 'completed')
          .where('customerRatingToDriver', isGreaterThan: 0)
          .get();
      
      if (snapshot.docs.isEmpty) {
        return 'No ratings yet';
      }
      
      double totalRating = snapshot.docs.fold(0.0, (total, doc) {
        final rating = doc.data()['customerRatingToDriver'];
        if (rating != null) {
          return total + (rating is int ? rating.toDouble() : (rating as num).toDouble());
        }
        return total;
      });
      
      final averageRating = totalRating / snapshot.docs.length;
      return averageRating.toStringAsFixed(1);
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  Future<String> _fetchActiveDriversToday() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('driverProfile.kijiweId', isEqualTo: _kijiweId)
          .where('driverProfile.isOnline', isEqualTo: true)
          .get();
      
      return snapshot.size.toString();
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }
}

class _DriverListDialog extends StatelessWidget {
  final String kijiweId;
  final ScrollController scrollController;

  const _DriverListDialog({required this.kijiweId, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drivers'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('driverProfile.kijiweId', isEqualTo: kijiweId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No drivers found.'));
          }

          final drivers = snapshot.data!.docs.map((doc) {
            return UserModel.fromJson(doc.data() as Map<String, dynamic>);
          }).toList();

          return ListView.builder(
            controller: scrollController,
            itemCount: drivers.length,
            itemBuilder: (context, index) {
              final driver = drivers[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: driver.profileImageUrl != null &&
                            driver.profileImageUrl!.isNotEmpty
                        ? NetworkImage(driver.profileImageUrl!)
                        : null,
                    child: driver.profileImageUrl == null ||
                            driver.profileImageUrl!.isEmpty
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(driver.name ?? 'No Name'),
                  subtitle: Text(driver.email ?? 'No Email'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        driver.driverProfile?['isOnline'] == true
                            ? Icons.wifi
                            : Icons.wifi_off,
                        color: driver.driverProfile?['isOnline'] == true
                            ? Colors.green
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DriverProfileScreen(driverId: driver.uid!),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}