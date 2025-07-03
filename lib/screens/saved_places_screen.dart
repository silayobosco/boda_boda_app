import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmf;
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../models/user_model.dart';
import '../services/user_service.dart';
import '../services/firestore_service.dart';
import '../providers/location_provider.dart';
import 'map_picker_screen.dart';
import '../utils/ui_utils.dart';

class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  _SavedPlacesScreenState createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  final UserService _userService = UserService();
  final FirestoreService _firestoreService = FirestoreService();
  final String? _userId = FirebaseAuth.instance.currentUser?.uid;
  UserModel? _userModel;
  List<Map<String, dynamic>> _savedPlaces = [];
  bool _isLoading = true;
  final String _googlePlacesApiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;

  @override
  void initState() {
    super.initState();
    _loadSavedPlaces();
  }

  Future<void> _loadSavedPlaces() async {
    if (_userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final userModel = await _userService.getUserModel(_userId);
      if (mounted) {
        setState(() {
          _userModel = userModel;
          final customerProfile = userModel?.customerProfile;
          if (customerProfile != null && customerProfile['savedPlaces'] is List) {
            // Convert GeoPoint to LatLng for local use
            _savedPlaces = (customerProfile['savedPlaces'] as List).map<Map<String, dynamic>>((place) {
              final placeMap = place as Map<String, dynamic>;
              if (placeMap['location'] is GeoPoint) {
                final GeoPoint geo = placeMap['location'];
                return {
                  ...placeMap,
                  'location': gmf.LatLng(geo.latitude, geo.longitude),
                };
              }
              return placeMap;
            }).toList();
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading saved places: $e')),
        );
      }
    }
  }

  Future<void> _savePlaces() async {
    if (_userId == null) return;
    try {
      await _firestoreService.updateUserSavedPlaces(_userId, _savedPlaces);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved places updated!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving places: $e')),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getGooglePlacesSuggestions(String query) async {
    if (query.length < 2) return []; // Don't search for very short strings
    final url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$_googlePlacesApiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          return (data['predictions'] as List).map((p) => {
            'place_id': p['place_id'],
            'description': p['description'],
          }).toList();
        } else {
          debugPrint("Google Places API Error: ${data['error_message'] ?? data['status']}");
        }
      } else {
        debugPrint("HTTP Error fetching suggestions: ${response.statusCode}");
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching suggestions: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> _getPlaceDetails(String placeId) async {
    final url = 'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_googlePlacesApiKey';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final geometry = data['result']['geometry']['location'];
          return {
            'latitude': geometry['lat'],
            'longitude': geometry['lng'],
          };
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching place details: $e');
      return null;
    }
  }

  Future<void> _showAddEditDialog({Map<String, dynamic>? existingPlace, int? index}) async {
    final labelController = TextEditingController(text: existingPlace?['label'] ?? '');
    final addressController = TextEditingController(text: existingPlace?['address'] ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        // State variables for the dialog's content
        List<Map<String, dynamic>> suggestions = [];
        Timer? debounce;
        bool isDialogLoading = false;
        gmf.LatLng? selectedLocation = existingPlace?['location'] as gmf.LatLng?;

        return StatefulBuilder(
          builder: (stfContext, setDialogState) {
            return AlertDialog(
              title: Text(existingPlace == null ? 'Add New Place' : 'Edit Place'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: labelController,
                        decoration: appInputDecoration(labelText: 'Label', hintText: 'e.g., Home, Work'),
                        validator: (value) => value == null || value.isEmpty ? 'Please enter a label' : null,
                      ),
                      verticalSpaceMedium,
                      TextFormField(
                        controller: addressController,
                        decoration: appInputDecoration(
                          labelText: 'Address',
                          hintText: 'Search for an address',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.map_outlined),
                            onPressed: () async {
                              final locationProvider = Provider.of<LocationProvider>(context, listen: false);
                              await locationProvider.updateLocation();
                              final initialLoc = locationProvider.currentLocation;

                              if (initialLoc != null && dialogContext.mounted) {
                                final gmf.LatLng? result = await Navigator.push<gmf.LatLng>(
                                  dialogContext,
                                  MaterialPageRoute(
                                    builder: (context) => MapPickerScreen(
                                      initialLocation: gmf.LatLng(initialLoc.latitude, initialLoc.longitude),
                                    ),
                                  ),
                                );
                                if (result != null) {
                                  List<Placemark> placemarks = await placemarkFromCoordinates(result.latitude, result.longitude);
                                  if (placemarks.isNotEmpty) {
                                    final p = placemarks.first;
                                    setDialogState(() {
                                      selectedLocation = result;
                                      addressController.text = "${p.name}, ${p.street}, ${p.locality}";
                                    });
                                  }
                                }
                              }
                            },
                          ),
                        ),
                        onChanged: (value) {
                          if (debounce?.isActive ?? false) debounce!.cancel();
                          debounce = Timer(const Duration(milliseconds: 500), () async {
                            // Check if the dialog is still mounted before making an API call
                            if (!stfContext.mounted) return;

                            if (value.isNotEmpty) {
                              final result = await _getGooglePlacesSuggestions(value);
                              if (stfContext.mounted) { // Check again after the async gap
                                setDialogState(() => suggestions = result);
                              }
                            } else {
                              setDialogState(() => suggestions = []);
                            }
                          });
                        },
                        validator: (value) => value == null || value.isEmpty ? 'Please enter an address' : null,
                      ),
                      if (suggestions.isNotEmpty)
                        SizedBox(
                          height: 150,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: suggestions.length,
                            itemBuilder: (context, index) {
                              final suggestion = suggestions[index];
                              return ListTile(
                                title: Text(suggestion['description']),
                                onTap: () async {
                                  final details = await _getPlaceDetails(suggestion['place_id']);
                                  if (details != null) {
                                    setDialogState(() {
                                      addressController.text = suggestion['description'];
                                      selectedLocation = gmf.LatLng(details['latitude'], details['longitude']);
                                      suggestions = [];
                                    });
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      if (isDialogLoading) ...[
                        verticalSpaceMedium,
                        const CircularProgressIndicator(),
                      ]
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    debounce?.cancel();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isDialogLoading ? null : () async {
                    debounce?.cancel();
                    if (formKey.currentState!.validate()) {
                      setDialogState(() => isDialogLoading = true);
                      gmf.LatLng? finalLocation = selectedLocation;

                      if (finalLocation == null) {
                        try {
                          List<Location> locations = await locationFromAddress(addressController.text);
                          if (locations.isNotEmpty) {
                            finalLocation = gmf.LatLng(locations.first.latitude, locations.first.longitude);
                          }
                        } catch (e) {
                          debugPrint("Geocoding fallback error: $e");
                        }
                      }

                      if (finalLocation != null) {
                        final newPlace = {
                          'label': labelController.text.trim(),
                          'address': addressController.text.trim(),
                          'location': finalLocation,
                        };
                        Navigator.pop(dialogContext, newPlace);
                      } else {
                        ScaffoldMessenger.of(stfContext).showSnackBar(
                          const SnackBar(content: Text('Could not find location for the address.')),
                        );
                        setDialogState(() => isDialogLoading = false);
                      }
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        if (index != null) {
          _savedPlaces[index] = result;
        } else {
          _savedPlaces.add(result);
        }
      });
      await _savePlaces();
    }
  }

  Future<void> _deletePlace(int index) async {
    setState(() {
      _savedPlaces.removeAt(index);
    });
    await _savePlaces();
  }

  IconData _getIconForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'home':
        return Icons.home_filled;
      case 'work':
        return Icons.work;
      default:
        return Icons.star;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Places'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _savedPlaces.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.place_outlined, size: 80, color: theme.hintColor),
                      verticalSpaceMedium,
                      Text(
                        'No saved places yet.',
                        style: theme.textTheme.titleMedium?.copyWith(color: theme.hintColor),
                      ),
                      verticalSpaceSmall,
                      const Text(
                        'Tap the + button to add a new place.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: _savedPlaces.length,
                  itemBuilder: (context, index) {
                    final place = _savedPlaces[index];
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(
                            _getIconForLabel(place['label']),
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: Text(place['label'], style: theme.textTheme.titleMedium),
                        subtitle: Text(place['address'], maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit_outlined, color: theme.colorScheme.secondary),
                              onPressed: () => _showAddEditDialog(existingPlace: place, index: index),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                              onPressed: () => _deletePlace(index),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}