import 'package:flutter/material.dart';

class ProfanityFilterService {
  // A comprehensive list of unparliamentary/dirty/rude words to filter.
  // We separate severe words (matched even inside other words) from regular words (matched whole word).
  static final List<String> _severeWords = [
    'fuck', 'fucker', 'fucking', 'fuckface', 'motherfucker', 'cocksucker',
    'shit', 'shitty', 'bullshit', 'horseshit', 'dipshit',
    'bitch', 'bitches', 'sonofabitch',
    'cunt', 'twat', 'pussy', 'clit',
    'whore', 'slut', 'hooker', 'prostitute',
    'faggot', 'nigger', 'nigga', 'coon', 'spic', 'kike', 'chink', 'fag',
    'dickhead', 'asshole', 'bastard'
  ];

  static final List<String> _regularWords = [
    'ass', 'dumbass', 'jackass', 'wiseass', 'smartass',
    'bastards', 
    'dick', 'dildo', 'prick', 'knob',
    'vagina', 'ho',
    'queer', 'homo', 'dyke',
    'stupid', 'idiot', 'moron', 'retard', 'scumbag', 'jerk', 'loser',
    'damn', 'hell', 'piss', 'bloody', 'bugger', 'crap', 'garbage', 'trash',
    'idiotic', 'retarded', 'moronic'
  ];

  /// Check if the text contains profanity.
  static bool hasProfanity(String text) {
    if (text.isEmpty) return false;
    
    // Clean string for standard comparison
    final cleanedText = text.toLowerCase();
    
    // Clean string aggressively by removing spaces and punctuation to catch "f.u.c.k" or "fuckyou"
    String strippedText = cleanedText.replaceAll(RegExp(r'[^a-z0-9]'), '');
    
    // Map common number substitutions to letters for better detection (l33t speak)
    String normalizedText = strippedText
      .replaceAll('0', 'o')
      .replaceAll('1', 'i')
      .replaceAll('3', 'e')
      .replaceAll('4', 'a')
      .replaceAll('5', 's')
      .replaceAll('7', 't')
      .replaceAll('8', 'b');

    // 1. Check severe words against normalized text
    for (final word in _severeWords) {
      if (normalizedText.contains(word)) {
        return true;
      }
    }

    // 2. Check regular words with boundary preservation
    for (final word in _regularWords) {
      final RegExp regex = RegExp('\\b${RegExp.escape(word)}\\b', caseSensitive: false);
      if (regex.hasMatch(cleanedText)) {
        return true;
      }
    }
    
    return false;
  }

  /// Censor a string, replacing bad words with asterisks.
  static String censor(String text) {
    if (text.isEmpty) return text;
    String censoredText = text;
    
    for (final word in [..._severeWords, ..._regularWords]) {
      final RegExp regex = RegExp('\\b${RegExp.escape(word)}\\b', caseSensitive: false);
      censoredText = censoredText.replaceAllMapped(regex, (match) {
        return List.filled(match.group(0)!.length, '*').join();
      });
    }
    
    return censoredText;
  }

  /// Show a warning dialog if profanity is detected.
  static bool validateAndShowWarning(BuildContext context, String text) {
    if (hasProfanity(text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unparliamentary language is not allowed in this app.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return false;
    }
    return true;
  }
}
