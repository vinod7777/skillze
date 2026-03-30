import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/localization_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  double _fontScale = 1.0;
  bool _highContrast = false;
  bool _reduceMotion = false;
  String _languageCode = 'en';

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  double get fontScale => _fontScale;
  bool get highContrast => _highContrast;
  bool get reduceMotion => _reduceMotion;
  String get languageCode => _languageCode;

  ThemeProvider() {
    _loadSettingsFromFirestore();
  }

  Future<void> _loadSettingsFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data != null) {
        if (data.containsKey('themeMode')) {
          _themeMode = data['themeMode'] == 'dark' ? ThemeMode.dark : ThemeMode.light;
        }
        if (data.containsKey('fontScale')) {
          _fontScale = (data['fontScale'] as num).toDouble();
        }
        if (data.containsKey('highContrast')) {
          _highContrast = data['highContrast'] as bool;
        }
        if (data.containsKey('reduceMotion')) {
          _reduceMotion = data['reduceMotion'] as bool;
        }
        if (data.containsKey('languageCode')) {
          _languageCode = data['languageCode'] as String;
          LocalizationService().setLanguage(_languageCode);
        }
        notifyListeners();
      }
    }
  }

  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'themeMode': _themeMode == ThemeMode.dark ? 'dark' : 'light',
      }, SetOptions(merge: true));
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'themeMode': mode == ThemeMode.dark ? 'dark' : 'light',
      }, SetOptions(merge: true));
    }
  }

  Future<void> setFontScale(double scale) async {
    _fontScale = scale;
    notifyListeners();
    _saveToFirestore('fontScale', scale);
  }

  Future<void> setHighContrast(bool value) async {
    _highContrast = value;
    notifyListeners();
    _saveToFirestore('highContrast', value);
  }

  Future<void> setReduceMotion(bool value) async {
    _reduceMotion = value;
    notifyListeners();
    _saveToFirestore('reduceMotion', value);
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    LocalizationService().setLanguage(code);
    notifyListeners();
    _saveToFirestore('languageCode', code);
  }

  Future<void> _saveToFirestore(String key, dynamic value) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        key: value,
      }, SetOptions(merge: true));
    }
  }
}
