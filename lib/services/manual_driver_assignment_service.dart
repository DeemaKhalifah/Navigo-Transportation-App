import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_status.dart';

/// Manually assign an [available] driver to a trip (replaces prior driver if any).
class ManualDriverAssignmentService {
  ManualDriverAssignmentService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<void> assignDriverToTrip({
    required String routeId,
    required String tripId,
    required String newDriverId,
  }) async {
    final trips = _db.collection('trips');
    final drivers = _db.collection('drivers');
    final queueRef =
        _db.collection('route').doc(routeId).collection('driverQueue').doc(newDriverId);

    await _db.runTransaction((txn) async {
      final tripRef = trips.doc(tripId);
      final tSnap = await txn.get(tripRef);
      if (!tSnap.exists) {
        throw StateError('Trip not found');
      }
      final tripData = tSnap.data()!;
      if (tripData['routeId'] != routeId) {
        throw StateError('Trip does not belong to this route');
      }

      final newRef = drivers.doc(newDriverId);
      final newSnap = await txn.get(newRef);
      if (!newSnap.exists) {
        throw StateError('Driver not found');
      }
      final newData = newSnap.data()!;
      if (newData['status'] != DriverStatus.available) {
        throw StateError('Driver is not available');
      }
      if ((newData['routeId'] as String? ?? '') != routeId) {
        throw StateError('Driver is not assigned to this route');
      }

      final oldId = tripData['driverId'] as String?;
      if (oldId != null && oldId.isNotEmpty && oldId != newDriverId) {
        txn.update(drivers.doc(oldId), {'status': DriverStatus.available});
      }

      txn.update(tripRef, {'driverId': newDriverId});
      txn.update(newRef, {'status': DriverStatus.onTrip});

      final qSnap = await txn.get(queueRef);
      if (qSnap.exists) {
        txn.delete(queueRef);
      }
    });
  }
}
