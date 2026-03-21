import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../services/localization_service.dart';

class LanguageSettingsScreen extends StatelessWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentLangCode = themeProvider.languageCode;

    final languages = [
      {'name': 'English', 'native': 'English', 'code': 'en'},
      {'name': 'Hindi', 'native': 'हिन्दी', 'code': 'hi'},
      {'name': 'Telugu', 'native': 'తెలుగు', 'code': 'te'},
      {'name': 'Spanish', 'native': 'Español', 'code': 'es'},
      {'name': 'French', 'native': 'Français', 'code': 'fr'},
      {'name': 'German', 'native': 'Deutsch', 'code': 'de'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('language')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: context.t('search_languages'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: languages.length,
              itemBuilder: (context, index) {
                final lang = languages[index];
                final isSelected = lang['code'] == currentLangCode;
                return ListTile(
                  title: Text(lang['name']!),
                  subtitle: Text(lang['native']!),
                  trailing: isSelected 
                    ? const Icon(Icons.check_circle, color: Color(0xFF0F2F6A))
                    : null,
                  onTap: () {
                    themeProvider.setLanguage(lang['code']!);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${context.t('language_changed')}${lang['name']}')),
                    );
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
