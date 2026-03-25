import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'blocked_accounts_screen.dart';
import 'hidden_content_screen.dart';
import '../../theme/app_theme.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _isPrivateAccount = false;
  bool _showOnlineStatus = true;
  bool _allowTagging = true;
  bool _isGhostMode = false;
  String _mentionsSetting = 'Everyone';
  String _commentsSetting = 'Everyone';
  bool _isLoading = true;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadPrivacyData();
  }

  Future<void> _loadPrivacyData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data();
        setState(() {
          _isPrivateAccount = data?['isPrivateAccount'] ?? false;
          _showOnlineStatus = data?['showOnlineStatus'] ?? true;
          _allowTagging = data?['allowTagging'] ?? true;
          _isGhostMode = data?['isGhostMode'] ?? false;
          _mentionsSetting = data?['mentionsSetting'] ?? 'Everyone';
          _commentsSetting = data?['commentsSetting'] ?? 'Everyone';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updatePrivacy(String field, dynamic value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({field: value});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: const Text('Privacy & Security'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          _buildSectionHeader('Account Safety'),
          _buildSwitchTile(
            'Private Account',
            'Only approved people can see your posts.',
            _isPrivateAccount,
            (v) {
              setState(() => _isPrivateAccount = v);
              _updatePrivacy('isPrivateAccount', v);
            },
          ),
          _buildSwitchTile(
            'Ghost Mode',
            'Hide your location and active status from others.',
            _isGhostMode,
            (v) {
              setState(() => _isGhostMode = v);
              _updatePrivacy('isGhostMode', v);
            },
          ),
          _buildNavigationTile(
            Icons.block_rounded,
            'Blocked Accounts',
            'Manage accounts you have blocked.',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedAccountsScreen())),
          ),
          _buildNavigationTile(
            Icons.visibility_off_rounded,
            'Hidden Content',
            'Manage posts you have hidden or marked as not interested.',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HiddenContentScreen())),
          ),
          
          const Divider(height: 32),
          _buildSectionHeader('Security & Login'),
          _buildNavigationTile(
            Icons.vpn_key_outlined,
            'Password',
            'Change your account password.',
            _showChangePasswordDialog,
          ),

          const Divider(height: 32),
          _buildSectionHeader('Interactions'),
          _buildListTile(
            Icons.alternate_email_rounded,
            'Mentions',
            _mentionsSetting,
            () => _showSelectionDialog('Mentions', 'mentionsSetting', _mentionsSetting, ['Everyone', 'People you follow', 'No one']),
          ),
          _buildListTile(
            Icons.comment_outlined,
            'Comments',
            _commentsSetting,
            () => _showSelectionDialog('Comments', 'commentsSetting', _commentsSetting, ['Everyone', 'People you follow', 'No one']),
          ),
          _buildSwitchTile(
            'Activity Status',
            'Allow accounts to see when you were last active.',
            _showOnlineStatus,
            (v) {
              setState(() => _showOnlineStatus = v);
              _updatePrivacy('showOnlineStatus', v);
            },
          ),
          _buildSwitchTile(
             'Allow Tagging',
             'Allow people to tag you in their posts.',
             _allowTagging,
             (v) {
               setState(() => _allowTagging = v);
               _updatePrivacy('allowTagging', v);
             }
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: context.textLow,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return SwitchListTile.adaptive(
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: context.textHigh)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: context.textMed)),
      value: value,
      onChanged: onChanged,
      activeColor: context.primary,
    );
  }

  Widget _buildNavigationTile(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: context.primary),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: context.textHigh)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: context.textMed)),
      trailing: Icon(Icons.chevron_right_rounded, size: 20, color: context.textLow),
      onTap: onTap,
    );
  }

  Widget _buildListTile(IconData icon, String title, String trailing, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: context.textMed),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: context.textHigh)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(trailing, style: TextStyle(color: context.textLow)),
          Icon(Icons.chevron_right_rounded, color: context.textLow),
        ],
      ),
      onTap: onTap,
    );
  }

  Future<void> _showSelectionDialog(String title, String field, String currentValue, List<String> options) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textHigh)),
              ),
              ...options.map((option) => ListTile(
                    title: Text(option, style: TextStyle(color: context.textHigh)),
                    trailing: option == currentValue ? Icon(Icons.check_circle_rounded, color: context.primary) : null,
                    onTap: () => Navigator.pop(context, option),
                  )),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );

    if (result != null && result != currentValue && mounted) {
      setState(() {
        if (field == 'mentionsSetting') _mentionsSetting = result;
        if (field == 'commentsSetting') _commentsSetting = result;
      });
      _updatePrivacy(field, result);
    }
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            top: 24,
            left: 24,
            right: 24,
          ),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Change Password',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: context.textHigh),
              ),
              const SizedBox(height: 8),
              Text('Security is important. Verify your current identity first.', 
                style: TextStyle(color: context.textLow, fontSize: 13)),
              const SizedBox(height: 24),
              _buildPasswordField('Current Password', currentPasswordController),
              const SizedBox(height: 16),
              _buildPasswordField('New Password', newPasswordController),
              const SizedBox(height: 16),
              _buildPasswordField('Confirm New Password', confirmPasswordController),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : () async {
                    final currentPw = currentPasswordController.text.trim();
                    final newPw = newPasswordController.text.trim();
                    final confirmPw = confirmPasswordController.text.trim();

                    if (currentPw.isEmpty || newPw.isEmpty || confirmPw.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields')));
                      return;
                    }
                    if (newPw != confirmPw) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
                       return;
                    }
                    if (newPw.length < 6) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password too short')));
                       return;
                    }

                    setModalState(() => isLoading = true);
                    try {
                      final user = _auth.currentUser;
                      if (user != null && user.email != null) {
                        AuthCredential credential = EmailAuthProvider.credential(
                          email: user.email!,
                          password: currentPw,
                        );
                        await user.reauthenticateWithCredential(credential);
                        await user.updatePassword(newPw);
                        
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated successfully')));
                        }
                      }
                    } on FirebaseAuthException catch (e) {
                      String message = 'An error occurred';
                      if (e.code == 'wrong-password') {
                        message = 'The current password you entered is incorrect.';
                      } else if (e.code == 'requires-recent-login') {
                        message = 'Security timeout. Please log out and log in again.';
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.redAccent));
                      }
                    } catch (e) {
                       if (context.mounted) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                       }
                    } finally {
                      if (context.mounted) setModalState(() => isLoading = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: isLoading 
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: context.onPrimary, strokeWidth: 2))
                    : Text('Update Password', style: TextStyle(color: context.onPrimary, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      obscureText: true,
      style: TextStyle(color: context.textHigh),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.textMed),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: context.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: context.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: context.primary, width: 2)),
        filled: true,
        fillColor: context.surfaceLightColor,
      ),
    );
  }
}
