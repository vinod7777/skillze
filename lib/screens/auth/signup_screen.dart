import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../services/profanity_filter_service.dart';
import '../../services/push_notification_service.dart';
import '../../utils/profanity_helper.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _bioController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _generatedOTP;

  String? _usernameError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _emailError;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _validateUsername() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => _usernameError = 'Username required');
      return;
    }
    final usernameQuery = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .get();
    if (usernameQuery.docs.isNotEmpty) {
      setState(() => _usernameError = 'Username is already taken');
    } else {
      setState(() => _usernameError = null);
    }
  }

  void _validatePassword() {
    final password = _passwordController.text;
    if (password.length < 6) {
      setState(() => _passwordError = 'Password must be at least 6 characters');
    } else if (!RegExp(
      r'^(?=.*[A-Za-z])(?=.*\d).{6,}$',
    ).hasMatch(password)) {
      setState(
        () => _passwordError = 'Password must contain letters and numbers',
      );
    } else {
      setState(() => _passwordError = null);
    }
    _validateConfirmPassword();
  }

  void _validateConfirmPassword() {
    if (_confirmPasswordController.text != _passwordController.text) {
      setState(() => _confirmPasswordError = 'Passwords do not match');
    } else {
      setState(() => _confirmPasswordError = null);
    }
  }

  void _validateEmail() {
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+').hasMatch(email)) {
      setState(() => _emailError = 'Invalid email format');
    } else {
      setState(() => _emailError = null);
    }
  }

  Future<void> _initiateSignup() async {
    // Trigger all validations
    _validateEmail();
    _validatePassword();
    _validateConfirmPassword();
    await _validateUsername();

    if (!mounted) return;
    if (_nameController.text.isEmpty ||
        _usernameController.text.isEmpty ||
        _emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }
    if (!mounted) return;
    if (_usernameError != null ||
        _passwordError != null ||
        _confirmPasswordError != null ||
        _emailError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fix errors before submitting')),
      );
      return;
    }

    if (!mounted) return;
    if (ProfanityFilterService.hasProfanity(_nameController.text) ||
        ProfanityFilterService.hasProfanity(_usernameController.text) ||
        ProfanityFilterService.hasProfanity(_bioController.text)) {
      showProfanityWarning(context);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Generate 6 digit OTP
      _generatedOTP = (100000 + Random().nextInt(900000)).toString();

      // 2. Send via Google Apps Script Web App Endpoint
      final url = Uri.parse(
        'https://script.google.com/macros/s/AKfycbyamZ6LtDof6wmKivaIoR7PLqMf4XG8cw7edxnA0wl0w-3Tzsd_WrFFUTqCK59_mSas0Q/exec',
      );

      await http.post(
        url,
        body: json.encode({
          'email': _emailController.text.trim(),
          'otp': _generatedOTP,
          'name': _nameController.text.trim(),
        }),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      _showOTPDialog();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showOTPDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Note: OTP email sending failed, but continuing for dev: ${e.toString()}',
          ),
        ),
      );
    }
  }

  void _showOTPDialog() {
    final otpController = TextEditingController();
    bool isVerifying = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8F9FB),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 32,
                bottom: MediaQuery.of(context).viewInsets.bottom + 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Verify your Email',
                    style: TextStyle(
                      color: Color(0xFF18181B),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'We sent a 6-digit code to ${_emailController.text.trim()}. Please enter it below.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF71717A)),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                    ),
                    child: TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF18181B),
                        fontSize: 24,
                        letterSpacing: 8,
                      ),
                      decoration: const InputDecoration(
                        hintText: '000000',
                        hintStyle: TextStyle(color: Color(0xFFA1A1AA)),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F2F6A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: isVerifying
                          ? null
                          : () async {
                              final enteredOtp = otpController.text.trim();
                               debugPrint('SignupDEBUG: Entered OTP: $enteredOtp, Generated OTP: $_generatedOTP');
                              
                              if (enteredOtp == _generatedOTP) {
                                setModalState(() => isVerifying = true);
                                debugPrint('SignupDEBUG: Starting finalizeSignup...');
                                
                                try {
                                  bool success = await _finalizeSignup();
                                  debugPrint('SignupDEBUG: finalizeSignup result: $success');
                                  
                                  if (!context.mounted) return;
                                  setModalState(() => isVerifying = false);
                                  
                                  if (success) {
                                    if (!context.mounted) return;
                                    await PushNotificationService.updateToken();
                                    if (!context.mounted) return;
                                    Navigator.pushReplacementNamed(context, '/skills');
                                  }
                                } catch (e) {
                                  debugPrint('SignupDEBUG: Critical error in OTP flow: $e');
                                  if (context.mounted) {
                                    setModalState(() => isVerifying = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Registration failed: $e')),
                                    );
                                  }
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Invalid OTP. Please check your email and try again.'),
                                  ),
                                );
                              }
                            },
                      child: isVerifying
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Verify & Register',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _finalizeSignup() async {
    final name = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final bio = _bioController.text.trim();

    if (ProfanityFilterService.hasProfanity(name) ||
        ProfanityFilterService.hasProfanity(username) ||
        ProfanityFilterService.hasProfanity(bio)) {
      showProfanityWarning(context);
      return false;
    }

    try {
      // Create the user
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      // Update standard display name
      await userCredential.user?.updateDisplayName(_nameController.text.trim());

      // Store extra metadata in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
            'uid': userCredential.user!.uid,
            'name': _nameController.text.trim(),
            'username': _usernameController.text.trim(),
            'email': _emailController.text.trim(),
            'bio': _bioController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
            'followers': 0,
            'following': 0,
          });

      return true;
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred during sign up.';
      if (e.code == 'weak-password') {
        message = 'The password provided is too weak.';
      } else if (e.code == 'email-already-in-use') {
        message = 'The account already exists for that email.';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is badly formatted.';
      }
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return false;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      return false;
    }
  }

  Widget _buildCardField({
    required String label,
    required String hint,
    required TextEditingController controller,
    IconData? prefixIcon,
    bool isPassword = false,
    bool isObscure = false,
    VoidCallback? onVisibilityToggle,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFF4F4F5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFA1A1AA),
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (prefixIcon != null) ...[
                    Icon(prefixIcon, size: 18, color: const Color(0xFFA1A1AA)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: FocusScope(
                      child: Focus(
                        onFocusChange: (hasFocus) async {
                          if (!hasFocus) {
                            if (controller == _usernameController) {
                              await _validateUsername();
                            }
                            if (controller == _passwordController) {
                              _validatePassword();
                            }
                            if (controller == _confirmPasswordController) {
                              _validateConfirmPassword();
                            }
                            if (controller == _emailController) {
                              _validateEmail();
                            }
                          }
                        },
                        child: TextField(
                          controller: controller,
                          obscureText: isObscure,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF18181B),
                          ),
                          decoration: InputDecoration(
                            hintText: hint,
                            hintStyle: const TextStyle(
                              color: Color(0xFFA1A1AA),
                            ),
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isPassword)
                    GestureDetector(
                      onTap: onVisibilityToggle,
                      child: Icon(
                        isObscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: const Color(0xFFA1A1AA),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Text(
              errorText,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId:
            '536909553761-b91jfbv4082fs327f6rcq556ptp3he31.apps.googleusercontent.com',
      );
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!userDoc.exists) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'uid': user.uid,
                'name': user.displayName ?? 'New User',
                'email': user.email,
                'username':
                    user.email?.split('@')[0] ??
                    'user_${user.uid.substring(0, 5)}',
                'profileImageUrl': user.photoURL,
                'createdAt': FieldValue.serverTimestamp(),
                'followers': 0,
                'following': 0,
                'bio': 'Hi there! I am using Skillze.',
              });
        }

        if (!mounted) return;
        await PushNotificationService.updateToken();
        if (!userDoc.exists) {
          Navigator.pushReplacementNamed(context, '/skills');
        } else {
          Navigator.pushReplacementNamed(context, '/main');
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Google Sign-In Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),

                // Sign in / Sign up toggle
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      // Sign in (inactive)
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              Navigator.pushReplacementNamed(context, '/login'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: const Text(
                              'Sign in',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFFA1A1AA),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Sign up (active)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Text(
                            'Sign up',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF18181B),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // Heading
                const Text(
                  'Hello there,',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF18181B),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'We are excited to see you here',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF71717A),
                  ),
                ),
                const SizedBox(height: 32),

                // Name field
                _buildCardField(
                  label: 'NAME',
                  hint: 'Enter your name',
                  controller: _nameController,
                  prefixIcon: Icons.person_outline,
                ),

                // Username field
                _buildCardField(
                  label: 'USERNAME',
                  hint: 'Choose a username',
                  controller: _usernameController,
                  prefixIcon: Icons.alternate_email,
                  errorText: _usernameError,
                ),

                // Email field
                _buildCardField(
                  label: 'EMAIL',
                  hint: 'your@email.com',
                  controller: _emailController,
                  prefixIcon: Icons.email_outlined,
                  errorText: _emailError,
                ),

                // Password field
                _buildCardField(
                  label: 'PASSWORD',
                  hint: 'Create a password',
                  controller: _passwordController,
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  isObscure: _obscurePassword,
                  onVisibilityToggle: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  errorText: _passwordError,
                ),

                // Confirm Password field
                _buildCardField(
                  label: 'CONFIRM PASSWORD',
                  hint: 'Confirm your password',
                  controller: _confirmPasswordController,
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  isObscure: _obscurePassword,
                  onVisibilityToggle: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  errorText: _confirmPasswordError,
                ),

                const SizedBox(height: 8),

                // Sign Up button
                GestureDetector(
                  onTap: _isLoading ? null : _initiateSignup,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F2F6A),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF5E3B95).withValues(alpha: 0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 10),
                          spreadRadius: -3,
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Sign up',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Or continue with
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1,
                        color: const Color(0xFFE4E4E7),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Or continue with',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFA1A1AA),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: const Color(0xFFE4E4E7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Google button
                Center(
                  child: GestureDetector(
                    onTap: _isLoading ? null : _handleGoogleSignIn,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 35,
                        vertical: 15,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF4F4F5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.network(
                            'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/1200px-Google_%22G%22_logo.svg.png',
                            height: 20,
                            width: 20,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.g_mobiledata, size: 20),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Google',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF3F3F46),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
