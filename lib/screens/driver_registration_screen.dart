import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/driver_provider.dart';
import '../providers/location_provider.dart';
import 'map_picker_screen.dart';
import '../services/firestore_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../utils/ui_utils.dart';
import 'home_screen.dart';

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
  
  late Future<List<Map<String, dynamic>>> _kijiweListFuture;
  late final FirestoreService _firestoreService;

  String? _selectedKijiweId;
  LatLng? _selectedLocation;

  bool _isCreatingKijiwe = false;

  @override
  void initState() {
    super.initState();
    // Get service instance from Provider to follow best practices
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    _kijiweListFuture = _firestoreService.getKijiweList();
  }

  Future<void> _selectLocationOnMap() async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);

    // Use the provider's existing permission check logic
    bool permissionOK = await locationProvider.checkAndRequestLocationPermission();
    if (!permissionOK) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required.')));
      }
      return;
    }

    try {
      // Trigger an update and get the latest location
      await locationProvider.updateLocation();
      final locationData = locationProvider.currentLocation;

      if (locationData != null && mounted) {
        // Navigate to the map picker screen and wait for a result
        final LatLng? result = await Navigator.push<LatLng>(
          context,
          MaterialPageRoute(
            builder: (context) => MapPickerScreen(
              initialLocation: LatLng(locationData.latitude, locationData.longitude),
            ),
          ),
        );

        // If a location was picked, update the state
        if (result != null) {
          setState(() {
            _selectedLocation = result;
          });
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not get current location.')));
      }
    } catch (e) {
      debugPrint("Error getting location via provider: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not get current location: $e')));
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      return;
    }

    // Specific validation for Kijiwe selection or creation
    if (_isCreatingKijiwe) {
      if (_newKijiweNameController.text.trim().isEmpty || _selectedLocation == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please provide a name and pick a location for the new Kijiwe.')),
        );
        return;
      }
    } else {
      if (_selectedKijiweId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an existing Kijiwe.')),
        );
        return;
      }
    }

    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    try {
      await driverProvider.registerAsDriver(
        userId: uid,
        vehicleType: _vehicleTypeController.text.trim(),
        licenseNumber: _licenseNumberController.text.trim(),
        createNewKijiwe: _isCreatingKijiwe,
        newKijiweName: _isCreatingKijiwe ? _newKijiweNameController.text.trim() : null,
        newKijiweLocation: _isCreatingKijiwe ? _selectedLocation : null,
        existingKijiweId: !_isCreatingKijiwe ? _selectedKijiweId : null,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const HomeScreen()));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registration successful!')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration failed: ${e.toString()}')),
      );
    }
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
    final driverProvider = Provider.of<DriverProvider>(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Registration')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: driverProvider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : FutureBuilder<List<Map<String, dynamic>>>(
                future: _kijiweListFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                          'Error loading Kijiwe locations: ${snapshot.error}'),
                    );
                  }
                  final kijiweList = snapshot.data ?? [];
                  return Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                        verticalSpaceMedium,
                        Text('Your Details', style: theme.textTheme.titleLarge),
                        verticalSpaceSmall,
                        TextFormField(
                          controller: _vehicleTypeController,
                          decoration: const InputDecoration(
                            labelText: 'Vehicle Type',
                            hintText: 'e.g., Boxer Boda, TVS King',
                          ),
                          validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                        ),
                        verticalSpaceMedium,
                        TextFormField(
                          controller: _licenseNumberController,
                          decoration: const InputDecoration(labelText: 'License Plate Number'),
                          validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                        ),
                        verticalSpaceLarge,
                        Text('Your Kijiwe', style: theme.textTheme.titleLarge),
                        verticalSpaceSmall,
                        Text(
                          'Every driver belongs to a Kijiwe. Join an existing one or create a new one for your area.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        verticalSpaceMedium,
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<bool>(
                            segments: const <ButtonSegment<bool>>[
                              ButtonSegment<bool>(value: false, label: Text('Join Existing'), icon: Icon(Icons.group_add_outlined)),
                              ButtonSegment<bool>(value: true, label: Text('Create New'), icon: Icon(Icons.add_location_alt_outlined)),
                            ],
                            selected: <bool>{_isCreatingKijiwe},
                            onSelectionChanged: (Set<bool> newSelection) {
                              setState(() {
                                _isCreatingKijiwe = newSelection.first;
                                if (_isCreatingKijiwe) {
                                  _selectedKijiweId = null;
                                } else {
                                  _newKijiweNameController.clear();
                                  _selectedLocation = null;
                                }
                              });
                            },
                          ),
                        ),
                        verticalSpaceMedium,
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SizeTransition(sizeFactor: animation, child: child),
                            );
                          },
                          child: _isCreatingKijiwe
                              ? _buildCreateKijiweSection(theme)
                              : _buildJoinKijiweSection(kijiweList, theme),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: theme.elevatedButtonTheme.style?.copyWith(
                              padding: MaterialStateProperty.all(const EdgeInsets.symmetric(vertical: 16)),
                            ),
                            onPressed: _submit,
                            child: const Text('Complete Registration'),
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildCreateKijiweSection(ThemeData theme) {
    return Card(
      key: const ValueKey('create_kijiwe_card'),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create a New Kijiwe', style: theme.textTheme.titleMedium),
            verticalSpaceMedium,
            TextFormField(
              controller: _newKijiweNameController,
              decoration: const InputDecoration(labelText: 'New Kijiwe Name'),
              validator: (val) => _isCreatingKijiwe && (val == null || val.isEmpty)
                  ? 'Kijiwe name is required'
                  : null,
            ),
            verticalSpaceMedium,
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _selectLocationOnMap,
                icon: const Icon(Icons.map_outlined),
                label: const Text("Pick Kijiwe Location on Map"),
              ),
            ),
            if (_selectedLocation != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: successColor, size: 18),
                    horizontalSpaceSmall,
                    Expanded(
                      child: Text(
                        "Location set: ${_selectedLocation!.latitude.toStringAsFixed(4)}, ${_selectedLocation!.longitude.toStringAsFixed(4)}",
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinKijiweSection(List<Map<String, dynamic>> kijiweList, ThemeData theme) {
    return Card(
      key: const ValueKey('join_kijiwe_card'),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Join an Existing Kijiwe', style: theme.textTheme.titleMedium),
            verticalSpaceMedium,
            DropdownButtonFormField<String>(
              value: _selectedKijiweId,
              items: kijiweList.map((kijiwe) => DropdownMenuItem<String>(value: kijiwe['id'], child: Text(kijiwe['name']))).toList(),
              onChanged: (val) => setState(() => _selectedKijiweId = val),
              decoration: const InputDecoration(labelText: 'Select Kijiwe'),
              validator: (val) => !_isCreatingKijiwe && val == null ? 'Please select a Kijiwe' : null,
            ),
          ],
        ),
      ),
    );
  }
}
