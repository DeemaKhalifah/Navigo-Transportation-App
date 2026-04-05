import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_status.dart';
import 'route_driver_queue_service.dart';
import 'schedule_slot_repository.dart';

/// Manually assign an [available] driver to a schedule slot (replaces prior driver if any).
class ManualDriverAssignmentService {
  ManualDriverAssignmentService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<void> assignDriverToSlot({
    required String routeId,
    required String slotId,
    required String newDriverId,
  }) async {
    final drivers = _db.collection('drivers');
    final routeRef = _db.collection('route').doc(routeId);

    await _db.runTransaction((txn) async {
      final rSnap = await txn.get(routeRef);
      if (!rSnap.exists) {
        throw StateError('Route not found');
      }
      final rData = rSnap.data()!;

      final list = ScheduleSlotRepository.parseSlotList(rData['scheduleSlots']);
      final idx = list.indexWhere((e) => e['slotId'] == slotId);
      if (idx < 0) {
        throw StateError('Slot not found');
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

      final slotMap = Map<String, dynamic>.from(list[idx]);
      final oldId = slotMap['driverId'] as String? ?? '';
      if (oldId.isNotEmpty && oldId != newDriverId) {
        txn.update(drivers.doc(oldId), {'status': DriverStatus.available});
      }

      slotMap['driverId'] = newDriverId;
      list[idx] = slotMap;

      final q = RouteDriverQueueService.parseIds(rData['driverQueueIds']);
      q.removeWhere((id) => id == newDriverId);

      txn.update(routeRef, {
        'scheduleSlots': list,
        'driverQueueIds': q,
      });
      txn.update(newRef, {'status': DriverStatus.assigned});
    });
  }
}
