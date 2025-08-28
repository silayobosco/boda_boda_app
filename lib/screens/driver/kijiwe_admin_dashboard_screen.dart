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

              // Recent Activity Section
              Text('Recent Activity', style: theme.textTheme.titleLarge),
              verticalSpaceMedium,
              _buildRecentActivityCard(theme),
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

  Widget _buildRecentActivityCard(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Recent Rides', style: theme.textTheme.titleMedium),
              ],
            ),
            verticalSpaceMedium,
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text('Recent activity feed coming soon.'),
              ),
            ),
          ],
        ),
      ),
    );
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
