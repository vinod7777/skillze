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
import '../../theme/app_theme.dart';
import '../../widgets/clean_text_field.dart';

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
  final _roleController = TextEditingController();

  final List<String> _suggestedRoles = [
    'Flutter Developer', 'React Developer', 'Product Designer', 'UI/UX Designer', 
    'Chef', 'Baker', 'Painter', 'Fashion Designer', 'Photographer', 'Videographer',
    'Financial Analyst', 'Marketing Manager', 'Content Creator', 'Social Media Manager',
    'Fitness Trainer', 'Yoga Instructor', 'Entrepreneur', 'Student', 'Teacher', 'Architect',
    'Interior Designer', 'Makeup Artist', 'Barber', 'Counselor', 'Data Scientist', 'Software Engineer'
  ];

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
    _roleController.dispose();
    super.dispose();
  }

  Future<void> _validateUsername() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      if (mounted) setState(() => _usernameError = 'Username required');
      return;
    }
    final usernameQuery = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .get();
    if (usernameQuery.docs.isNotEmpty) {
      if (mounted) setState(() => _usernameError = 'Username is already taken');
    } else {
      if (mounted) setState(() => _usernameError = null);
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
        _usernameController.text.isEmpty ||
        ProfanityFilterService.hasProfanity(_usernameController.text) ||
        ProfanityFilterService.hasProfanity(_bioController.text)) {
      showProfanityWarning(context);
      return;
    }

    setState(() => _isLoading = true);

    try {
      _generatedOTP = (100000 + Random().nextInt(900000)).toString();
      final url = Uri.parse(
        'https://script.google.com/macros/s/AKfycbyuZsWCq49NQIMyesXBWmpItV7dAZ04u2TWrw1Bo_YWCWC8ELvvNF311koUb82vm7g_Mw/exec',
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
      backgroundColor: context.bg,
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
                   Text(
                    'Verify your Email',
                    style: TextStyle(
                      color: context.textHigh,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'We sent a 6-digit code to ${_emailController.text.trim()}. Please enter it below.',
                    textAlign: TextAlign.center,
                    style:  TextStyle(color: context.textMed),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.border),
                    ),
                    child: TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style:  TextStyle(
                        color: context.textHigh,
                        fontSize: 24,
                        letterSpacing: 8,
                      ),
                      decoration:  InputDecoration(
                        hintText: '000000',
                        hintStyle: TextStyle(color: context.textLow),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
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
                        backgroundColor: context.primary,
                        foregroundColor: context.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      onPressed: isVerifying
                          ? null
                          : () async {
                              final enteredOtp = otpController.text.trim();
                              
                              if (enteredOtp == _generatedOTP) {
                                setModalState(() => isVerifying = true);
                                try {
                                  bool success = await _finalizeSignup();
                                  if (!context.mounted) return;
                                  setModalState(() => isVerifying = false);
                                  
                                  if (success) {
                                    if (!context.mounted) return;
                                    await PushNotificationService.updateToken();
                                    if (!context.mounted) return;
                                    Navigator.pushReplacementNamed(context, '/skills');
                                  }
                                } catch (e) {
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
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: context.onPrimary,
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
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );

      await userCredential.user?.updateDisplayName(_nameController.text.trim());

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
            'uid': userCredential.user!.uid,
            'name': _nameController.text.trim(),
            'username': _usernameController.text.trim(),
            'email': _emailController.text.trim(),
            'bio': _bioController.text.trim(),
            'role': _roleController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
            'followers': 0,
            'following': 0,
            'skills': [],
            'onboardingCompleted': false,
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

        bool needsOnboarding = true;

        if (!userDoc.exists) {
          final String rawPrefix = user.email?.split('@')[0] ?? 'user_${user.uid.substring(0, 5)}';
          final String emailPrefix = rawPrefix.replaceAll(' ', '').toLowerCase();
          
          String derivedName = user.displayName ?? '';
          if (derivedName.trim().isEmpty) {
            derivedName = emailPrefix[0].toUpperCase() + emailPrefix.substring(1);
          }
          if (derivedName.trim().isEmpty) derivedName = 'New User';

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'uid': user.uid,
                'name': derivedName,
                'email': user.email,
                'username': emailPrefix,
                'profileImageUrl': user.photoURL,
                'createdAt': FieldValue.serverTimestamp(),
                'followers': 0,
                'following': 0,
                'bio': 'Hi there! I am using Skillze.',
                'onboardingCompleted': false,
                'skills': [],
              });
        } else {
          final data = userDoc.data()!;
          final List skills = data['skills'] ?? [];
          final bool onboardingCompleted = data['onboardingCompleted'] ?? false;
          
          // If name or username is missing/default, update from Google info
          if (data['name'] == 'New User' || data['name'] == null || data['username'] == null || data['username'] == '') {
            final String rawPrefix = user.email?.split('@')[0] ?? 'user_${user.uid.substring(0, 5)}';
            final String emailPrefix = rawPrefix.replaceAll(' ', '').toLowerCase();
            
            String derivedName = data['name'] ?? '';
            if (derivedName == 'New User' || derivedName.isEmpty) {
              derivedName = user.displayName ?? (emailPrefix[0].toUpperCase() + emailPrefix.substring(1));
            }

            await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
              'name': derivedName,
              'username': data['username'] ?? emailPrefix,
              'profileImageUrl': user.photoURL,
            });
          }
          
          if (skills.isNotEmpty && onboardingCompleted) {
            needsOnboarding = false;
          }
        }

        if (!mounted) return;
        await PushNotificationService.updateToken();
        
        if (needsOnboarding) {
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
      backgroundColor: context.bg,
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
                    color: context.surfaceLightColor,
                    borderRadius: BorderRadius.circular(10),
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
                            child:  Text(
                              'Sign in',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: context.textLow,
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
                            color: context.surfaceColor,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child:  Text(
                            'Sign up',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.textHigh,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // Heading
                 Text(
                  'Hello there,',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: context.textHigh,
                  ),
                ),
                const SizedBox(height: 8),
                 Text(
                  'We are excited to see you here',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: context.textMed,
                  ),
                ),
                const SizedBox(height: 32),

                // Name field
                CleanTextField(
                  label: 'NAME',
                  hintText: 'Enter your name',
                  controller: _nameController,
                  prefixIcon: Icons.person_outline,
                ),
                const SizedBox(height: 16),

                // Username field
                CleanTextField(
                  label: 'USERNAME',
                  hintText: 'Choose a username',
                  controller: _usernameController,
                  prefixIcon: Icons.alternate_email,
                  errorText: _usernameError,
                  onChanged: (val) async {
                    await _validateUsername();
                  },
                ),
                const SizedBox(height: 16),

                // Email field
                CleanTextField(
                  label: 'EMAIL',
                  hintText: 'your@email.com',
                  controller: _emailController,
                  prefixIcon: Icons.email_outlined,
                  errorText: _emailError,
                  onChanged: (val) {
                    _validateEmail();
                  },
                ),
                const SizedBox(height: 16),

                // Role field with Autocomplete
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<String>.empty();
                    }
                    return _suggestedRoles.where((role) {
                      return role.toLowerCase().contains(textEditingValue.text.toLowerCase());
                    });
                  },
                  onSelected: (String selection) {
                    _roleController.text = selection;
                  },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                     // Sync internal controller
                    if (_roleController.text != controller.text && _roleController.text.isNotEmpty && controller.text.isEmpty) {
                      controller.text = _roleController.text;
                    }

                    return CleanTextField(
                      label: 'PROFESSIONAL ROLE',
                      hintText: 'e.g. Chef, Painter, Developer',
                      controller: controller,
                      focusNode: focusNode,
                      prefixIcon: Icons.work_outline,
                      onChanged: (val) {
                        _roleController.text = val;
                      },
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 10,
                        borderRadius: BorderRadius.circular(10),
                        color: context.surfaceColor,
                        shadowColor: Colors.black.withValues(alpha: 0.1),
                        child: Container(
                          width: MediaQuery.of(context).size.width - 48,
                          constraints: const BoxConstraints(maxHeight: 250),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            separatorBuilder: (context, index) => Divider(height: 1, color: context.border.withValues(alpha: 0.5)),
                            itemBuilder: (BuildContext context, int index) {
                              final String option = options.elementAt(index);
                              return ListTile(
                                dense: true,
                                title: Text(option, style: TextStyle(color: context.textHigh)),
                                onTap: () => onSelected(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Password field
                CleanTextField(
                  label: 'PASSWORD',
                  hintText: 'Create a password',
                  controller: _passwordController,
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  errorText: _passwordError,
                  onChanged: (val) {
                    _validatePassword();
                  },
                ),
                const SizedBox(height: 16),

                // Confirm Password field
                CleanTextField(
                  label: 'CONFIRM PASSWORD',
                  hintText: 'Confirm your password',
                  controller: _confirmPasswordController,
                  prefixIcon: Icons.lock_outline,
                  isPassword: true,
                  errorText: _confirmPasswordError,
                  onChanged: (val) {
                    _validateConfirmPassword();
                  },
                ),

                const SizedBox(height: 8),

                // Sign Up button
                GestureDetector(
                  onTap: _isLoading ? null : _initiateSignup,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: context.primary,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: context.primary.withValues(alpha: 0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 10),
                          spreadRadius: -3,
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isLoading
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: context.isDark ? Colors.black : Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Sign up',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: context.isDark ? Colors.black : Colors.white,
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
                        color: context.border,
                      ),
                    ),
                     Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Or continue with',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: context.textLow,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: context.border,
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
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.border),
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
                                 Icon(Icons.g_mobiledata, size: 20, color: context.textHigh),
                          ),
                          const SizedBox(width: 8),
                           Text(
                            'Google',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: context.textHigh,
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
