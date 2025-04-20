import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:geocoding/geocoding.dart'; // Import geocoding
//import 'package:cached_network_image/cached_network_image.dart'; // Import cached_network_image
import 'package:intl/intl.dart'; // Import intl for date formatting
import '../services/user_service.dart';
import '../models/user_model.dart';
import '../utils/ui_utils.dart'; // Import appTextStyle, appInputDecoration, primaryColor, hintTextColor

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final firebase_storage.FirebaseStorage _storage =
      firebase_storage.FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
  final List<String> _genders = [
    'Male',
    'Female',
    'Other',
  ]; // Define valid gender options
  final UserService _userService = UserService();

  UserModel? _userModel;
  String? _name;
  String? _phone;
  DateTime? _dob;
  String? _gender;
  String? _location;
  String? _photoURL;
  File? _imageFile;
  String? _email;
  String? _role;
  String? _locationAddress; // Human-readable location
  bool _isEditing = false; // Track whether the fields are in edit mode

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    //_loadCachedData(); // Load cached data first
    _loadUserData(); // Fetch data from Firestore
  }

  Future<void> _loadUserData() async {
    try {
      User? user = _auth.currentUser;
      if (user == null) return;

      // Fetch user data using UserService
      UserModel? fetchedUser = await _userService.getUserModel(user.uid);
      if (fetchedUser != null) {
        setState(() {
          _userModel = fetchedUser;

          // Populate the controllers with user data
          _nameController.text = _userModel?.name ?? "";
          _phoneController.text = _userModel?.phoneNumber ?? "";
          _locationController.text =
              _userModel?.location != null
                  ? "${_userModel!.location!.latitude}, ${_userModel!.location!.longitude}"
                  : ""; //_userModel!.location.toString()): "";
          _emailController.text = _userModel?.email ?? "";
          _dob =
              _userModel?.dob != null
                  ? (_userModel!.dob is DateTime
                      ? _userModel!.dob
                      : DateTime.tryParse(_userModel!.dob.toString()))
                  : null;
          _gender = _userModel?.gender ?? "";
          _photoURL = _userModel?.profileImageUrl ?? "";
          _role = _userModel?.role ?? "N/A"; // Fetch role from UserModel
        });

        // Cache the data locally
        final prefs = await SharedPreferences.getInstance();
        if (_photoURL != null && _photoURL!.isNotEmpty) {
          await prefs.setString('photoURL', _photoURL!);
        } else {
          _photoURL = prefs.getString('photoURL'); // Fallback to cached image
        }
        await prefs.setString('name', _name ?? "");
        await prefs.setString('phone', _phone ?? "");
        await prefs.setString('dob', _dob?.toIso8601String() ?? "");
        await prefs.setString('gender', _gender ?? "");
        await prefs.setString('photoURL', _photoURL ?? "");
        await prefs.setString('role', _role ?? "N/A"); // Cache role locally
        await prefs.setString('location', _location ?? "");
        await prefs.setString('email', _email ?? "");
        await prefs.setString('role', _role ?? "");
      } else {
        throw Exception("Unexpected data format in Firestore document");
      }

      // Fetch user data and convert location to human-readable form
      if (_userModel?.location != null) {
        GeoPoint geoPoint = _userModel!.location!;
        print(
          "GeoPoint data: Latitude = ${geoPoint.latitude}, Longitude = ${geoPoint.longitude}",
        );
        try {
          List<Placemark>? placemarks = await placemarkFromCoordinates(
            geoPoint.latitude,
            geoPoint.longitude,
          );
          if (placemarks.isEmpty) {
            setState(() {
              _locationAddress = "Location not found";
            });
            print("No placemarks found for the given coordinates.");
            return;
          }
          Placemark place = placemarks.first;
          setState(() {
            _locationAddress =
                "${place.street}, ${place.locality}, ${place.country}";
          });
          print("Location converted: $_locationAddress");
        } catch (e) {
          setState(() {
            _locationAddress = "Error fetching location";
          });
          print("Error converting location: $e");
        }
      } else {
        setState(() {
          _locationAddress = "No location available";
        });
        print("No GeoPoint data available.");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "An error occurred while loading your profile. Please try again later.",
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateField(String field, dynamic value) async {
    try {
      if (_userModel == null) return;

      UserModel updatedUserModel = _userModel!.copyWith();

      if (field == "location") {
        List<Location> locations = await locationFromAddress(value);
        if (locations.isNotEmpty) {
          GeoPoint geoPoint = GeoPoint(
            locations.first.latitude,
            locations.first.longitude,
          );
          updatedUserModel = updatedUserModel.copyWith(location: geoPoint);
        }
      } else {
        switch (field) {
          case "name":
            updatedUserModel = updatedUserModel.copyWith(name: value);
            break;
          case "phoneNumber":
            updatedUserModel = updatedUserModel.copyWith(phoneNumber: value);
            break;
          case "dob":
            updatedUserModel = updatedUserModel.copyWith(
              dob: value is DateTime ? value : DateTime.tryParse(value),
            );
            break;
          case "gender":
            updatedUserModel = updatedUserModel.copyWith(gender: value);
            break;
          case "profileImageUrl":
            updatedUserModel = updatedUserModel.copyWith(
              profileImageUrl: value,
            );
            break;
          case "email":
            updatedUserModel = updatedUserModel.copyWith(email: value);
            break;
        }
      }

      await _userService.updateUserProfile(
        _auth.currentUser!.uid,
        updatedUserModel.toJson(),
      );

      _loadUserData();
      final prefs = await SharedPreferences.getInstance();
      if (field == "location") {
        prefs.setString(field, "${value.latitude}, ${value.longitude}");
      } else if (field == "dob") {
        prefs.setString(field, (value as DateTime).toIso8601String());
      } else {
        prefs.setString(field, value.toString());
      }
    } catch (e) {
      print("Error updating $field: $e");
    }
  }

  Future<String> _uploadImage(String userId) async {
    final ref = _storage.ref().child('user_images').child('$userId.jpg');
    await ref.putFile(_imageFile!);
    return await ref.getDownloadURL();
  }

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });

      try {
        String imageUrl = await _uploadImage(_auth.currentUser!.uid);
        await _updateField("photoURL", imageUrl);
        setState(() {
          _photoURL = imageUrl; // Update only after successful upload
        });
        print("photoURL: $_photoURL");
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to upload image: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        backgroundColor: primaryColor,
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.save : Icons.edit),
            onPressed: () async {
              if (_isEditing) {
                await _saveChanges();
              }
              setState(() {
                _isEditing = !_isEditing;
              });
            },
          ),
        ],
      ),
      body:
          _userModel == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 600,
                    ), // Limit width
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Center(
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          GestureDetector(
                          onTap: _pickImage, // Always allow image picking
                          child: CircleAvatar(
                            radius: 60,
                            backgroundColor:
                              Colors.grey[300], // Fallback background color
                            backgroundImage:
                              _photoURL != null && _photoURL!.isNotEmpty
                                ? NetworkImage(_photoURL!)
                                : null, // Use null if no image is available
                            child: (_photoURL == null || _photoURL!.isEmpty)
                              ? const Icon(
                                Icons.person,
                                size: 60,
                                color: Colors.white,
                              )
                              : null, // Show an icon only if no image is available
                          ),
                          ),
                              const SizedBox(height: 16),
                              Text(
                                " ${_role ?? "N/A"}",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                        // Editable Fields
                        _buildEditableField(
                          "Name",
                          _name ?? "N/A",
                          Icons.person,
                          _nameController,
                          (value) => _updateField("name", value),
                        ),
                        _buildEditableField(
                          "Phone",
                          _phone ?? "N/A",
                          Icons.phone,
                          _phoneController,
                          (value) => _updateField("phoneNumber", value),
                          keyboardType: TextInputType.phone,
                        ),
                        _buildEditableField(
                          "Email",
                          _email ?? "N/A",
                          Icons.email,
                          _emailController,
                          (value) => _updateField("email", value),
                        ),
                        _buildEditableDropdownField(
                          "Gender",
                          _gender ?? "N/A",
                          Icons.transgender,
                          (value) => _updateField("gender", value),
                        ),
                        _buildEditableDateField(
                          "Date of Birth",
                          _dob ?? DateTime(2000, 1, 1),
                          Icons.calendar_today,
                          (value) =>
                              _updateField("dob", value.toIso8601String()),
                        ),
                        _buildNonEditableField(
                          "Location",
                          _locationAddress ?? "Fetching location...",
                          Icons.location_on,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
    );
  }

  Widget _buildEditableField(
    String label,
    String value,
    IconData icon,
    TextEditingController controller,
    Function(String) onSave, {
    TextInputType? keyboardType,
  }) {
    return ListTile(
      leading: Icon(icon, color: hintTextColor),
      title:
          _isEditing
              ? TextField(
                controller: controller,
                keyboardType: keyboardType,
                decoration: appInputDecoration(
                  labelText: label,
                  hintText: "Enter $label",
                ),
              )
              : Text(
                "$label: ${controller.text}",
                style:
                    Theme.of(
                      context,
                    ).textTheme.bodyLarge, // Use bodyLarge for larger text
              ),
    );
  }

  Widget _buildEditableDateField(
    String label,
    DateTime value,
    IconData icon,
    Function(DateTime) onSave,
  ) {
    return ListTile(
      leading: Icon(icon, color: hintTextColor),
      title:
          _isEditing
              ? TextField(
                readOnly: true,
                decoration: InputDecoration(
                  labelText: label,
                  border: OutlineInputBorder(),
                ),
                onTap: () async {
                  DateTime? pickedDate = await showDatePicker(
                    context: context,
                    initialDate: value,
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                  );
                  if (pickedDate != null) {
                    onSave(pickedDate);
                  }
                },
              )
              : Text(
                "$label: ${DateFormat.yMd().format(value)}", // Use intl's DateFormat
                style:
                    Theme.of(
                      context,
                    ).textTheme.bodyLarge, // Use bodyLarge for larger text
              ),
    );
  }

  Widget _buildEditableDropdownField(
    String label,
    String? value,
    IconData icon,
    Function(String) onSave,
  ) {
    return ListTile(
      leading: Icon(icon, color: hintTextColor),
      title:
          _isEditing
              ? DropdownButtonFormField<String>(
                value: _genders.contains(value) ? value : null,
                decoration: InputDecoration(
                  labelText: label,
                  border: OutlineInputBorder(),
                ),
                hint: Text(
                  "Select $label",
                  style: appTextStyle(color: hintTextColor),
                ),
                items:
                    _genders.map((String gender) {
                      return DropdownMenuItem<String>(
                        value: gender,
                        child: Text(gender),
                      );
                    }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    onSave(newValue);
                  }
                },
              )
              : Text(
                "$label: ${value ?? "N/A"}",
                style:
                    Theme.of(
                      context,
                    ).textTheme.bodyLarge, // Use bodyLarge for larger text
              ),
    );
  }

  Widget _buildNonEditableField(String label, String value, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: hintTextColor),
      title: Text(
        "$label: $value",
        style:
            Theme.of(
              context,
            ).textTheme.bodyLarge, // Use bodyLarge for larger text
      ),
    );
  }

  Future<void> _saveChanges() async {
    // Save changes logic here
    // You can call `_updateField` for each field if needed
    print("Changes saved!");
  }
}
