import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/driver_provider.dart';

class KijiweAdminReportsScreen extends StatefulWidget {
  const KijiweAdminReportsScreen({super.key});

  @override
  State<KijiweAdminReportsScreen> createState() => _KijiweAdminReportsScreenState();
}

class _KijiweAdminReportsScreenState extends State<KijiweAdminReportsScreen> {
  String _kijiweId = '';
  String _kijiweName = 'Loading...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadKijiweInfo();
  }

  Future<void> _loadKijiweInfo() async {
    setState(() => _isLoading = true);
    
    try {
      final driverProvider = Provider.of<DriverProvider>(context, listen: false);
      final kijiweId = driverProvider.currentKijiweId;
      
      if (kijiweId == null) {
        setState(() {
          _isLoading = false;
          _kijiweName = 'No Kijiwe Assigned';
        });
        return;
      }

      _kijiweId = kijiweId;
      
      // Get kijiwe details
      final kijiweDoc = await FirebaseFirestore.instance
          .collection('kijiwe')
          .doc(kijiweId)
          .get();
      
      if (kijiweDoc.exists) {
        final kijiweData = kijiweDoc.data()!;
        _kijiweName = kijiweData['name'] ?? 'Unknown Kijiwe';
      }
    } catch (e) {
      debugPrint('Error loading kijiwe info: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_kijiweId.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No Kijiwe Assigned',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'You need to be assigned to a kijiwe to view reports.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          // Kijiwe Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kijiweName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Reports & Analytics',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          
          // Reports Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadKijiweInfo,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
          ),
        ],
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
