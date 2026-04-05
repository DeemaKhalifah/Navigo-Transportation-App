import 'package:cloud_firestore/cloud_firestore.dart';

import 'route_driver_queue_service.dart';

/// Driver queue is stored on `route/{routeId}` as `driverQueueIds` (ordered uids).
class DriverQueueRepository {
  DriverQueueRepository({FirebaseFirestore? firestore})
      : _queueSvc = RouteDriverQueueService(firestore: firestore);

  final RouteDriverQueueService _queueSvc;

  /// Appends [driverId] at the end if not already in the queue.
  Future<void> joinQueue(String routeId, String driverId) async {
    await _queueSvc.appendDriver(routeId, driverId);
  }

  /// Removes [driverId] from the ordered queue.
  Future<void> leaveQueue(String routeId, String driverId) async {
    await _queueSvc.removeDriver(routeId, driverId);
  }
}
