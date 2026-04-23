import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'api_client.dart';
import 'api_config.dart';

class UserApiService {
  final ApiClient _client = ApiClient();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<Map<String, dynamic>?> getProfile() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    if (!ApiConfig.useBackend) {
      final doc = await _db.collection('users').doc(user.uid).get();

      if (!doc.exists) {
        return {
          'uid': user.uid,
          'email': user.email ?? '',
          'firstName': '',
          'lastName': '',
          'phone': user.phoneNumber ?? '',
          'role': '',
        };
      }

      final data = doc.data() ?? {};

      return {
        'uid': user.uid,
        'email': data['email'] ?? user.email ?? '',
        'firstName': data['firstName'] ?? '',
        'lastName': data['lastName'] ?? '',
        'phone': data['phone'] ?? user.phoneNumber ?? '',
        'role': data['role'] ?? '',
        'image': data['image'] ?? '',
      };
    }

    try {
      final response = await _client.get('/users/profile');
      if (response['success'] == true) {
        return response['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> updateProfile({
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    if (!ApiConfig.useBackend) {
      await _db.collection('users').doc(user.uid).set({
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'email': user.email ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    }

    try {
      final response = await _client.put(
        '/users/profile',
        body: {'firstName': firstName, 'lastName': lastName, 'phone': phone},
      );
      return response['success'] == true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateLanguagePreference(String languageCode) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    if (!ApiConfig.useBackend) {
      await _db.collection('users').doc(user.uid).set({
        'language': languageCode,
      }, SetOptions(merge: true));
      return true;
    }

    try {
      final response = await _client.put(
        '/users/settings/language',
        body: {'language': languageCode},
      );
      return response['success'] == true;
    } catch (e) {
      return false;
    }
  }
}
