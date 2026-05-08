import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_status.dart';
import '../models/schedule_slot.dart';
import 'route_driver_queue_service.dart';
import 'schedule_slot_repository.dart';

enum SlotAssignmentOutcome { assigned, noDriversInQueue }

class SlotDriverAssignmentResult {
  SlotDriverAssignmentResult._({required this.outcome, this.driverId});

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
  final RouteDriverQueueService _queueSvc = RouteDriverQueueService();

  DocumentReference<Map<String, dynamic>> _routeRef(String routeId) =>
      _db.collection('route').doc(routeId);

  static bool isEligibleForQueueAssignment(String? rawStatus) {
    return DriverStatus.normalize(rawStatus) == DriverStatus.available;
  }

  static bool isEligibleDriverDoc(Map<String, dynamic> d) {
    final st = DriverStatus.normalize(d['status'] as String?);
    final isOnline = d['isOnline'] == true;
    return isOnline && st == DriverStatus.available;
  }

  Future<SlotDriverAssignmentResult> tryAssignFirstUnassignedSlot({
    required String routeId,
    required String vehicleType,
  }) async {
    // Keep queue up-to-date with online+available drivers.
    await _queueSvc.syncQueueWithOnlineAvailableDrivers(routeId);

    final snap = await _routeRef(routeId).get();
    if (!snap.exists) return SlotDriverAssignmentResult.noDrivers();

    final maps = ScheduleSlotRepository.parseSlotList(
      snap.data()?['scheduleSlots'],
    );
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
      if (earliest == null || slot.departureAt.isBefore(earliest.departureAt)) {
        earliest = slot;
      }
    }

    if (earliest == null) return SlotDriverAssignmentResult.noDrivers();
    return tryAssignDriverForNewSlot(routeId: routeId, slotId: earliest.slotId);
  }

  /// Automatically assigns drivers from the queue to already-existing upcoming
  /// unassigned trips (scheduleSlots) in chronological order.
  ///
  /// This is invoked when new drivers become eligible (e.g. they go online).
  /// Rotation to queue end happens when a driver starts a trip.
  Future<int> autoAssignUpcomingUnassignedSlots({
    required String routeId,
    int maxAssignments = 10,
  }) async {
    if (maxAssignments < 1) return 0;

    await _queueSvc.syncQueueWithOnlineAvailableDrivers(routeId);

    final driversCol = _db.collection('drivers');

    return _db.runTransaction((txn) async {
      final routeRef = _routeRef(routeId);
      final snap = await txn.get(routeRef);
      if (!snap.exists) return 0;

      final data = snap.data() ?? <String, dynamic>{};
      final q = RouteDriverQueueService.parseIds(data['driverQueueIds']);
      final list = ScheduleSlotRepository.parseSlotList(data['scheduleSlots']);

      if (q.isEmpty || list.isEmpty) return 0;

      final now = DateTime.now();
      final usedDriverIds = <String>{};
      final driverCache = <String, Map<String, dynamic>?>{};

      Future<Map<String, dynamic>?> loadDriver(String id) async {
        if (driverCache.containsKey(id)) return driverCache[id];
        final dSnap = await txn.get(driversCol.doc(id));
        driverCache[id] = dSnap.exists ? dSnap.data() : null;
        return driverCache[id];
      }

      bool isSlotUpcomingUnassigned(Map<String, dynamic> m) {
        final driverId = (m['driverId'] as String? ?? '').trim();
        if (driverId.isNotEmpty) return false;
        final sid = (m['slotId'] as String? ?? '').trim();
        if (sid.isEmpty) return false;
        final slot = ScheduleSlot.fromMap(sid, m);
        return slot.departureAt.isAfter(now.subtract(const Duration(minutes: 1)));
      }

      int assignedCount = 0;
      var queue = List<String>.from(q);

      // Iterate in chronological order (ScheduleSlotRepository preserves list
      // order; we sort indices by departure time to be safe).
      final candidates = <({int idx, DateTime dep})>[];
      for (var i = 0; i < list.length; i++) {
        final m = list[i];
        if (!isSlotUpcomingUnassigned(m)) continue;
        final sid = (m['slotId'] as String? ?? '').trim();
        final slot = ScheduleSlot.fromMap(sid, m);
        candidates.add((idx: i, dep: slot.departureAt));
      }
      candidates.sort((a, b) => a.dep.compareTo(b.dep));

      for (final c in candidates) {
        if (assignedCount >= maxAssignments) break;

        String? assignedId;
        for (final id in queue) {
          if (usedDriverIds.contains(id)) continue;
          final d = await loadDriver(id);
          if (d == null) continue;
          if ((d['routeId'] as String? ?? '') != routeId) continue;
          if (!isEligibleDriverDoc(d)) continue;
          assignedId = id;
          break;
        }

        if (assignedId == null) break;

        final slotMap = Map<String, dynamic>.from(list[c.idx]);
        slotMap['driverId'] = assignedId;
        list[c.idx] = slotMap;

        usedDriverIds.add(assignedId);
        txn.update(driversCol.doc(assignedId), {'status': DriverStatus.assigned});
        assignedCount++;

        // Rotate assigned driver to end so next assignment is FIFO.
        queue.removeWhere((id) => id == assignedId);
        queue.add(assignedId);
      }

      if (assignedCount > 0) {
        txn.update(routeRef, {'scheduleSlots': list, 'driverQueueIds': queue});
      }

      return assignedCount;
    });
  }

  Future<SlotDriverAssignmentResult> tryAssignDriverForNewSlot({
    required String routeId,
    required String slotId,
  }) async {
    // Keep queue up-to-date with online+available drivers.
    await _queueSvc.syncQueueWithOnlineAvailableDrivers(routeId);

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

      String? assignedId;

      // FIFO: pick the first eligible driver in the queue, but do NOT remove
      // them from the queue. We rotate on assignment.
      for (final id in q) {
        final dRef = driversCol.doc(id);
        final dSnap = await txn.get(dRef);
        if (!dSnap.exists) continue;
        final d = dSnap.data()!;
        if ((d['routeId'] as String? ?? '') != routeId) continue;
        if (!isEligibleDriverDoc(d)) continue;
        assignedId = id;
        break;
      }

      if (assignedId == null) {
        return SlotDriverAssignmentResult.noDrivers();
      }

      final slotMap = Map<String, dynamic>.from(list[slotIdx]);
      slotMap['driverId'] = assignedId;
      list[slotIdx] = slotMap;

      // Rotate assigned driver to end of queue.
      final newQueue = List<String>.from(q);
      newQueue.removeWhere((id) => id == assignedId);
      newQueue.add(assignedId);

      txn.update(routeRef, {'scheduleSlots': list, 'driverQueueIds': newQueue});
      txn.update(driversCol.doc(assignedId), {'status': DriverStatus.assigned});

      return SlotDriverAssignmentResult.assigned(driverId: assignedId);
    });
  }
}
