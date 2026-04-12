import 'package:cloud_firestore/cloud_firestore.dart';

import 'route_driver_queue_service.dart';

class DriverQueueRepository {
  DriverQueueRepository({FirebaseFirestore? firestore})
    : _queueSvc = RouteDriverQueueService(firestore: firestore);

  final RouteDriverQueueService _queueSvc;

  Future<void> joinQueue(String routeId, String driverId) async {
    await _queueSvc.appendDriver(routeId, driverId);
  }

  Future<void> leaveQueue(String routeId, String driverId) async {
    await _queueSvc.removeDriver(routeId, driverId);
  }
}
