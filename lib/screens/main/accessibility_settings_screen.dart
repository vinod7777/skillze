import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';

class AccessibilitySettingsScreen extends StatefulWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  State<AccessibilitySettingsScreen> createState() => _AccessibilitySettingsScreenState();
}

class _AccessibilitySettingsScreenState extends State<AccessibilitySettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accessibility'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          _buildSectionHeader('Visual'),
          _buildAccessibilityTile(
            'Large Text',
            'Increase font size for better readability',
            themeProvider.fontScale > 1.0,
            (v) => themeProvider.setFontScale(v ? 1.2 : 1.0),
          ),
          _buildAccessibilityTile(
            'High Contrast',
            'Make colors more distinct',
            themeProvider.highContrast,
            (v) => themeProvider.setHighContrast(v),
          ),
          _buildSectionHeader('Motor'),
          _buildAccessibilityTile(
            'Reduce Motion',
            'Simplify animations and transitions',
            themeProvider.reduceMotion,
            (v) => themeProvider.setReduceMotion(v),
          ),
          _buildSectionHeader('Assistive'),
          _buildAccessibilityTile(
            'Screen Reader Support',
            'Optimize UI for TalkBack/VoiceOver',
            false, // Screen reader is system level, but we can add semantic hints
            (v) {},
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
      ),
    );
  }

  Widget _buildAccessibilityTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return SwitchListTile.adaptive(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: onChanged,
      activeColor: const Color(0xFF0F2F6A),
    );
  }
}
