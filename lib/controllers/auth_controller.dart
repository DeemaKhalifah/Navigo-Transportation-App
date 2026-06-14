import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthController extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool isLoading = false;
  String? error;
  String? errorCode;

  User? get currentUser => _auth.currentUser;

  void _update({
    bool? loading,
    String? newError,
    String? newErrorCode,
    bool clearError = false,
  }) {
    if (loading != null) isLoading = loading;

    if (clearError) {
      error = null;
      errorCode = null;
    } else {
      if (newError != null) error = newError;
      if (newErrorCode != null) errorCode = newErrorCode;
    }

    notifyListeners();
  }

  String _normalizeRole(String? role) {
    final value = (role ?? '').trim().toLowerCase();

    if (value == 'route_manager' ||
        value == 'route_manger' ||
        value == 'route manager' ||
        value == 'routemanager' ||
        value == 'manager') {
      return 'route_manager';
    }

    if (value == 'driver') return 'driver';
    if (value == 'passenger') return 'passenger';

    return value;
  }

  Future<String?> signInWithEmail(String email, String password) async {
    _update(loading: true, clearError: true);

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      final uid = credential.user?.uid;

      if (uid == null) {
        _update(
          loading: false,
          newError: 'Login failed. No user found.',
          newErrorCode: 'no-user',
        );
        return null;
      }

      final userDoc = await _db.collection('users').doc(uid).get();

      if (!userDoc.exists) {
        await _auth.signOut();

        _update(
          loading: false,
          newError: 'User profile was not found in Firestore.',
          newErrorCode: 'user-doc-not-found',
        );

        return null;
      }

      final data = userDoc.data() ?? {};
      final role = _normalizeRole(data['role']?.toString());

      if (role != 'route_manager') {
        await _auth.signOut();

        _update(
          loading: false,
          newError: 'You are not authorized as a Route Manager.',
          newErrorCode: 'not-route-manager',
        );

        return null;
      }

      _update(loading: false);
      return role;
    } on FirebaseAuthException catch (e) {
      String message = 'Login failed.';

      if (e.code == 'user-not-found') {
        message = 'No user found for this email.';
      } else if (e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'INVALID_LOGIN_CREDENTIALS') {
        message = 'Incorrect email or password.';
      } else if (e.message != null) {
        message = e.message!;
      }

      _update(loading: false, newError: message, newErrorCode: e.code);

      return null;
    } catch (e) {
      _update(
        loading: false,
        newError: 'Login failed: $e',
        newErrorCode: 'unknown',
      );

      return null;
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    notifyListeners();
  }
}
