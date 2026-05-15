import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageController extends ChangeNotifier {
  static const String _storageKey = 'app_language_code';

  Locale _locale = const Locale('en');
  StreamSubscription<User?>? _authSub;

  Locale get locale => _locale;
  bool get isArabic => _locale.languageCode == 'ar';

  Future<void> loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_storageKey) ?? 'en';
    _locale = Locale(code);
    notifyListeners();
  }

  void startAuthLanguageSync() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        unawaited(_syncUserLanguagePreference(_locale.languageCode));
      }
    });

    unawaited(_syncUserLanguagePreference(_locale.languageCode));
  }

  Future<void> setLanguage(String languageCode) async {
    if (_locale.languageCode == languageCode) return;
    _locale = Locale(languageCode);

    // Notify immediately before the async preference write, so MaterialApp,
    // Directionality, and the current screen rebuild on the first toggle tap.
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, languageCode);
    await _syncUserLanguagePreference(languageCode);
  }

  Future<void> toggleLanguage(bool useArabic) async {
    await setLanguage(useArabic ? 'ar' : 'en');
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _syncUserLanguagePreference(String languageCode) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'language': languageCode,
      }, SetOptions(merge: true));
    } catch (_) {
      // Language should still change locally even if the remote preference write
      // fails because of connectivity or permissions.
    }
  }
}
