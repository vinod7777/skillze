import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/profanity_filter_service.dart';
import '../../utils/profanity_helper.dart';
import '../../theme/app_theme.dart';

class EditPersonalDetailsScreen extends StatefulWidget {
  const EditPersonalDetailsScreen({super.key});

  @override
  State<EditPersonalDetailsScreen> createState() => _EditPersonalDetailsScreenState();
}

class _EditPersonalDetailsScreenState extends State<EditPersonalDetailsScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user != null) {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _nameController.text = data['name'] ?? '';
          _emailController.text = user.email ?? '';
          _bioController.text = data['bio'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveChanges() async {
    final user = _auth.currentUser;
    if (user != null) {
      if (ProfanityFilterService.hasProfanity(_nameController.text) ||
          ProfanityFilterService.hasProfanity(_bioController.text)) {
        showProfanityWarning(context);
        return;
      }

      setState(() => _isSaving = true);
      try {
        await _firestore.collection('users').doc(user.uid).update({
          'name': _nameController.text.trim(),
          'bio': _bioController.text.trim(),
          'phone': _phoneController.text.trim(),
        });

        if (_emailController.text.trim() != user.email) {
          await user.verifyBeforeUpdateEmail(_emailController.text.trim());
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated successfully')));
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.bg,
        body: Center(child: CircularProgressIndicator(color: context.primary)),
      );
    }

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        title: Text('Edit Profile', style: TextStyle(color: context.textHigh)),
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: context.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveChanges,
            child: _isSaving 
              ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.primary))
              : Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.primary)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildEditField('Name', _nameController, Icons.person_outline_rounded),
            const SizedBox(height: 20),
            _buildEditField('Email', _emailController, Icons.email_outlined), 
             Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                'Note: Fast login might be required after email change.',
                style: TextStyle(fontSize: 10, color: context.textLow),
              ),
            ),
            const SizedBox(height: 20),
            _buildEditField('Phone', _phoneController, Icons.phone_android_rounded),
            const SizedBox(height: 20),
            _buildEditField('Bio', _bioController, Icons.info_outline_rounded, maxLines: 3),
            const SizedBox(height: 40),
            Center(
              child: Text(
                'Personal Information Settings',
                style: TextStyle(color: context.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditField(String label, TextEditingController controller, IconData icon, {bool enabled = true, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textMed)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          style: TextStyle(color: context.textHigh),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 20, color: context.textLow),
            border: UnderlineInputBorder(borderSide: BorderSide(color: context.border)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.border)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.primary)),
          ),
        ),
      ],
    );
  }
}
