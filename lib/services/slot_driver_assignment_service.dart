import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_status.dart';
import '../models/schedule_slot.dart';
import 'route_driver_queue_service.dart';
import 'schedule_slot_repository.dart';

/// Pops the first **available** driver from `route.driverQueueIds`, sets
/// [DriverStatus.assigned] (until the driver starts the live trip), and writes
/// `driverId` on the matching `scheduleSlots[]` entry. No `trips` doc.
enum SlotAssignmentOutcome {
  assigned,
  noDriversInQueue,
}

class SlotDriverAssignmentResult {
  SlotDriverAssignmentResult._({
    required this.outcome,
    this.driverId,
  });

  factory SlotDriverAssignmentResult.assigned({required String driverId}) {
    return SlotDriverAssignmentResult._(
      outcome: SlotAssignmentOutcome.assigned,
      driverId: driverId,
    );
  }

  factory SlotDriverAssignmentResult.noDrivers() {
    return SlotDriverAssignmentResult._(
      outcome: SlotAssignmentOutcome.noDriversInQueue,
    );
  }

  final SlotAssignmentOutcome outcome;
  final String? driverId;
}

class SlotDriverAssignmentService {
  SlotDriverAssignmentService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _routeRef(String routeId) =>
      _db.collection('route').doc(routeId);

  /// Only [DriverStatus.available] drivers are taken from the queue.
  static bool isEligibleForQueueAssignment(String? rawStatus) {
    return DriverStatus.normalize(rawStatus) == DriverStatus.available;
  }

  /// Finds the earliest upcoming slot (for [vehicleType]) with no `driverId`
  /// and assigns **one** driver from the queue (same rules as [tryAssignDriverForNewSlot]).
  Future<SlotDriverAssignmentResult> tryAssignFirstUnassignedSlot({
    required String routeId,
    required String vehicleType,
  }) async {
    final snap = await _routeRef(routeId).get();
    if (!snap.exists) return SlotDriverAssignmentResult.noDrivers();

    final maps = ScheduleSlotRepository.parseSlotList(snap.data()?['scheduleSlots']);
    final now = DateTime.now();
    ScheduleSlot? earliest;

    for (final m in maps) {
      final sid = m['slotId'] as String? ?? '';
      if (sid.isEmpty) continue;
      final driverId = (m['driverId'] as String? ?? '').trim();
      if (driverId.isNotEmpty) continue;

      final slot = ScheduleSlot.fromMap(sid, m);
      if (slot.vehicleType != vehicleType) continue;
      if (!slot.departureAt.isAfter(now.subtract(const Duration(minutes: 1)))) {
        continue;
      }
      if (earliest == null ||
          slot.departureAt.isBefore(earliest.departureAt)) {
        earliest = slot;
      }
    }

    if (earliest == null) return SlotDriverAssignmentResult.noDrivers();
    return tryAssignDriverForNewSlot(
      routeId: routeId,
      slotId: earliest.slotId,
    );
  }

  /// Call only for **new** slots (not edits).
  Future<SlotDriverAssignmentResult> tryAssignDriverForNewSlot({
    required String routeId,
    required String slotId,
  }) async {
    final driversCol = _db.collection('drivers');

    return _db.runTransaction((txn) async {
      final routeRef = _routeRef(routeId);
      final snap = await txn.get(routeRef);
      if (!snap.exists) {
        return SlotDriverAssignmentResult.noDrivers();
      }

      final data = snap.data()!;
      final q = RouteDriverQueueService.parseIds(data['driverQueueIds']);
      final list = ScheduleSlotRepository.parseSlotList(data['scheduleSlots']);
      final slotIdx = list.indexWhere((e) => e['slotId'] == slotId);
      if (slotIdx < 0) {
        return SlotDriverAssignmentResult.noDrivers();
      }

      var work = List<String>.from(q);
      String? assignedId;

      while (work.isNotEmpty) {
        final id = work.removeAt(0);
        final dRef = driversCol.doc(id);
        final dSnap = await txn.get(dRef);
        if (!dSnap.exists) continue;
        final d = dSnap.data()!;
        if (!isEligibleForQueueAssignment(d['status'] as String?)) continue;
        if ((d['routeId'] as String? ?? '') != routeId) continue;
        assignedId = id;
        break;
      }

      if (assignedId == null) {
        txn.update(routeRef, {'driverQueueIds': work});
        return SlotDriverAssignmentResult.noDrivers();
      }

      final slotMap = Map<String, dynamic>.from(list[slotIdx]);
      slotMap['driverId'] = assignedId;
      list[slotIdx] = slotMap;

      txn.update(routeRef, {
        'scheduleSlots': list,
        'driverQueueIds': work,
      });
      txn.update(driversCol.doc(assignedId), {'status': DriverStatus.assigned});

      return SlotDriverAssignmentResult.assigned(driverId: assignedId);
    });
  }
}
