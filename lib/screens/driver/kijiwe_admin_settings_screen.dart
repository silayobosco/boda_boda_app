import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/driver_provider.dart';
import '../../utils/account_utils.dart';

class KijiweAdminSettingsScreen extends StatefulWidget {
  const KijiweAdminSettingsScreen({super.key});

  @override
  State<KijiweAdminSettingsScreen> createState() => _KijiweAdminSettingsScreenState();
}

class _KijiweAdminSettingsScreenState extends State<KijiweAdminSettingsScreen> {
  String _kijiweId = '';
  String _kijiweName = 'Loading...';
  bool _isLoading = true;
  
  // Kijiwe settings
  bool _allowManualRide = true;
  bool _enableDriverRegistration = true;
  bool _autoAcceptRides = false;
  double _commissionRate = 0.0;
  String _kijiweDescription = '';
  
  // Form controllers
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _commissionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadKijiweInfo();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _commissionController.dispose();
    super.dispose();
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
        _allowManualRide = kijiweData['allowManualRide'] ?? true;
        _enableDriverRegistration = kijiweData['enableDriverRegistration'] ?? true;
        _autoAcceptRides = kijiweData['autoAcceptRides'] ?? false;
        _commissionRate = (kijiweData['commissionRate'] ?? 0.0).toDouble();
        _kijiweDescription = kijiweData['description'] ?? '';
        
        _descriptionController.text = _kijiweDescription;
        _commissionController.text = _commissionRate.toString();
      }
    } catch (e) {
      debugPrint('Error loading kijiwe info: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveKijiweSettings() async {
    if (_kijiweId.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      final commissionRate = double.tryParse(_commissionController.text) ?? 0.0;
      
      await FirebaseFirestore.instance
          .collection('kijiwe')
          .doc(_kijiweId)
          .update({
        'allowManualRide': _allowManualRide,
        'enableDriverRegistration': _enableDriverRegistration,
        'autoAcceptRides': _autoAcceptRides,
        'commissionRate': commissionRate,
        'description': _descriptionController.text.trim(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kijiwe settings updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving kijiwe settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating settings: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
              'You need to be assigned to a kijiwe to manage settings.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    
    return Scaffold(
      body: Column(
        children: [
          // Kijiwe Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: theme.colorScheme.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kijiweName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Kijiwe Settings',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          
          // Settings Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Kijiwe Settings Section
                  Text('Kijiwe Settings', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 16),
                  
                  _buildSettingTile(
                    theme,
                    'Allow Manual Ride (Street Pickup)',
                    _allowManualRide,
                    (value) => setState(() => _allowManualRide = value),
                  ),
                  _buildSettingTile(
                    theme,
                    'Enable Driver Registration',
                    _enableDriverRegistration,
                    (value) => setState(() => _enableDriverRegistration = value),
                  ),
                  _buildSettingTile(
                    theme,
                    'Auto-Accept Rides',
                    _autoAcceptRides,
                    (value) => setState(() => _autoAcceptRides = value),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Commission Rate
                  Text('Commission Rate (%)', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _commissionController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Enter commission rate (0-100)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixText: '%',
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Kijiwe Description
                  Text('Kijiwe Description', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Enter kijiwe description',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveKijiweSettings,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Save Settings'),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Logout Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        AccountUtils.showLogoutConfirmationDialog(context, userRole: 'Kijiwe Admin');
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(color: theme.colorScheme.error),
                      ),
                      child: Text(
                        'Logout',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile(
    ThemeData theme,
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title, 
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
