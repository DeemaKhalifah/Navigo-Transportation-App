import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/driver_status.dart';
import 'route_driver_queue_service.dart';
import 'slot_driver_assignment_service.dart';

class DriverQueueRepository {
  DriverQueueRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance,
        _queueSvc = RouteDriverQueueService(
          firestore: firestore ?? FirebaseFirestore.instance,
        ),
        _slotAssign = SlotDriverAssignmentService(
          firestore: firestore ?? FirebaseFirestore.instance,
        );

  final FirebaseFirestore _db;
  final RouteDriverQueueService _queueSvc;
  final SlotDriverAssignmentService _slotAssign;

  DocumentReference<Map<String, dynamic>> _driverRef(String driverId) =>
      _db.collection('drivers').doc(driverId.trim());

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid.trim());

  Future<void> joinQueue(String routeId, String driverId) async {
    final cleanRouteId = routeId.trim();
    final cleanDriverId = driverId.trim();
    if (cleanRouteId.isEmpty || cleanDriverId.isEmpty) return;

    debugPrint('[DriverQueueRepo] joinQueue routeId=$cleanRouteId driverId=$cleanDriverId');

    await _queueSvc.syncQueueWithOnlineAvailableDrivers(cleanRouteId);
    await _queueSvc.appendDriver(cleanRouteId, cleanDriverId);

    final result = await _slotAssign.tryAssignOldestPendingTripForDriver(
      routeId: cleanRouteId,
      driverId: cleanDriverId,
    );

    if (result.outcome != SlotAssignmentOutcome.assigned) {
      await _slotAssign.autoAssignUpcomingUnassignedSlots(routeId: cleanRouteId);
    }
  }

  Future<void> onDriverStatusUpdated({
    required String routeId,
    required String driverId,
    required String status,
  }) async {
    final normalized = DriverStatus.normalize(status);

    if (normalized == DriverStatus.offline) {
      await leaveQueue(routeId, driverId);
      return;
    }

    if (normalized == DriverStatus.available) {
      await joinQueue(routeId, driverId);
    }
  }

  Future<void> goOnlineTransactional({
    required String routeId,
    required String driverId,
    required String userId,
  }) async {
    final cleanRouteId = routeId.trim();
    final cleanDriverId = driverId.trim();
    final cleanUserId = userId.trim();
    if (cleanRouteId.isEmpty || cleanDriverId.isEmpty || cleanUserId.isEmpty) return;

    debugPrint('[DriverQueueRepo] goOnline routeId=$cleanRouteId driverId=$cleanDriverId userId=$cleanUserId');

    await _db.runTransaction((txn) async {
      final dRef = _driverRef(cleanDriverId);
      final uRef = _userRef(cleanUserId);
      final dSnap = await txn.get(dRef);

      if (!dSnap.exists) {
        debugPrint('[DriverQueueRepo] goOnline failed reason=driverMissing driverId=$cleanDriverId');
        return;
      }

      txn.set(
        dRef,
        {
          'routeId': cleanRouteId,
          'status': DriverStatus.available,
          'isOnline': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      txn.set(
        uRef,
        {
          'isOnline': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    await joinQueue(cleanRouteId, cleanDriverId);
  }

  Future<void> goOfflineTransactional({
    required String routeId,
    required String driverId,
    required String userId,
  }) async {
    final cleanRouteId = routeId.trim();
    final cleanDriverId = driverId.trim();
    final cleanUserId = userId.trim();
    if (cleanDriverId.isEmpty || cleanUserId.isEmpty) return;

    debugPrint('[DriverQueueRepo] goOffline routeId=$cleanRouteId driverId=$cleanDriverId userId=$cleanUserId');

    await _db.runTransaction((txn) async {
      txn.set(
        _driverRef(cleanDriverId),
        {
          'status': DriverStatus.offline,
          'isOnline': false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      txn.set(
        _userRef(cleanUserId),
        {
          'isOnline': false,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    if (cleanRouteId.isNotEmpty) {
      await leaveQueue(cleanRouteId, cleanDriverId);
    }
  }

  Future<void> leaveQueue(String routeId, String driverId) async {
    await _queueSvc.removeDriver(routeId, driverId);
  }
}
