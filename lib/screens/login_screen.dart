import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../utils/ui_utils.dart';
import '../utils/validation.dart';
import '../screens/home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserService _userService = UserService();
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  void login() async {
    if (!_formKey.currentState!.validate()) return;

    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;
      if (user != null && mounted) {
        final userDoc = await _userService.getUserModel(user.uid);
        if (userDoc != null) { // Check if userDoc is not null
        final role = userDoc.role; // Access the role directly from UserModel
          if (role != null) {
            navigateToHome(role);
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("User role not found.")),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("User document not found.")),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Login Failed: $e")),
        );
      }
    }
  }

  void navigateToHome(String role) {
    if (!mounted) return;
    Future.microtask(() {
      Navigator.popUntil(context, (route) => route.isFirst);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    });
  }

  void showResetPasswordDialog() {
    TextEditingController emailController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Reset Password"),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: "Enter your email"),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              String email = emailController.text.trim();
              try {
                final methods = await _auth.fetchSignInMethodsForEmail(email);
                if (methods.isNotEmpty) {
                  await _auth.sendPasswordResetEmail(email: email);
                  Navigator.of(context).pop();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Password reset email sent")),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Email not registered.")),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                }
              }
            },
            child: const Text("Send"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Welcome",
                    style: headingTextStyle(fontSize: 30),
                  ),
                  verticalSpaceMedium,
                  Text(
                    "Login to your account",
                    style: appTextStyle(
                        color: hintTextColor, fontWeight: FontWeight.bold),
                  ),
                  verticalSpaceLarge,
                  TextFormField(
                    controller: _emailController,
                    decoration:
                        appInputDecoration(hintText: "Email", labelText: "Email"),
                    validator: (value) =>
                        Validation.validateEmailPhoneNida(email: value),
                  ),
                  verticalSpaceMedium,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: "Password",
                          labelText: "Password",
                          border: const OutlineInputBorder(),
                          suffixIcon: GestureDetector(
                            onLongPress: () {
                              setState(() {
                                _obscurePassword = false;
                              });
                            },
                            onLongPressUp: () {
                              setState(() {
                                _obscurePassword = true;
                              });
                            },
                            child: const Icon(Icons.remove_red_eye),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Please enter your password'
                            : null,
                      ),
                      TextButton(
                        onPressed: showResetPasswordDialog,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          "Forgot Password?",
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  verticalSpaceLarge,
                  ElevatedButton(
                    onPressed: login,
                    style: appButtonStyle(),
                    child: Text("Login", style: appTextStyle(color: Colors.white)),
                  ),
                  verticalSpaceMedium,
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _authService.signInWithGoogle(context);
                    },
                    icon: Image.asset(
                      'assets/google_logo.png',
                      height: 24,
                    ),
                    label: const Text(
                      "Sign in with Google",
                      style: TextStyle(color: Colors.white),
                    ),
                    style: appButtonStyle(),
                  ),
                  const SizedBox(height: 50),
                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(context, '/register');
                    },
                    child: Text(
                      "Don't have an account? Register",
                      style: appTextStyle(color: primaryColor),
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