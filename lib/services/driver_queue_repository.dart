import 'package:cloud_firestore/cloud_firestore.dart';

import 'route_driver_queue_service.dart';
import 'slot_driver_assignment_service.dart';

class DriverQueueRepository {
  DriverQueueRepository({FirebaseFirestore? firestore})
    : _queueSvc = RouteDriverQueueService(firestore: firestore),
      _slotAssign = SlotDriverAssignmentService(firestore: firestore);

  final RouteDriverQueueService _queueSvc;
  final SlotDriverAssignmentService _slotAssign;

  Future<void> joinQueue(String routeId, String driverId) async {
    await _queueSvc.appendDriver(routeId, driverId);
    // As soon as a driver becomes eligible (goes online), automatically assign
    // them to any already-existing upcoming unassigned trips.
    await _slotAssign.autoAssignUpcomingUnassignedSlots(routeId: routeId);
  }

  Future<void> leaveQueue(String routeId, String driverId) async {
    await _queueSvc.removeDriver(routeId, driverId);
  }
}
