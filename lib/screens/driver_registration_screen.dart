import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/driver_provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';

class DriverRegistrationScreen extends StatefulWidget {
  const DriverRegistrationScreen({super.key});

  @override
  State<DriverRegistrationScreen> createState() => _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vehicleTypeController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _newKijiweNameController = TextEditingController();

  List<Map<String, dynamic>> _kijiweList = [];
  String? _selectedKijiweId;
  LatLng? _selectedLocation;

  bool _isCreatingKijiwe = false;
  // Loading state is handled by DriverProvider

  @override
  void initState() {
    super.initState();
    _fetchKijiweList();
  }

  Future<void> _fetchKijiweList() async {
    try {
      // Consider moving Kijiwe fetching to a dedicated service if used elsewhere
      final snapshot = await FirebaseFirestore.instance.collection('kijiwe').get();
      if (mounted) { // Check if the widget is still in the tree
        setState(() {
          _kijiweList = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'name': data['name'] ?? 'Unnamed Kijiwe', // More descriptive default
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Error fetching kijiwe list: $e');
      if (mounted) { // Check before showing SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load Kijiwe locations. Please try again.')),
        );
      }
    }
  }

  Future<void> _selectLocationOnMap() async {
    Location location = Location();
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.')));
        return;
      }
    }

    permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission denied.')));
        return;
      }
    }

    try {
      final LocationData locationData = await location.getLocation();
      setState(() {
        _selectedLocation = LatLng(locationData.latitude!, locationData.longitude!);
      });
    } catch (e) {
      debugPrint("Error getting location: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not get current location: $e')));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      return;
    }

    // Specific validation for Kijiwe selection or creation
    if (_isCreatingKijiwe) {
      if (_newKijiweNameController.text.trim().isEmpty || _selectedLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please provide a name and pick a location for the new Kijiwe.')),
        );
        return;
      }
    } else {
      if (_selectedKijiweId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an existing Kijiwe.')),
        );
        return;
      }
    }

    final driverProvider = Provider.of<DriverProvider>(context, listen: false);

    await driverProvider.registerAsDriver(
      context: context,
      userId: uid,
      vehicleType: _vehicleTypeController.text.trim(),
      licenseNumber: _licenseNumberController.text.trim(),
      // Kijiwe parameters
      createNewKijiwe: _isCreatingKijiwe,
      newKijiweName: _isCreatingKijiwe ? _newKijiweNameController.text.trim() : null,
      newKijiweLocation: _isCreatingKijiwe ? _selectedLocation : null,
      existingKijiweId: !_isCreatingKijiwe ? _selectedKijiweId : null,
    );
  }

  @override
  void dispose() {
    _vehicleTypeController.dispose();
    _licenseNumberController.dispose();
    _newKijiweNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driverProvider = Provider.of<DriverProvider>(context); // Listen for isLoading changes
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Registration')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: driverProvider.isLoading // Use provider's isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  children: [
                    TextFormField(
                      controller: _vehicleTypeController,
                      decoration: const InputDecoration(labelText: 'Vehicle Type'),
                      validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _licenseNumberController,
                      decoration: const InputDecoration(labelText: 'License Number'),
                      validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text("Create new Kijiwe?"),
                        Switch(
                          value: _isCreatingKijiwe,
                          onChanged: (val) {
                            setState(() {
                              _isCreatingKijiwe = val;
                              // Clear selection if switching modes
                              if (val) {
                                _selectedKijiweId = null;
                              } else {
                                _newKijiweNameController.clear();
                                _selectedLocation = null;
                              }
                            });
                          },
                        )
                      ],
                    ),
                    if (_isCreatingKijiwe) ...[
                      TextFormField(
                        controller: _newKijiweNameController,
                        decoration: const InputDecoration(labelText: 'New Kijiwe Name'),
                        validator: (val) => _isCreatingKijiwe && (val == null || val.isEmpty) ? 'Kijiwe name is required' : null,
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _selectLocationOnMap,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text("Pick Kijiwe Location"),
                      ),
                      if (_selectedLocation != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text("Selected: ${_selectedLocation!.latitude.toStringAsFixed(5)}, ${_selectedLocation!.longitude.toStringAsFixed(5)}"),
                        ),
                    ] else ...[
                      DropdownButtonFormField<String>(
                        value: _selectedKijiweId,
                        items: _kijiweList.map((kijiwe) => DropdownMenuItem<String>(value: kijiwe['id'], child: Text(kijiwe['name']))).toList(),
                        onChanged: (val) => setState(() => _selectedKijiweId = val),
                        decoration: const InputDecoration(labelText: 'Select Kijiwe'),
                        validator: (val) => !_isCreatingKijiwe && val == null ? 'Please select a Kijiwe' : null,
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _submit,
                      child: const Text('Complete Registration'),
                    )
                  ],
                ),
              ),
      ),
    );
  }
}
