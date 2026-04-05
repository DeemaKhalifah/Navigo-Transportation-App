import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_status.dart';

/// When a trip finishes, return the driver to the pool (not the queue).
class TripCompletionService {
  TripCompletionService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Sets `drivers/{driverId}.status` to [DriverStatus.available].
  Future<void> releaseDriverAfterTrip({required String driverId}) async {
    await _db.collection('drivers').doc(driverId).update({
      'status': DriverStatus.available,
    });
  }
}
