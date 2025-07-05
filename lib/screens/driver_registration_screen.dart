import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:provider/provider.dart';
import '../providers/driver_provider.dart';
import '../providers/location_provider.dart';
import 'map_picker_screen.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../utils/ui_utils.dart';
import '../localization/locales.dart';
import '../widgets/profile_image_picker.dart';
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
  File? _pickedImageFile;
  
  late Future<List<Map<String, dynamic>>> _kijiweListFuture;
  late final FirestoreService _firestoreService;

  UserModel? _currentUserModel;
  String? _selectedKijiweId;
  LatLng? _selectedLocation;

  bool _isCreatingKijiwe = false;

  @override
  void initState() {
    super.initState();
    // Get service instance from Provider to follow best practices
    _firestoreService = Provider.of<FirestoreService>(context, listen: false);
    _kijiweListFuture = _firestoreService.getKijiweList();
    _fetchCurrentUser();
  }

  Future<void> _fetchCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userModel = await _firestoreService.getUser(user.uid);
      if (mounted) {
        setState(() {
          _currentUserModel = userModel;
        });
      }
    }
  }

  Future<void> _selectLocationOnMap() async {
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);

    // Use the provider's existing permission check logic
    bool permissionOK = await locationProvider.checkAndRequestLocationPermission();
    if (!permissionOK) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocale.location_permission_required.getString(context))));
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
            SnackBar(content: Text(AppLocale.could_not_get_current_location.getString(context))));
      }
    } catch (e) {
      debugPrint("Error getting location via provider: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${AppLocale.could_not_get_current_location.getString(context)}: $e')));
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocale.user_not_logged_in.getString(context)),
      ));
      return;
    }

    // Specific validation for Kijiwe selection or creation
    if (_isCreatingKijiwe) {
      if (_newKijiweNameController.text.trim().isEmpty || _selectedLocation == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocale.provide_kijiwe_name_and_location.getString(context)),
        ));
        return;
      }
    } else {
      if (_selectedKijiweId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocale.please_select_existing_kijiwe.getString(context)),  
        ));
        return;
      }
    }

    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    try {
      String? imageUrl;
      if (_pickedImageFile != null) {
        imageUrl = await _firestoreService.uploadProfileImage(uid, _pickedImageFile!);
      }

      await driverProvider.registerAsDriver(
        userId: uid,
        vehicleType: _vehicleTypeController.text.trim(),
        licenseNumber: _licenseNumberController.text.trim(),
        createNewKijiwe: _isCreatingKijiwe,
        newKijiweName: _isCreatingKijiwe ? _newKijiweNameController.text.trim() : null,
        newKijiweLocation: _isCreatingKijiwe ? _selectedLocation : null,
        existingKijiweId: !_isCreatingKijiwe ? _selectedKijiweId : null,
        profileImageUrl: imageUrl,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const HomeScreen()));
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocale.registration_successful.getString(context))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('${AppLocale.registration_failed.getString(context)}${e.toString()}')),
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
      appBar: AppBar(title: Text(AppLocale.driver_registration.getString(context))),
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
                      child: Text(AppLocale.error_loading_kijiwe_locations
                              .getString(context) +
                          snapshot.error.toString()),
                    );
                  }
                  final kijiweList = snapshot.data ?? [];
                  return Form(
                    key: _formKey,
                    child: ListView(
                      children: [
                        verticalSpaceMedium,
                        ProfileImagePicker(
                          initialImageUrl: _currentUserModel?.profileImageUrl,
                          onImagePicked: (pickedImage) {
                            setState(() {
                              _pickedImageFile = pickedImage;
                            });
                          },
                        ),
                        verticalSpaceMedium,
                        Text(AppLocale.your_details.getString(context),
                            style: theme.textTheme.titleLarge),
                        verticalSpaceSmall,
                        TextFormField(
                          controller: _vehicleTypeController,
                          decoration: InputDecoration(
                            labelText: AppLocale.vehicle_type.getString(context),
                            hintText:
                                AppLocale.vehicle_type_hint.getString(context),
                          ),
                          validator: (val) => val == null || val.isEmpty
                              ? AppLocale.required_field.getString(context)
                              : null,
                        ),
                        verticalSpaceMedium,
                        TextFormField(
                          controller: _licenseNumberController,
                          decoration: InputDecoration(
                              labelText: AppLocale.license_plate_number
                                  .getString(context)),
                          validator: (val) => val == null || val.isEmpty
                              ? AppLocale.required_field.getString(context)
                              : null,
                        ),
                        verticalSpaceLarge,
                        Text(AppLocale.your_kijiwe.getString(context),
                            style: theme.textTheme.titleLarge),
                        verticalSpaceSmall,
                        Text(
                          AppLocale.kijiwe_description_text.getString(context),
                          style: theme.textTheme.bodyMedium,
                        ),
                        verticalSpaceMedium,
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<bool>(
                            segments: <ButtonSegment<bool>>[
                              ButtonSegment<bool>(
                                  value: false,
                                  label: Text(AppLocale.join_existing.getString(context)),
                                  icon: const Icon(Icons.group_add_outlined)),
                              ButtonSegment<bool>(
                                  value: true,
                                  label: Text(AppLocale.create_new.getString(context)),
                                  icon: const Icon(Icons.add_location_alt_outlined)),
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
                            child: Text(
                                AppLocale.complete_registration.getString(context)),
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
            Text(AppLocale.create_a_new_kijiwe.getString(context),
                style: theme.textTheme.titleMedium),
            verticalSpaceMedium,
            TextFormField(
              controller: _newKijiweNameController,
              decoration: InputDecoration(
                  labelText: AppLocale.new_kijiwe_name.getString(context)),
              validator: (val) => _isCreatingKijiwe && (val == null || val.isEmpty)
                  ? AppLocale.kijiwe_name_required.getString(context)
                  : null,
            ),
            verticalSpaceMedium,
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _selectLocationOnMap,
                icon: const Icon(Icons.map_outlined),
                label: Text(
                    AppLocale.pick_kijiwe_location_on_map.getString(context)),
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
                        "${AppLocale.location_set.getString(context)}: ${_selectedLocation!.latitude.toStringAsFixed(4)}, ${_selectedLocation!.longitude.toStringAsFixed(4)}",
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
            Text(AppLocale.join_an_existing_kijiwe.getString(context),
                style: theme.textTheme.titleMedium),
            verticalSpaceMedium,
            DropdownButtonFormField<String>(
              value: _selectedKijiweId,
              items: kijiweList.map((kijiwe) => DropdownMenuItem<String>(value: kijiwe['id'], child: Text(kijiwe['name']))).toList(),
              onChanged: (val) => setState(() => _selectedKijiweId = val),
              decoration: InputDecoration(
                  labelText: AppLocale.select_kijiwe.getString(context)),
              validator: (val) => !_isCreatingKijiwe && val == null
                  ? AppLocale.please_select_kijiwe.getString(context)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
