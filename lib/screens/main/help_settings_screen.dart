import 'package:flutter/material.dart';

class HelpSettingsScreen extends StatelessWidget {
  const HelpSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          _buildHelpItem(context, Icons.report_problem_outlined, 'Report a Problem'),
          _buildHelpItem(context, Icons.help_outline_rounded, 'Help Center'),
          _buildHelpItem(context, Icons.lock_person_outlined, 'Privacy and Security Help'),
          _buildHelpItem(context, Icons.mail_outline_rounded, 'Support Requests'),
          const Divider(height: 32),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Contact Us', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                SizedBox(height: 8),
                Text('Available 24/7 for our premium members.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          _buildHelpItem(context, Icons.chat_bubble_outline_rounded, 'Live Chat Support'),
          _buildHelpItem(context, Icons.call_outlined, 'Request a Callback'),
        ],
      ),
    );
  }

  Widget _buildHelpItem(BuildContext context, IconData icon, String title) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () {},
    );
  }
}
