import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_status.dart';
import 'route_driver_queue_service.dart';
import 'schedule_slot_repository.dart';

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
      final newStatus = DriverStatus.normalize(newData['status'] as String?);
      if (newStatus != DriverStatus.available &&
          newStatus != DriverStatus.assigned) {
        throw StateError('Driver is not available');
      }
      if ((newData['routeId'] as String? ?? '') != routeId) {
        throw StateError('Driver is not assigned to this route');
      }
      final newVehicleType = (newData['vehicleType'] as String? ?? '').trim();

      final slotMap = Map<String, dynamic>.from(list[idx]);
      final slotStatus = (slotMap['status'] as String? ?? '').trim();
      if (slotStatus != 'scheduled') {
        throw StateError('Only scheduled trips can be assigned');
      }
      final slotVehicleType = (slotMap['vehicleType'] as String? ?? '').trim();
      if (slotVehicleType != newVehicleType) {
        throw StateError('Vehicle type mismatch');
      }
      final oldId = slotMap['driverId'] as String? ?? '';
      if (oldId.isNotEmpty && oldId != newDriverId) {
        txn.update(drivers.doc(oldId), {'status': DriverStatus.available});
      }

      slotMap['driverId'] = newDriverId;
      list[idx] = slotMap;

      final q = RouteDriverQueueService.parseIds(rData['driverQueueIds']);
      q.removeWhere((id) => id == newDriverId);
      q.add(newDriverId);

      txn.update(routeRef, {'scheduleSlots': list, 'driverQueueIds': q});
      txn.update(newRef, {'status': DriverStatus.assigned});
    });
  }
}
