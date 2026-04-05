import 'package:cloud_firestore/cloud_firestore.dart';

/// FIFO queue: `route/{routeId}/driverQueue/{driverId}`
///
/// Order by `joinedAt` ascending when dequeuing (see [SlotDriverAssignmentService]).
class DriverQueueRepository {
  DriverQueueRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _queue(String routeId) {
    return _db.collection('route').doc(routeId).collection('driverQueue');
  }

  Future<void> joinQueue(String routeId, String driverId) async {
    await _queue(routeId).doc(driverId).set({
      'driverId': driverId,
      'joinedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> leaveQueue(String routeId, String driverId) async {
    await _queue(routeId).doc(driverId).delete();
  }
}
