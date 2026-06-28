import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/driver_status.dart';
import 'local_storage_service.dart';

enum AppSessionDestination {
  welcome,
  phoneLogin,
  passengerHome,
  driverHome,
  driverApproval,
  routeManagerHome,
}

class AuthSessionService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  AuthSessionService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _db = firestore ?? FirebaseFirestore.instance;

  Future<DocumentSnapshot<Map<String, dynamic>>> _driverDocForUser(
    String uid,
  ) async {
    final directDoc = await _db.collection('drivers').doc(uid).get();
    if (directDoc.exists) return directDoc;

    final query = await _db
        .collection('drivers')
        .where('userId', isEqualTo: uid)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return query.docs.first;
    }

    return directDoc;
  }

  Future<AppSessionDestination> resolveStartupDestination() async {
    final user = _auth.currentUser;
    if (user == null) return AppSessionDestination.welcome;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final role = _normalizeRole(userDoc.data()?['role']?.toString());

    final isIosDemoUser =
        user.isAnonymous || (user.email ?? '').startsWith('ios-demo-');

    if (role.isEmpty && isIosDemoUser) {
      await _auth.signOut();
      return AppSessionDestination.phoneLogin;
    }

    if (role == 'passenger') {
      return AppSessionDestination.passengerHome;
    }

    if (role == 'driver') {
      final driverDoc = await _driverDocForUser(user.uid);
      final isApproved = driverDoc.data()?['isApproved'] == true;
      await LocalStorageService.saveDriverDisplayName(
        _displayNameFromMaps([userDoc.data(), driverDoc.data()]),
      );
      await LocalStorageService.saveDriverStatus(
        DriverStatus.normalize(driverDoc.data()?['status']?.toString()),
      );
      return isApproved
          ? AppSessionDestination.driverHome
          : AppSessionDestination.driverApproval;
    }

    if (role == 'route_manager') {
      return AppSessionDestination.routeManagerHome;
    }

    return AppSessionDestination.welcome;
  }

  String _displayNameFromMaps(List<Map<String, dynamic>?> maps) {
    for (final data in maps) {
      if (data == null) continue;
      final direct =
          (data['fullName'] ??
                  data['name'] ??
                  data['displayName'] ??
                  data['driverName'] ??
                  '')
              .toString()
              .trim();
      if (direct.isNotEmpty) return direct;

      final first = (data['firstName'] ?? '').toString().trim();
      final last = (data['lastName'] ?? '').toString().trim();
      final full = '$first $last'.trim();
      if (full.isNotEmpty) return full;
    }
    return '';
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
    return value;
  }
}
