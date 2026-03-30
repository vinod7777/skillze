import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'saved_posts_screen.dart';
import 'notifications_screen.dart';
import 'privacy_settings_screen.dart';
import 'edit_personal_details_screen.dart';
import 'language_settings_screen.dart';
import 'accessibility_settings_screen.dart';
import 'help_settings_screen.dart';
import 'about_settings_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar.dart';
import '../../theme/theme_provider.dart';
import '../../services/localization_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _userData = doc.data();
          _isLoading = false;
        });
        return;
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Log Out',
          style: TextStyle(
            color: context.textHigh,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Are you sure you want to log out of your account?',
          style: TextStyle(color: context.textMed),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.primary,
              foregroundColor: context.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDark;

    final languages = [
      {'name': 'English', 'code': 'en'},
      {'name': 'Hindi', 'code': 'hi'},
      {'name': 'Telugu', 'code': 'te'},
      {'name': 'Spanish', 'code': 'es'},
      {'name': 'French', 'code': 'fr'},
      {'name': 'German', 'code': 'de'},
    ];

    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: context.primary),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('settings')),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildUserHeader(),

            _buildSectionHeader(context.t('how_you_use')),
            _buildSettingsItem(
              icon: Icons.bookmark_outline_rounded,
              title: context.t('saved'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SavedPostsScreen())),
            ),
            _buildSettingsItem(
              icon: Icons.notifications_none_rounded,
              title: context.t('notifications'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
            ),

            _buildSectionHeader('Privacy & Security'),
            _buildSettingsItem(
              icon: Icons.lock_outline_rounded,
              title: 'Privacy & Security',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacySettingsScreen())),
            ),

            _buildSectionHeader(context.t('app_and_media')),
            _buildSettingsItem(
              icon: Icons.palette_outlined,
              title: context.t('appearance'),
              trailing: Text(
                isDark ? 'Dark' : 'Light',
                style: TextStyle(color: Colors.grey.shade500),
              ),
              onTap: () => _showThemePicker(context),
            ),
            _buildSettingsItem(
              icon: Icons.accessibility_new_rounded,
              title: context.t('accessibility'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccessibilitySettingsScreen())),
            ),
            _buildSettingsItem(
              icon: Icons.language_rounded,
              title: context.t('language'),
              trailing: Text(languages.firstWhere((l) => l['code'] == themeProvider.languageCode)['name']!, style: TextStyle(color: Colors.grey.shade500)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguageSettingsScreen())),
            ),

            _buildSectionHeader(context.t('more_info')),
            _buildSettingsItem(
              icon: Icons.help_outline_rounded,
              title: context.t('help'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSettingsScreen())),
            ),
            _buildSettingsItem(
              icon: Icons.info_outline_rounded,
              title: context.t('about'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutSettingsScreen())),
            ),

            const SizedBox(height: 32),
            Center(
              child: TextButton(
                onPressed: () => _logout(context),
                child: Text(
                  context.t('logout'),
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildUserHeader() {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditPersonalDetailsScreen())),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.border),
          ),
          child: Row(
            children: [
              UserAvatar(
                imageUrl: _userData?['profileImageUrl'],
                name: _userData?['name'] ?? 'User',
                radius: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userData?['name'] ?? 'User',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textHigh),
                    ),
                    Text(
                      _userData?['email'] ?? '',
                      style: TextStyle(fontSize: 14, color: context.textLow),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.textLow),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: context.textLow,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: context.primary),
      title: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: context.textHigh)),
      trailing: trailing ?? Icon(Icons.chevron_right_rounded, color: context.textLow, size: 20),
      onTap: onTap,
    );
  }

  void _showThemePicker(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Choose Appearance',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textHigh),
            ),
            const SizedBox(height: 16),
            RadioListTile<ThemeMode>(
              title: Text('Light', style: TextStyle(color: context.textHigh)),
              value: ThemeMode.light,
              groupValue: themeProvider.themeMode,
              activeColor: context.primary,
              onChanged: (mode) {
                if (mode != null) {
                  Navigator.pop(context);
                  themeProvider.setTheme(mode);
                }
              },
            ),
            RadioListTile<ThemeMode>(
              title: Text('Dark', style: TextStyle(color: context.textHigh)),
              value: ThemeMode.dark,
              groupValue: themeProvider.themeMode,
              activeColor: context.primary,
              onChanged: (mode) {
                if (mode != null) {
                  Navigator.pop(context);
                  themeProvider.setTheme(mode);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
