import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../utils/ui_utils.dart';
import '../utils/validation.dart';
import '../screens/home_screen.dart';
import '../localization/locales.dart';

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
                SnackBar(content: Text(AppLocale.user_role_not_found.getString(context))),
              );
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocale.user_document_not_found.getString(context))),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${AppLocale.login_failed.getString(context)}$e")),
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
        title: Text(AppLocale.reset_password.getString(context)),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: AppLocale.enter_your_email.getString(context)),
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
                      SnackBar(content: Text(AppLocale.password_reset_email_sent.getString(context))),
                    );
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(AppLocale.email_not_registered.getString(context))),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${AppLocale.error_prefix.getString(context)}$e")));
                }
              }
            },
            child: Text(AppLocale.send.getString(context)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = FlutterLocalization.instance;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(AppLocale.selectLanguage.getString(context)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        title: Text(AppLocale.english.getString(context)),
                        onTap: () {
                          localization.translate('en');
                          Navigator.pop(context);
                        },
                      ),
                      ListTile(
                        title: Text(AppLocale.swahili.getString(context)),
                        onTap: () {
                          localization.translate('sw');
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
            icon: const Icon(Icons.language),
            label: Text(localization.currentLocale!.languageCode.toUpperCase()),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset('assets/icon.png', height: 80), // App Logo
                    verticalSpaceMedium,
                    Text(
                      AppLocale.welcome.getString(context),
                      textAlign: TextAlign.center,
                      style: headingTextStyle(fontSize: 32),
                    ),
                    verticalSpaceSmall,
                    Text(
                      AppLocale.login_to_account.getString(context),
                      textAlign: TextAlign.center,
                      style: appTextStyle(
                          color: hintTextColor, fontWeight: FontWeight.bold),
                    ),
                    verticalSpaceLarge,
                    TextFormField(
                      controller: _emailController,
                      decoration: appInputDecoration(
                          labelText: AppLocale.email.getString(context)),
                      validator: (value) =>
                          Validation.validateEmailPhoneNida(email: value),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    verticalSpaceMedium,
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: appInputDecoration(
                        labelText: AppLocale.password.getString(context),
                      ).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? AppLocale.please_enter_password.getString(context)
                          : null,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: showResetPasswordDialog,
                        child: Text(AppLocale.forgot_password.getString(context)),
                      ),
                    ),
                    verticalSpaceMedium,
                    ElevatedButton(
                      onPressed: login,
                      style: appButtonStyle().copyWith(
                          padding: MaterialStateProperty.all<EdgeInsets>(
                              const EdgeInsets.symmetric(vertical: 16))),
                      child: Text(AppLocale.login.getString(context),
                          style: appTextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                    ),
                    verticalSpaceMedium,
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _authService.signInWithGoogle(context);
                      },
                      icon: Image.asset(
                        'assets/google_logo.png',
                        height: 22,
                      ),
                      label: Text(
                        AppLocale.sign_in_with_google.getString(context),
                        style: appTextStyle(
                            color: Colors.black87, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/register');
                      },
                      child: Text(
                        AppLocale.dont_have_account_register.getString(context),
                        style: appTextStyle(color: primaryColor),
                      ),
                    ),
                  ],
                )),
          ),
        ),
      ),
    );
  }
}