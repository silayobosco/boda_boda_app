import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../localization/locales.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../utils/ui_utils.dart';
import '../utils/validation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../widgets/profile_image_picker.dart';

class AdditionalInfoScreen extends StatefulWidget {
  final String userUid;

  const AdditionalInfoScreen({super.key, required this.userUid});

  @override
  _AdditionalInfoScreenState createState() => _AdditionalInfoScreenState();
}

class _AdditionalInfoScreenState extends State<AdditionalInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  File? _pickedImageFile;
  UserModel? _currentUserModel;
  String? _selectedGender;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _phoneController.text = "+255";
    _fetchCurrentUser();
  }

  Future<void> _fetchCurrentUser() async {
    // No need to check for mounted here as this is initState
    final userModel = await _firestoreService.getUser(widget.userUid);
    // Check mounted before calling setState
    if (mounted) {
      setState(() {
        _currentUserModel = userModel;
      });
    }
  }

  // Function to save additional information to Firestore
  Future<void> _saveAdditionalInfo() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      var status = await Permission.location.request();
      if (status.isGranted) {
        LocationSettings locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
        );
        Position position = await Geolocator.getCurrentPosition(
          locationSettings: locationSettings,
        );

        Map<String, dynamic> userData = {
          'phoneNumber': _phoneController.text.trim(),
          'dob': _dobController.text.trim(),
          'gender': _selectedGender,
          'location': GeoPoint(position.latitude, position.longitude),
        };

        if (_pickedImageFile != null) {
          final imageUrl = await _firestoreService.uploadProfileImage(widget.userUid, _pickedImageFile!);
          userData['profileImageUrl'] = imageUrl;
        }

        // Update the user's password in Firebase Authentication
        if (_passwordController.text.isNotEmpty) {
          User? currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null) {
            await currentUser.updatePassword(_passwordController.text.trim());
          } else {
            throw Exception("No authenticated user found.");
          }
        }

        // Save additional user data to Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userUid)
            .update(userData);

        print("Data saved to Firestore: ${userData.toString()}");

        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        print("Location permission denied");
      }
    } catch (e) {
      print("Error saving data: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context, // This is correct
        ).showSnackBar(SnackBar(content: Text("${AppLocale.error_saving_data.getString(context)}: $e")));
      }
    }
  }

  Widget _buildDateField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
  }) {
    return TextFormField(
      controller: controller,
      decoration: appInputDecoration(labelText: labelText, hintText: hintText),
      onTap: () async {
        DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
        );
        if (pickedDate != null) {
          setState(() {
            controller.text =
                "${pickedDate.year}-${pickedDate.month}-${pickedDate.day}";
          });
        }
      },
      validator: (value) {
        if (value == null || value.isEmpty) {
          return AppLocale.date_required.getString(context);
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocale.please_complete_profile.getString(context))),
        );
        return false;
      },
      child: Scaffold(
        appBar: AppBar(title: Text(AppLocale.additional_info.getString(context))),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ProfileImagePicker(
                    initialImageUrl: _currentUserModel?.profileImageUrl,
                    onImagePicked: (pickedImage) {
                      _pickedImageFile = pickedImage;
                    },
                  ),
                  verticalSpaceMedium,
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: appInputDecoration(
                      labelText: AppLocale.phone_number.getString(context),
                      hintText: AppLocale.phone_number.getString(context),
                    ),
                    validator:
                        (value) =>
                            value == null || value.isEmpty
                                ? AppLocale.phone_number_required.getString(context)
                                : Validation.validateEmailPhoneNida(
                                  phone: value,
                                ),
                  ),
                  verticalSpaceMedium,
                  // Replace the existing date picker logic with _buildDateField
                  _buildDateField(
                    controller: _dobController,
                    labelText: AppLocale.date_of_birth.getString(context),
                    hintText: AppLocale.dob_hint.getString(context),
                  ),
                  verticalSpaceMedium,
                  DropdownButtonFormField<String>(
                    value: _selectedGender,
                    onChanged: (value) {
                      setState(() {
                        _selectedGender = value;
                      });
                    },
                    decoration: appInputDecoration(
                      labelText: AppLocale.gender.getString(context),
                      hintText: AppLocale.gender.getString(context),
                    ),
                    items:
                        [AppLocale.male.getString(context), AppLocale.female.getString(context)].map((gender) {
                          return DropdownMenuItem(
                            value: gender,
                            child: Text(gender),
                          );
                        }).toList(),
                    validator:
                        (value) => value == null ? AppLocale.gender_required.getString(context) : null,
                  ),
                  verticalSpaceMedium,
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: AppLocale.password.getString(context),
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator:
                        (value) =>
                            value == null || value.isEmpty
                                ? AppLocale.password_required.getString(context)
                                : null,
                  ),
                  verticalSpaceMedium,
                  TextFormField(
                    controller: _confirmPasswordController,
                    decoration: InputDecoration(
                      labelText: AppLocale.confirm_password.getString(context),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirmPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureConfirmPassword = !_obscureConfirmPassword;
                          });
                        },
                      ),
                    ),
                    obscureText: _obscureConfirmPassword,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppLocale.confirm_password_required.getString(context);
                      }
                      if (value != _passwordController.text) {
                        return AppLocale.passwords_do_not_match.getString(context);
                      }
                      return null;
                    },
                  ),
                  verticalSpaceLarge,
                  ElevatedButton(
                    onPressed: _saveAdditionalInfo,
                    style: appButtonStyle(),
                    child: Text(
                      AppLocale.save.getString(context),
                      style: appTextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
