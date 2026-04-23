import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/api_config.dart';
import '../services/auth_api_service.dart';

/// Handles authentication state, login/signup logic, and role-based navigation.
class AuthController extends ChangeNotifier {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final AuthApiService _apiService = AuthApiService();

  bool _isLoading = false;
  String? _error;
  String? _errorCode;

  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get errorCode => _errorCode;
  User? get currentUser => _auth.currentUser;

  AuthController({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String? value) {
    _error = value;
    notifyListeners();
  }

  void _setErrorCode(String? value) {
    _errorCode = value;
    notifyListeners();
  }

  void clearError() => _setError(null);

  /// Sign in with email and password (Route Manager flow).
  ///
  /// Returns the user's role (e.g. `route_manager`) when available.
  Future<String?> signInWithEmail(String email, String password) async {
    _setLoading(true);
    _setError(null);
    _setErrorCode(null);

    try {
      if (ApiConfig.useBackend) {
        await _auth.signInWithEmailAndPassword(email: email, password: password);
        final result = await _apiService.loginWithToken();
        _setLoading(false);
        return result?['role'] as String?;
      }

      final userCredential =
          await _auth.signInWithEmailAndPassword(email: email, password: password);
      final uid = userCredential.user!.uid;
      final userDoc = await _db.collection('users').doc(uid).get();
      _setLoading(false);

      if (userDoc.exists) {
        return userDoc.get('role') as String?;
      }
      return null;
    } on FirebaseAuthException catch (e) {
      _setErrorCode(e.code);
      _setError(e.message);
      _setLoading(false);
      return null;
    } catch (e) {
      _setErrorCode('unknown');
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  /// Send OTP to the given phone number.
  Future<void> sendOtp({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String error) onError,
  }) async {
    _setLoading(true);
    _setError(null);
    _setErrorCode(null);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {},
        verificationFailed: (FirebaseAuthException e) {
          _setLoading(false);
          _setErrorCode(e.code);
          _setError(e.message);
          onError(e.message ?? 'Verification failed');
        },
        codeSent: (String verificationId, int? resendToken) {
          _setLoading(false);
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _setLoading(false);
        },
      );
    } catch (e) {
      _setLoading(false);
      _setErrorCode('unknown');
      _setError(e.toString());
      onError("Failed to send OTP: $e");
    }
  }

  /// Verify OTP and return the signed-in user ID.
  Future<String?> verifyOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    _setLoading(true);
    _setError(null);
    _setErrorCode(null);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      _setLoading(false);
      return userCredential.user?.uid;
    } on FirebaseAuthException catch (e) {
      _setErrorCode(e.code);
      _setError(e.message);
      _setLoading(false);
      return null;
    } catch (e) {
      _setErrorCode('unknown');
      _setError(e.toString());
      _setLoading(false);
      return null;
    }
  }

  /// Logout.
  Future<void> logout() async {
    await _auth.signOut();
    notifyListeners();
  }
}