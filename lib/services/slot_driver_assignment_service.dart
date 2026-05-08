import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum SlotAssignmentOutcome {
  assigned,
  noQueue,
  noMatchingDriver,
  noPendingSlot,
  error,
}

class SlotAssignmentResult {
  const SlotAssignmentResult({
    required this.outcome,
    this.driverId,
    this.slotId,
    this.message,
    this.assignedCount = 0,
  });

  final SlotAssignmentOutcome outcome;
  final String? driverId;
  final String? slotId;
  final String? message;
  final int assignedCount;
}

class SlotDriverAssignmentService {
  SlotDriverAssignmentService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String _routeCollection = 'route';
  static const String _driversCollection = 'drivers';
  static const String _vehiclesCollection = 'vehicles';

  DocumentReference<Map<String, dynamic>> _routeRef(String routeId) {
    return _db.collection(_routeCollection).doc(routeId.trim());
  }

  DocumentReference<Map<String, dynamic>> _driverRef(String driverId) {
    return _db.collection(_driversCollection).doc(driverId.trim());
  }

  DocumentReference<Map<String, dynamic>> _vehicleRef(String vehicleId) {
    return _db.collection(_vehiclesCollection).doc(vehicleId.trim());
  }

  String _normalizeVehicleType(dynamic value) {
    final text = value
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), '');

    if (text.contains('micro')) return 'micro';
    if (text == 'bus') return 'bus';

    return text;
  }

  List<String> _parseQueue(dynamic raw) {
    if (raw is! List) return [];

    final seen = <String>{};
    final out = <String>[];

    for (final item in raw) {
      final id = item.toString().trim();
      if (id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      out.add(id);
    }

    return out;
  }

  List<Map<String, dynamic>> _parseSlots(dynamic raw) {
    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  bool _slotHasNoDriver(Map<String, dynamic> slot) {
    final driverId = slot['driverId'];
    return driverId == null || driverId.toString().trim().isEmpty;
  }

  DateTime _dateValue(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime(1900);
    return DateTime(1900);
  }

  DateTime _slotDeparture(Map<String, dynamic> slot) {
    return _dateValue(slot['departureAt']);
  }

  DateTime _slotArrival(Map<String, dynamic> slot) {
    final arrival = _dateValue(slot['arrivalAt']);
    if (arrival.year > 1900) return arrival;

    return _slotDeparture(slot).add(const Duration(minutes: 45));
  }

  bool _timesOverlap(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aStart = _slotDeparture(a);
    final aEnd = _slotArrival(a);

    final bStart = _slotDeparture(b);
    final bEnd = _slotArrival(b);

    return aStart.isBefore(bEnd) && bStart.isBefore(aEnd);
  }

  bool _driverHasTimeConflict({
    required List<Map<String, dynamic>> slots,
    required String driverId,
    required Map<String, dynamic> targetSlot,
  }) {
    for (final slot in slots) {
      final existingDriverId = slot['driverId']?.toString().trim();

      if (existingDriverId != driverId) continue;

      if (_timesOverlap(slot, targetSlot)) {
        return true;
      }
    }

    return false;
  }

  String _driverStatus(Map<String, dynamic> driverData) {
    return driverData['status']
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_-]+'), '');
  }

  bool _canUseDriverStatus(String status) {
    return status == 'available' || status == 'assigned';
  }

  String _vehicleTypeFromDriverAndVehicle({
    required Map<String, dynamic> driverData,
    required Map<String, dynamic>? vehicleData,
  }) {
    final fromDriver =
        driverData['vehicleType'] ?? driverData['type'] ?? driverData['vehicle'];

    if (fromDriver != null && fromDriver.toString().trim().isNotEmpty) {
      return _normalizeVehicleType(fromDriver);
    }

    final fromVehicle = vehicleData?['vehicleType'] ??
        vehicleData?['type'] ??
        vehicleData?['vehicle'] ??
        vehicleData?['vehicle_type'];

    return _normalizeVehicleType(fromVehicle ?? '');
  }

  Future<SlotAssignmentResult> autoAssignUpcomingUnassignedSlots({
    required String routeId,
  }) async {
    try {
      return await _db.runTransaction<SlotAssignmentResult>((tx) async {
        final cleanRouteId = routeId.trim();
        final routeRef = _routeRef(cleanRouteId);

        // =========================
        // 1. READS FIRST
        // =========================

        final routeSnap = await tx.get(routeRef);

        if (!routeSnap.exists) {
          debugPrint('[AutoAssign] route not found: $cleanRouteId');
          return const SlotAssignmentResult(
            outcome: SlotAssignmentOutcome.error,
            message: 'Route not found',
          );
        }

        final routeData = routeSnap.data() ?? {};
        final originalQueue = _parseQueue(routeData['driverQueueIds']);
        final slots = _parseSlots(routeData['scheduleSlots']);

        debugPrint('================ AUTO ASSIGN MANY ================');
        debugPrint('[AutoAssign] routeId=$cleanRouteId');
        debugPrint('[AutoAssign] queue=$originalQueue');
        debugPrint('[AutoAssign] slots=${slots.length}');

        if (originalQueue.isEmpty) {
          return const SlotAssignmentResult(
            outcome: SlotAssignmentOutcome.noQueue,
            message: 'Queue is empty',
          );
        }

        final pendingIndexes = <int>[];

        for (int i = 0; i < slots.length; i++) {
          if (_slotHasNoDriver(slots[i])) {
            pendingIndexes.add(i);
          }
        }

        pendingIndexes.sort(
          (a, b) => _slotDeparture(slots[a]).compareTo(_slotDeparture(slots[b])),
        );

        if (pendingIndexes.isEmpty) {
          return const SlotAssignmentResult(
            outcome: SlotAssignmentOutcome.noPendingSlot,
            message: 'No pending slots',
          );
        }

        final driverSnaps =
            <String, DocumentSnapshot<Map<String, dynamic>>>{};

        final vehicleSnaps =
            <String, DocumentSnapshot<Map<String, dynamic>>>{};

        for (final driverId in originalQueue) {
          final driverSnap = await tx.get(_driverRef(driverId));
          driverSnaps[driverId] = driverSnap;

          final driverData = driverSnap.data();
          final vehicleId = driverData?['vehicleId'];

          if (vehicleId != null && vehicleId.toString().trim().isNotEmpty) {
            final cleanVehicleId = vehicleId.toString().trim();
            final vehicleSnap = await tx.get(_vehicleRef(cleanVehicleId));
            vehicleSnaps[cleanVehicleId] = vehicleSnap;
          }
        }

        // =========================
        // 2. DECIDE ALL ASSIGNMENTS
        // =========================

        final updatedSlots = slots
            .map((slot) => Map<String, dynamic>.from(slot))
            .toList();

        final queue = List<String>.from(originalQueue);
        final selectedDrivers = <String>{};

        String? firstDriverId;
        String? firstSlotId;
        int assignedCount = 0;

        for (final slotIndex in pendingIndexes) {
          final slot = updatedSlots[slotIndex];

          if (!_slotHasNoDriver(slot)) continue;

          final slotVehicleType = _normalizeVehicleType(slot['vehicleType']);

          debugPrint('[AutoAssign] checking slot=${slot['slotId']}');
          debugPrint('[AutoAssign] slotVehicleType=$slotVehicleType');

          String? selectedDriverId;

          for (final driverId in List<String>.from(queue)) {
            final driverSnap = driverSnaps[driverId];

            if (driverSnap == null || !driverSnap.exists) {
              debugPrint('[AutoAssign] skip $driverId: driver not found');
              continue;
            }

            final driverData = driverSnap.data() ?? {};
            final status = _driverStatus(driverData);
            final isOnline = driverData['isOnline'] == true;

            if (!isOnline) {
              debugPrint('[AutoAssign] skip $driverId: offline');
              continue;
            }

            if (!_canUseDriverStatus(status)) {
              debugPrint('[AutoAssign] skip $driverId: status=$status');
              continue;
            }

            final vehicleId = driverData['vehicleId']?.toString().trim() ?? '';
            final vehicleData =
                vehicleId.isEmpty ? null : vehicleSnaps[vehicleId]?.data();

            final driverVehicleType = _vehicleTypeFromDriverAndVehicle(
              driverData: driverData,
              vehicleData: vehicleData,
            );

            debugPrint('[AutoAssign] driver=$driverId');
            debugPrint('[AutoAssign] driverVehicleType=$driverVehicleType');
            debugPrint('[AutoAssign] slotVehicleType=$slotVehicleType');

            if (driverVehicleType != slotVehicleType) {
              debugPrint('[AutoAssign] skip $driverId: vehicle mismatch');
              continue;
            }

            if (_driverHasTimeConflict(
              slots: updatedSlots,
              driverId: driverId,
              targetSlot: slot,
            )) {
              debugPrint('[AutoAssign] skip $driverId: time conflict');
              continue;
            }

            selectedDriverId = driverId;
            break;
          }

          if (selectedDriverId == null) {
            debugPrint('[AutoAssign] no driver for slot=${slot['slotId']}');
            continue;
          }

          updatedSlots[slotIndex]['driverId'] = selectedDriverId;
          updatedSlots[slotIndex]['status'] = 'assigned';
          updatedSlots[slotIndex]['assignedAt'] = Timestamp.now();

          queue.remove(selectedDriverId);
          queue.add(selectedDriverId);

          selectedDrivers.add(selectedDriverId);

          firstDriverId ??= selectedDriverId;
          firstSlotId ??= slot['slotId']?.toString();

          assignedCount++;

          debugPrint(
            '[AutoAssign] assigned slot=${slot['slotId']} driver=$selectedDriverId',
          );
          debugPrint('[AutoAssign] queue after rotation=$queue');
        }

        if (assignedCount == 0) {
          return const SlotAssignmentResult(
            outcome: SlotAssignmentOutcome.noMatchingDriver,
            message: 'No matching driver found',
          );
        }

        // =========================
        // 3. WRITES AFTER READS
        // =========================

        tx.update(routeRef, {
          'scheduleSlots': updatedSlots,
          'driverQueueIds': queue,
        });

        for (final driverId in selectedDrivers) {
          tx.update(_driverRef(driverId), {
            'status': 'assigned',
            'isOnline': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        debugPrint('[AutoAssign] SUCCESS assignedCount=$assignedCount');
        debugPrint('[AutoAssign] finalQueue=$queue');

        return SlotAssignmentResult(
          outcome: SlotAssignmentOutcome.assigned,
          driverId: firstDriverId,
          slotId: firstSlotId,
          assignedCount: assignedCount,
          message: 'Assigned $assignedCount trips',
        );
      });
    } catch (e) {
      debugPrint('[AutoAssign] ERROR: $e');

      return SlotAssignmentResult(
        outcome: SlotAssignmentOutcome.error,
        message: e.toString(),
      );
    }
  }

  Future<SlotAssignmentResult> tryAssignOldestPendingTripForDriver({
    required String routeId,
    required String driverId,
  }) async {
    return autoAssignUpcomingUnassignedSlots(routeId: routeId);
  }
}