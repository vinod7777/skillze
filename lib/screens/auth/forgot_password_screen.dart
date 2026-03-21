import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter your email')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent! Check your inbox.'),
        ),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = 'An error occurred.';
      if (e.code == 'user-not-found') {
        message = 'No user found with this email.';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address.';
      } else if (e.message?.contains('reCAPTCHA') ?? false) {
        message = 'Safety check failed. Please ensure Google Play Services is up to date or verify your app in Firebase Console.';
      } else {
        message = e.message ?? 'Authentication error.';
      }
      _showError(message);
    } catch (e) {
      if (!mounted) return;
      _showError('Error: Connection timed out or service unavailable.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
     ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.chevron_left,
                      size: 20,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Heading
              const Text(
                'Forgot\npassword?',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),

              // Description
              const Text(
                "Fill in your email and we'll send you a link to reset your password.",
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF64748B),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),

              // Email label
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'EMAIL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFA1A1AA),
                    letterSpacing: 1,
                  ),
                ),
              ),

              // Email field
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.email_outlined,
                      size: 18,
                      color: Color(0xFFA1A1AA),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF18181B),
                        ),
                        decoration: const InputDecoration(
                          hintText: 'your@email.com',
                          hintStyle: TextStyle(color: Color(0xFFA1A1AA)),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Send Code button
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: GestureDetector(
                  onTap: _isLoading ? null : _sendCode,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F2F6A),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF5E4399).withValues(alpha: 0.2),
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
                              'Send Code',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 18,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
