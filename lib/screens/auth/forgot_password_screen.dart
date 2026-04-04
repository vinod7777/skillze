import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import 'create_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _generatedOTP;
  String? _userName;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Please enter your email');
      return;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+').hasMatch(email)) {
      _showError('Please enter a valid email address');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Check if user exists in Firestore
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        _showError('No account found with this email');
        return;
      }

      _userName = userQuery.docs.first.data()['name'] ?? 'User';

      // Generate 6-digit OTP
      _generatedOTP = (100000 + Random().nextInt(900000)).toString();

      // Send OTP via Apps Script
      final url = Uri.parse(
        'https://script.google.com/macros/s/AKfycbyuZsWCq49NQIMyesXBWmpItV7dAZ04u2TWrw1Bo_YWCWC8ELvvNF311koUb82vm7g_Mw/exec',
      );

      await http.post(
        url,
        body: json.encode({
          'email': email,
          'otp': _generatedOTP,
          'name': _userName,
        }),
      );

      if (!mounted) return;
      setState(() => _isLoading = false);
      _showOTPBottomSheet();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      // Still show OTP dialog for dev/testing even if email fails
      _showOTPBottomSheet();
    }
  }

  void _showOTPBottomSheet() {
    final otpController = TextEditingController();
    int attemptsLeft = 3;
    bool isVerifying = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: context.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 32,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: sheetContext.textLow.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Lock icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: sheetContext.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_reset_rounded,
                      size: 32,
                      color: sheetContext.primary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    'Enter OTP',
                    style: TextStyle(
                      color: sheetContext.textHigh,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We sent a 6-digit code to\n${_emailController.text.trim()}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: sheetContext.textMed,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Attempts indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: attemptsLeft <= 1
                          ? Colors.redAccent.withValues(alpha: 0.1)
                          : sheetContext.surfaceLightColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$attemptsLeft attempt${attemptsLeft == 1 ? '' : 's'} remaining',
                      style: TextStyle(
                        color: attemptsLeft <= 1 ? Colors.redAccent : sheetContext.textMed,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // OTP input
                  Container(
                    decoration: BoxDecoration(
                      color: sheetContext.surfaceColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: sheetContext.border),
                    ),
                    child: TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      style: TextStyle(
                        color: sheetContext.textHigh,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 12,
                      ),
                      decoration: InputDecoration(
                        hintText: '000000',
                        hintStyle: TextStyle(
                          color: sheetContext.textLow.withValues(alpha: 0.4),
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 12,
                        ),
                        counterText: '',
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Verify button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: sheetContext.primary,
                        foregroundColor: sheetContext.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: isVerifying
                          ? null
                          : () async {
                              final enteredOtp = otpController.text.trim();

                              if (enteredOtp.length != 6) {
                                ScaffoldMessenger.of(sheetContext).showSnackBar(
                                  const SnackBar(content: Text('Please enter the full 6-digit code')),
                                );
                                return;
                              }

                              if (enteredOtp == _generatedOTP) {
                                // OTP correct → navigate to create password
                                setModalState(() => isVerifying = true);
                                Navigator.pop(sheetContext); // close bottom sheet

                                if (!mounted) return;
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CreatePasswordScreen(
                                      email: _emailController.text.trim(),
                                    ),
                                  ),
                                );
                              } else {
                                // Wrong OTP
                                attemptsLeft--;
                                otpController.clear();

                                if (attemptsLeft <= 0) {
                                  // No attempts left → close and go back
                                  Navigator.pop(sheetContext);
                                  if (!mounted) return;
                                  _showError('Too many failed attempts. Please try again.');
                                } else {
                                  setModalState(() {}); // rebuild to show updated attempts
                                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Incorrect OTP. $attemptsLeft attempt${attemptsLeft == 1 ? '' : 's'} left.',
                                      ),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                            },
                      child: isVerifying
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: sheetContext.onPrimary,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'Verify OTP',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Resend / Cancel row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                        },
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: sheetContext.textLow,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        color: sheetContext.border,
                      ),
                      TextButton(
                        onPressed: () {
                          // Regenerate OTP and resend
                          _generatedOTP = (100000 + Random().nextInt(900000)).toString();
                          otpController.clear();
                          setModalState(() {
                            attemptsLeft = 3;
                          });

                          // Fire-and-forget resend
                          final url = Uri.parse(
                            'https://script.google.com/macros/s/AKfycbyuZsWCq49NQIMyesXBWmpItV7dAZ04u2TWrw1Bo_YWCWC8ELvvNF311koUb82vm7g_Mw/exec',
                          );
                          http.post(
                            url,
                            body: json.encode({
                              'email': _emailController.text.trim(),
                              'otp': _generatedOTP,
                              'name': _userName ?? 'User',
                            }),
                          );

                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text('New OTP sent! Check your email.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        },
                        child: Text(
                          'Resend Code',
                          style: TextStyle(
                            color: sheetContext.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
      backgroundColor: context.bg,
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
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.border),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.chevron_left,
                      size: 20,
                      color: context.textHigh,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),

              // Heading
              Text(
                'Forgot\npassword?',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: context.textHigh,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),

              // Description
              Text(
                "Enter your email and we'll send you a verification code to reset your password.",
                style: TextStyle(
                  fontSize: 15,
                  color: context.textMed,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),

              // Email label
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'EMAIL',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: context.textLow,
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
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.email_outlined,
                      size: 18,
                      color: context.textLow,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: context.textHigh,
                        ),
                        decoration: InputDecoration(
                          hintText: 'your@email.com',
                          hintStyle: TextStyle(color: context.textLow),
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
                  onTap: _isLoading ? null : _sendOTP,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: context.primary,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: context.primary.withValues(alpha: 0.2),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
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
