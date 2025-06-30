import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';
import '../utils/ui_utils.dart';
import '../utils/validation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/user_model.dart';
import '../widgets/profile_image_picker.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();
  final FirestoreService _firestoreService = FirestoreService();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _phoneController = TextEditingController(
    text: "+255",
  );
  final TextEditingController _dobController = TextEditingController();

  String? _selectedGender;
  late AnimationController _animationController;
  late Animation<double> _animation;
  File? _pickedImageFile;

  final _formKey = GlobalKey<FormState>();

  final bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.locationWhenInUse.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission is required.")),
        );
      }
      throw Exception("Location permission denied");
    }
  }

  void register() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await _requestLocationPermission();

      String name = _nameController.text.trim();
      String email = _emailController.text.trim();
      String password = _passwordController.text.trim();
      String phone = _phoneController.text.trim();
      String dob = _dobController.text.trim();
      String gender = _selectedGender ?? "";

      String? imageUrl;
      if (_pickedImageFile != null) {
        // Temporarily create a dummy user to get UID for storage path
        final tempUser = await _auth.createUserWithEmailAndPassword(email: email, password: password);
        imageUrl = await _firestoreService.uploadProfileImage(tempUser.user!.uid, _pickedImageFile!);
        await tempUser.user!.delete(); // Delete temp user, will be recreated
      }

      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: email, password: password);

      User? user = userCredential.user;
      if (user != null) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        // Create a UserModel instance
        UserModel newUser = UserModel(
          uid: user.uid,
          name: name,
          email: email,
          phoneNumber: phone,
          dob: DateTime.tryParse(dob),
          gender: gender,
          location: GeoPoint(position.latitude, position.longitude),
          role: "Customer",
          profileImageUrl: imageUrl,
        );


        await _userService.createUserDocument(newUser);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Registration successful! Please login."),
          ),
        );
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Registration Failed: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacementNamed(context, '/login');
        return false;
      },
      child: Scaffold(
        appBar: AppBar(title: const Text("Register")),
        body: FadeTransition(
          opacity: _animation,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    ProfileImagePicker(
                      onImagePicked: (pickedImage) {
                        _pickedImageFile = pickedImage;
                      },
                    ),
                    verticalSpaceMedium,
                    _buildTextField(
                      controller: _nameController,
                      labelText: "Full Name",
                      hintText: "Full Name",
                      validator:
                          (value) =>
                              value == null || value.isEmpty
                                  ? 'Please enter your full name'
                                  : null,
                    ),
                    verticalSpaceMedium,
                    _buildTextField(
                      controller: _emailController,
                      labelText: "Email",
                      hintText: "Email",
                      validator:
                          (value) =>
                              Validation.validateEmailPhoneNida(email: value),
                    ),
                    verticalSpaceMedium,
                    _buildPasswordField(
                      controller: _passwordController,
                      labelText: "Password",
                      obscureText: _obscurePassword,
                    ),
                    verticalSpaceMedium,
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      decoration: InputDecoration(
                        labelText: "Confirm Password",
                        hintText: "Confirm Password",
                        border: const OutlineInputBorder(),
                        suffixIcon: GestureDetector(
                          onLongPress: () {
                            setState(() {
                              _obscureConfirmPassword = false;
                            });
                          },
                          onLongPressUp: () {
                            setState(() {
                              _obscureConfirmPassword = true;
                            });
                          },
                          child: const Icon(Icons.remove_red_eye),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your password';
                        }
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    verticalSpaceMedium,
                    _buildTextField(
                      controller: _phoneController,
                      labelText: "Phone Number",
                      hintText: "Phone Number",
                      keyboardType: TextInputType.phone,
                      validator:
                          (value) =>
                              Validation.validateEmailPhoneNida(phone: value),
                    ),
                    verticalSpaceMedium,
                    _buildDateField(
                      controller: _dobController,
                      labelText: "Date of Birth",
                      hintText: "YYYY-MM-DD",
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
                        labelText: "Gender",
                        hintText: "Gender",
                      ),
                      items:
                          const ["Male", "Female"].map((gender) {
                            return DropdownMenuItem(
                              value: gender,
                              child: Text(gender),
                            );
                          }).toList(),
                    ),
                    verticalSpaceLarge,
                    ElevatedButton(
                      onPressed: register,
                      style: appButtonStyle(),
                      child: Text(
                        "Register",
                        style: appTextStyle(color: Colors.white),
                      ),
                    ),
                    verticalSpaceMedium,
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      child: Text(
                        "Already have an account? Login",
                        style: appTextStyle(color: primaryColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ... (rest of your buildTextField, buildPasswordField, buildDateField widgets)

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: appInputDecoration(labelText: labelText, hintText: hintText),
      validator: validator,
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String labelText,
    required bool obscureText,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: labelText,
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
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
          return 'Please enter a date';
        }
        return null;
      },
    );
  }
}
