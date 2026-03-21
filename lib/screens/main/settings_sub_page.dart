import 'package:flutter/material.dart';

class SettingsSubPage extends StatelessWidget {
  final String title;
  final Widget? body;

  const SettingsSubPage({super.key, required this.title, this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: body ?? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction_rounded,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Coming Soon',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The $title page is under development.',
              style: TextStyle(
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
