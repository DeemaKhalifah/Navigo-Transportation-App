import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_status.dart';
import 'route_driver_queue_service.dart';

class TripCompletionService {
  TripCompletionService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance,
      _queue = RouteDriverQueueService(firestore: firestore);

  final FirebaseFirestore _db;
  final RouteDriverQueueService _queue;

  Future<void> markDriverLiveTripStarted({required String driverId}) async {
    final ref = _db.collection('drivers').doc(driverId);
    final snap = await ref.get();
    final st = DriverStatus.normalize(snap.data()?['status'] as String?);
    if (st == DriverStatus.assigned) {
      await ref.update({'status': DriverStatus.onTrip});
    }
  }

  Future<void> releaseDriverAfterTrip({required String driverId}) async {
    final dSnap = await _db.collection('drivers').doc(driverId).get();
    final routeId = dSnap.data()?['routeId'] as String?;

    if (routeId != null && routeId.isNotEmpty) {
      await _queue.completeTripAndRequeueEnd(
        routeId: routeId,
        driverId: driverId,
      );
    } else {
      await _db.collection('drivers').doc(driverId).update({
        'status': DriverStatus.available,
      });
    }
  }
}
