import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.primary,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Image.asset('assets/logo.png', errorBuilder: (_, __, ___) => Icon(Icons.rocket_launch, color: context.onPrimary, size: 50)),
                ),
                const SizedBox(height: 16),
                const Text('Feed Native', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text('Version 1.0.0 (Build 2024.1)', style: TextStyle(color: context.textLow)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _buildAboutItem(context, 'Data Policy'),
          _buildAboutItem(context, 'Terms of Use'),
          _buildAboutItem(context, 'Open Source Libraries'),
          _buildAboutItem(context, 'Privacy Policy'),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '© 2026 Feed Native Inc. Developed with ❤️ for the community.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textLow, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutItem(BuildContext context, String title) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Icon(Icons.open_in_new_rounded, size: 18, color: context.textLow),
      onTap: () {},
    );
  }
}
