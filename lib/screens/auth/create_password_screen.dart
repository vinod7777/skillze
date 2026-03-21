import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreatePasswordScreen extends StatefulWidget {
  final String email;

  const CreatePasswordScreen({super.key, required this.email});

  @override
  State<CreatePasswordScreen> createState() => _CreatePasswordScreenState();
}

class _CreatePasswordScreenState extends State<CreatePasswordScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isResetting = false;

  bool get _hasMinLength => _newPasswordController.text.length >= 8;
  bool get _hasSpecialChar => RegExp(
    r'[!@#$%^&*(),.?":{}|<>0-9]',
  ).hasMatch(_newPasswordController.text);
  bool get _passwordsMatch =>
      _newPasswordController.text == _confirmPasswordController.text &&
      _confirmPasswordController.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(() => setState(() {}));
    _confirmPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    if (!_hasMinLength || !_hasSpecialChar || !_passwordsMatch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please meet all password requirements')),
      );
      return;
    }

    setState(() => _isResetting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updatePassword(_newPasswordController.text);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: widget.email);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password reset email sent'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Error resetting password')),
        );
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
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
              const SizedBox(height: 16),
              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E4E7)),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    color: Color(0xFF18181B),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Create New\nPassword',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF18181B),
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your new password must be different\nfrom previously used passwords.',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF71717A),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              // New Password field
              _buildPasswordField(
                label: 'NEW PASSWORD',
                controller: _newPasswordController,
                obscure: _obscureNew,
                onToggle: () => setState(() => _obscureNew = !_obscureNew),
              ),
              const SizedBox(height: 16),
              // Confirm Password field
              _buildPasswordField(
                label: 'CONFIRM PASSWORD',
                controller: _confirmPasswordController,
                obscure: _obscureConfirm,
                onToggle: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              const SizedBox(height: 24),
              // Validation indicators
              _buildValidationRow('At least 8 characters long', _hasMinLength),
              const SizedBox(height: 12),
              _buildValidationRow(
                'Includes a special character or number',
                _hasSpecialChar,
              ),
              const Spacer(),
              // Reset Password button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isResetting ? null : _resetPassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F2F6A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: _isResetting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Reset Password',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFFA1A1AA),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE4E4E7)),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            style: const TextStyle(color: Color(0xFF18181B), fontSize: 16),
            decoration: InputDecoration(
              prefixIcon: const Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFFA1A1AA),
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFFA1A1AA),
                  size: 20,
                ),
                onPressed: onToggle,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValidationRow(String text, bool isValid) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isValid ? Colors.green : const Color(0xFFE4E4E7),
          ),
          child: Icon(
            Icons.check,
            size: 14,
            color: isValid ? Colors.white : const Color(0xFFA1A1AA),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: isValid ? Colors.green : const Color(0xFF71717A),
          ),
        ),
      ],
    );
  }
}
