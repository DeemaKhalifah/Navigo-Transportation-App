import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageController extends ChangeNotifier {
  static const String _storageKey = 'admin_language_code';

  Locale _locale = const Locale('en');

  Locale get locale => _locale;
  bool get isArabic => _locale.languageCode == 'ar';

  Future<void> loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    _locale = Locale(prefs.getString(_storageKey) ?? 'en');
    notifyListeners();
  }

  Future<void> setLanguage(String languageCode) async {
    if (_locale.languageCode == languageCode) return;

    _locale = Locale(languageCode);
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, languageCode);
  }

  Future<void> toggleLanguage(bool useArabic) async {
    await setLanguage(useArabic ? 'ar' : 'en');
  }
}
