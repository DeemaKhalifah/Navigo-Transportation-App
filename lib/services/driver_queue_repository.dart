import 'package:cloud_firestore/cloud_firestore.dart';

import 'route_driver_queue_service.dart';
import 'slot_driver_assignment_service.dart';

class DriverQueueRepository {
  DriverQueueRepository({FirebaseFirestore? firestore})
      : _queueSvc = RouteDriverQueueService(firestore: firestore),
        _slotAssign = SlotDriverAssignmentService(firestore: firestore);

  final RouteDriverQueueService _queueSvc;
  final SlotDriverAssignmentService _slotAssign;

  // ======================================================
  // JOIN QUEUE
  // ======================================================
  Future<void> joinQueue(String routeId, String driverId) async {
    if (driverId.isEmpty) return;

    // ALWAYS sync first (FIX)
    await _queueSvc.syncQueueWithOnlineAvailableDrivers(routeId);

    await _queueSvc.appendDriver(routeId, driverId);

    await _slotAssign.tryAssignOldestPendingTripForDriver(
      routeId: routeId,
      driverId: driverId,
    );

    await _slotAssign.autoAssignUpcomingUnassignedSlots(
      routeId: routeId,
    );
  }

  // ======================================================
  // DRIVER STATUS UPDATE
  // ======================================================
  Future<void> onDriverStatusUpdated({
    required String routeId,
    required String driverId,
    required String status,
  }) async {
    final normalized = status.trim().toLowerCase();

    if (normalized == 'offline') {
      await leaveQueue(routeId, driverId);
      return;
    }

    if (normalized != 'available' && normalized != 'assigned') {
      return;
    }

    // ALWAYS SYNC FIRST (CRITICAL FIX)
    await _queueSvc.syncQueueWithOnlineAvailableDrivers(routeId);

    await _queueSvc.appendDriver(routeId, driverId);

    await _slotAssign.tryAssignOldestPendingTripForDriver(
      routeId: routeId,
      driverId: driverId,
    );

    await _slotAssign.autoAssignUpcomingUnassignedSlots(
      routeId: routeId,
    );
  }

  // ======================================================
  // LEAVE QUEUE
  // ======================================================
  Future<void> leaveQueue(String routeId, String driverId) async {
    await _queueSvc.removeDriver(routeId, driverId);
  }
}