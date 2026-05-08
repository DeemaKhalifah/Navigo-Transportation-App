import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_status.dart';
import '../models/schedule_slot.dart';
import '../models/trip_status.dart';
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

  bool _isUnassigned(dynamic v) =>
      (v ?? '').toString().trim().isEmpty;

  bool _isScheduled(Map<String, dynamic> m) {
    final s = TripStatus.normalize(m['status'] as String?);
    return s == TripStatus.scheduled;
  }

  String _normalizeVehicleType(String? value) {
    final v = (value ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), '')
        .trim();
    if (v.contains('micro')) return 'microbus';
    if (v.contains('bus') && !v.contains('micro')) return 'bus';
    return v;
  }

  String _driverVehicle(Map<String, dynamic> d) {
    final direct = d['vehicleType'] as String?;
    final nested =
        d['vehicle'] is Map ? (d['vehicle']['type'] as String?) : null;
    return _normalizeVehicleType(direct ?? nested);
  }

  String _slotVehicle(Map<String, dynamic> m) =>
      _normalizeVehicleType(m['vehicleType'] as String?);

  String _driverId(Map<String, dynamic> m) =>
      (m['driverId'] ?? '').toString().trim();

  // ======================================================
  // MAIN AUTO ASSIGN
  // ======================================================
  Future<int> autoAssignUpcomingUnassignedSlots({
    required String routeId,
    int maxAssignments = 10,
  }) async {
    await _queueSvc.syncQueueWithOnlineAvailableDrivers(routeId);

    return _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);
      final snap = await txn.get(ref);
      if (!snap.exists) return 0;

      final data = snap.data()!;
      final queue = RouteDriverQueueService.parseIds(data['driverQueueIds']);
      final list =
          ScheduleSlotRepository.parseSlotList(data['scheduleSlots']);

      int assigned = 0;

      for (final driverId in queue) {
        if (assigned >= maxAssignments) break;
        final driverRef = _db.collection('drivers').doc(driverId);
        final driverSnap = await txn.get(driverRef);
        if (!driverSnap.exists) continue;

        final driver = driverSnap.data()!;
        final driverStatus =
            DriverStatus.normalize(driver['status'] as String?);

        if (driverStatus != DriverStatus.available) {
          continue;
        }

        final driverVehicle = _driverVehicle(driver);

        for (int i = 0; i < list.length; i++) {
          final slot = list[i];

          if (!_isScheduled(slot)) continue;

          final slotDriverId = _driverId(slot);
          if (slotDriverId.isNotEmpty) continue;

          final slotVehicle = _slotVehicle(slot);

          if (slotVehicle != driverVehicle) continue;

          // =========================
          // FIXED NULL CHECK
          // =========================
          final fresh = await txn.get(ref);
          final freshList =
              ScheduleSlotRepository.parseSlotList(fresh.data()?['scheduleSlots']);

          final current = _driverId(freshList[i]);
          if (current.isNotEmpty) continue;

          // ASSIGN
          final updated = Map<String, dynamic>.from(freshList[i]);
          updated['driverId'] = driverId;
          updated['assignedAt'] = FieldValue.serverTimestamp();
          updated['status'] = TripStatus.scheduled;

          freshList[i] = updated;

          txn.update(ref, {'scheduleSlots': freshList});

          txn.update(driverRef, {
            'status': DriverStatus.assigned,
          });

          // rotate queue
          final newQueue = List<String>.from(queue);
          newQueue.remove(driverId);
          newQueue.add(driverId);

          txn.update(ref, {'driverQueueIds': newQueue});

          assigned++;
          break;
        }
      }

      return assigned;
    });
  }

  // ======================================================
  // ASSIGN SINGLE SLOT
  // ======================================================
  Future<bool> tryAssignDriverForSlot({
    required String routeId,
    required String slotId,
  }) async {
    await _queueSvc.syncQueueWithOnlineAvailableDrivers(routeId);

    return _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);
      final snap = await txn.get(ref);
      if (!snap.exists) return false;

      final data = snap.data()!;
      final queue = RouteDriverQueueService.parseIds(data['driverQueueIds']);
      final list =
          ScheduleSlotRepository.parseSlotList(data['scheduleSlots']);

      final idx = list.indexWhere((e) => e['slotId'] == slotId);
      if (idx < 0) return false;

      final slot = list[idx];

      // FIXED: null-safe check
      if (_driverId(slot).isNotEmpty) return false;

      final slotVehicle = _slotVehicle(slot);

      for (final driverId in queue) {
        final driverRef = _db.collection('drivers').doc(driverId);
        final driverSnap = await txn.get(driverRef);
        if (!driverSnap.exists) continue;

        final driver = driverSnap.data()!;
        final driverStatus =
            DriverStatus.normalize(driver['status'] as String?);
        if (driverStatus != DriverStatus.available) continue;
        final driverVehicle = _driverVehicle(driver);

        if (driverVehicle != slotVehicle) continue;

        // assign
        final updated = Map<String, dynamic>.from(slot);
        updated['driverId'] = driverId;
        updated['assignedAt'] = FieldValue.serverTimestamp();
        updated['status'] = TripStatus.scheduled;

        list[idx] = updated;

        txn.update(ref, {'scheduleSlots': list});

        txn.update(driverRef, {
          'status': DriverStatus.assigned,
        });

        return true;
      }

      return false;
    });
  }

  Future<SlotDriverAssignmentResult> tryAssignDriverForNewSlot({
    required String routeId,
    required String slotId,
  }) async {
    final assigned = await tryAssignDriverForSlot(routeId: routeId, slotId: slotId);
    if (!assigned) return SlotDriverAssignmentResult.noDrivers();

    final snap = await _routeRef(routeId).get();
    final list = ScheduleSlotRepository.parseSlotList(snap.data()?['scheduleSlots']);
    final idx = list.indexWhere((e) => e['slotId'] == slotId);
    if (idx < 0) return SlotDriverAssignmentResult.noDrivers();
    final did = _driverId(list[idx]);
    if (did.isEmpty) return SlotDriverAssignmentResult.noDrivers();
    return SlotDriverAssignmentResult.assigned(driverId: did);
  }

  Future<SlotDriverAssignmentResult> tryAssignOldestPendingTripForDriver({
    required String routeId,
    required String driverId,
  }) async {
    await _queueSvc.syncQueueWithOnlineAvailableDrivers(routeId);

    return _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);
      final snap = await txn.get(ref);
      if (!snap.exists) return SlotDriverAssignmentResult.noDrivers();

      final data = snap.data()!;
      final list = ScheduleSlotRepository.parseSlotList(data['scheduleSlots']);
      if (list.isEmpty) return SlotDriverAssignmentResult.noDrivers();

      final driverRef = _db.collection('drivers').doc(driverId);
      final driverSnap = await txn.get(driverRef);
      if (!driverSnap.exists) return SlotDriverAssignmentResult.noDrivers();
      final driver = driverSnap.data()!;
      final st = DriverStatus.normalize(driver['status'] as String?);
      if (st != DriverStatus.available) return SlotDriverAssignmentResult.noDrivers();
      final vehicle = _driverVehicle(driver);

      int? targetIdx;
      DateTime? bestDep;
      for (var i = 0; i < list.length; i++) {
        final slot = list[i];
        if (!_isScheduled(slot)) continue;
        if (_driverId(slot).isNotEmpty) continue;
        if (_slotVehicle(slot) != vehicle) continue;
        final sid = (slot['slotId'] ?? '').toString();
        if (sid.isEmpty) continue;
        final dep = ScheduleSlot.fromMap(sid, slot).departureAt;
        if (bestDep == null || dep.isBefore(bestDep)) {
          bestDep = dep;
          targetIdx = i;
        }
      }
      if (targetIdx == null) return SlotDriverAssignmentResult.noDrivers();

      final updated = Map<String, dynamic>.from(list[targetIdx]);
      updated['driverId'] = driverId;
      updated['assignedAt'] = FieldValue.serverTimestamp();
      updated['status'] = TripStatus.scheduled;
      list[targetIdx] = updated;

      final queue = RouteDriverQueueService.parseIds(data['driverQueueIds']);
      queue.remove(driverId);
      queue.add(driverId);

      txn.update(ref, {'scheduleSlots': list, 'driverQueueIds': queue});
      txn.update(driverRef, {'status': DriverStatus.assigned});

      return SlotDriverAssignmentResult.assigned(driverId: driverId);
    });
  }

  // ======================================================
  // CLEANUP FUNCTION (IMPORTANT)
  // ======================================================
  Future<void> normalizeBadDriverIds(String routeId) async {
    await _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);
      final snap = await txn.get(ref);
      if (!snap.exists) return;

      final list =
          ScheduleSlotRepository.parseSlotList(snap.data()?['scheduleSlots']);

      bool changed = false;

      for (int i = 0; i < list.length; i++) {
        final d = list[i]['driverId'];

        if (_isUnassigned(d)) {
          list[i]['driverId'] = null;
          changed = true;
        }
      }

      if (changed) {
        txn.update(ref, {'scheduleSlots': list});
      }
    });
  }
}