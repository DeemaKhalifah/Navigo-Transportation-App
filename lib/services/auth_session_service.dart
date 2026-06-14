import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  AuthSessionService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _db = firestore ?? FirebaseFirestore.instance;

  Future<AppSessionDestination> resolveStartupDestination() async {
    final user = _auth.currentUser;
    if (user == null) return AppSessionDestination.welcome;

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final role = _normalizeRole(userDoc.data()?['role']?.toString());

    if (role == 'passenger') {
      return AppSessionDestination.passengerHome;
    }

    if (role == 'driver') {
      final driverDoc = await _db.collection('drivers').doc(user.uid).get();
      final isApproved = driverDoc.data()?['isApproved'] == true;
      return isApproved
          ? AppSessionDestination.driverHome
          : AppSessionDestination.driverApproval;
    }

    if (role == 'route_manager') {
      return AppSessionDestination.routeManagerHome;
    }

    return AppSessionDestination.welcome;
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
