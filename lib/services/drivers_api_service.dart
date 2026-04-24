import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/driver_status.dart';
import 'api_client.dart';
import 'api_config.dart';

class DriversApiService {
  final ApiClient _api = ApiClient();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<Map<String, dynamic>> getDriverProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No logged in driver');
    }

    if (!ApiConfig.useBackend) {
      final doc = await _db.collection('drivers').doc(user.uid).get();

      if (!doc.exists) {
        return {
          'userId': user.uid,
          'firstName': '',
          'lastName': '',
          'phone': user.phoneNumber ?? '',
          'email': user.email ?? '',
          'image': null,
          'status': DriverStatus.offline,
          'routeId': '',
          'isApproved': false,
        };
      }

      final data = doc.data() ?? {};

      return {
        'userId': user.uid,
        'firstName': data['firstName'] ?? '',
        'lastName': data['lastName'] ?? '',
        'phone': data['phone'] ?? user.phoneNumber ?? '',
        'email': data['email'] ?? user.email ?? '',
        'image': data['image'],
        'status': DriverStatus.normalize(data['status']?.toString()),
        'routeId': data['routeId'] ?? '',
        'isApproved': data['isApproved'] == true,
      };
    }

    final response = await _api.get('/drivers/profile');
    return response['data'] as Map<String, dynamic>;
  }

  Future<void> updateDriverProfile({
    required String firstName,
    required String lastName,
    required String phone,
    String? imageUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No logged in driver');
    }

    if (!ApiConfig.useBackend) {
      await _db.collection('drivers').doc(user.uid).set({
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'image': ?imageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _db.collection('users').doc(user.uid).set({
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'role': 'driver',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return;
    }

    await _api.put(
      '/drivers/profile',
      body: {
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'image': ?imageUrl,
      },
    );
  }

  Future<Map<String, dynamic>> updateStatus(String status) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('No logged in driver');
    }

    final normalized = DriverStatus.normalize(status);

    if (!ApiConfig.useBackend) {
      await _db.collection('drivers').doc(user.uid).set({
        'status': normalized,
        'isOnline': normalized == DriverStatus.available,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return {'status': normalized};
    }

    final response = await _api.put(
      '/drivers/status',
      body: {'status': normalized},
    );

    return response['data'] as Map<String, dynamic>;
  }

  Future<void> updateLocation(double latitude, double longitude) async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (!ApiConfig.useBackend) {
      await _db.collection('drivers').doc(user.uid).set({
        'latitude': latitude,
        'longitude': longitude,
        'location': {'lat': latitude, 'lng': longitude},
        'lastLocationUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return;
    }

    await _api.put(
      '/drivers/location',
      body: {'latitude': latitude, 'longitude': longitude},
    );
  }

  Future<Map<String, dynamic>> completeTrip(
    String routeId,
    String slotId,
  ) async {
    final response = await _api.post(
      '/drivers/trip/complete',
      body: {'routeId': routeId, 'slotId': slotId},
    );

    return response['data'] as Map<String, dynamic>;
  }

  void dispose() => _api.dispose();
}
