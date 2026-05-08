import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_status.dart';

class RouteDriverQueueService {
  RouteDriverQueueService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _routeRef(String routeId) =>
      _db.collection('route').doc(routeId);

  static List<String> parseIds(dynamic raw) {
    if (raw is! List) return [];

    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Stream<List<String>> watchQueueIds(String routeId) {
    return _routeRef(
      routeId,
    ).snapshots().map((s) => parseIds(s.data()?['driverQueueIds']));
  }

  Future<void> clearQueue(String routeId) async {
    await _routeRef(routeId).update({
      'driverQueueIds': <String>[],
    });
  }

  Future<void> setQueue(
    String routeId,
    List<String> driverIds,
  ) async {
    await _routeRef(routeId).update({
      'driverQueueIds': driverIds,
    });
  }

  /// =========================================================
  /// APPEND DRIVER
  /// =========================================================
  ///
  /// FIX:
  /// After adding a driver to queue,
  /// immediately try assigning old pending trips.
  ///
  Future<void> appendDriver(
    String routeId,
    String driverId,
  ) async {
    if (driverId.isEmpty) return;

    var added = false;

    await _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);

      final snap = await txn.get(ref);

      if (!snap.exists) return;

      final q = parseIds(snap.data()?['driverQueueIds']);

      if (q.contains(driverId)) return;

      q.add(driverId);

      txn.update(ref, {
        'driverQueueIds': q,
      });

      added = true;
    });

    /// IMPORTANT FIX
    /// Immediately assign existing scheduled trips.
    if (added) {
      await autoAssignPendingTrips(routeId);
    }
  }

  Future<void> removeDriver(
    String routeId,
    String driverId,
  ) async {
    await _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);

      final snap = await txn.get(ref);

      if (!snap.exists) return;

      final q = parseIds(snap.data()?['driverQueueIds']);

      q.removeWhere((id) => id == driverId);

      txn.update(ref, {
        'driverQueueIds': q,
      });
    });
  }

  /// =========================================================
  /// REMOVE ONLY OFFLINE DRIVERS
  /// =========================================================
  Future<void> pruneQueueToOnlineAvailableDrivers(
    String routeId,
  ) async {
    final routeSnap = await _routeRef(routeId).get();

    if (!routeSnap.exists) return;

    final current = parseIds(
      routeSnap.data()?['driverQueueIds'],
    );

    if (current.isEmpty) return;

    final keep = <String>[];

    for (final id in current) {
      final dSnap =
          await _db.collection('drivers').doc(id).get();

      if (!dSnap.exists) continue;

      final d = dSnap.data() ?? {};

      final st = DriverStatus.normalize(
        d['status'] as String?,
      );

      final sameRoute =
          (d['routeId'] as String? ?? '') == routeId;

      /// REMOVE ONLY OFFLINE
      if (st == DriverStatus.offline) continue;

      if (!sameRoute) continue;

      keep.add(id);
    }

    if (keep.length == current.length) return;

    await _routeRef(routeId).update({
      'driverQueueIds': keep,
    });
  }

  Future<void> queueAllAvailableDriversSorted(
    String routeId,
  ) async {
    final snap = await _db
        .collection('drivers')
        .where('routeId', isEqualTo: routeId)
        .get();

    final candidates =
        <({String driverDocId, String userKey})>[];

    for (final d in snap.docs) {
      final st = DriverStatus.normalize(
        d.data()['status'] as String?,
      );

      if (st == DriverStatus.offline) continue;

      final uid =
          d.data()['userId'] as String? ?? d.id;

      candidates.add((
        driverDocId: d.id,
        userKey: uid,
      ));
    }

    final names = <String, String>{};

    for (final c in candidates) {
      if (names.containsKey(c.userKey)) continue;

      final u =
          await _db.collection('users').doc(c.userKey).get();

      final m = u.data();

      final first = m?['firstName'] ?? '';
      final last = m?['lastName'] ?? '';

      final n = '$first $last'.trim();

      names[c.userKey] =
          n.isEmpty ? c.userKey : n;
    }

    candidates.sort((a, b) {
      final na = names[a.userKey] ?? a.driverDocId;
      final nb = names[b.userKey] ?? b.driverDocId;

      return na.toLowerCase().compareTo(
        nb.toLowerCase(),
      );
    });

    await setQueue(
      routeId,
      candidates.map((c) => c.driverDocId).toList(),
    );
  }

  /// =========================================================
  /// SYNC QUEUE
  /// =========================================================
  Future<void> syncQueueWithOnlineAvailableDrivers(
    String routeId,
  ) async {
    await pruneQueueToOnlineAvailableDrivers(
      routeId,
    );

    final snap = await _db
        .collection('drivers')
        .where('routeId', isEqualTo: routeId)
        .get();

    final toAppend = <String>[];

    for (final d in snap.docs) {
      final data = d.data();

      final st = DriverStatus.normalize(
        data['status'] as String?,
      );

      if (st == DriverStatus.offline) continue;

      toAppend.add(d.id);
    }

    if (toAppend.isEmpty) return;

    var changed = false;

    await _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);

      final routeSnap = await txn.get(ref);

      if (!routeSnap.exists) return;

      final q = parseIds(
        routeSnap.data()?['driverQueueIds'],
      );

      for (final id in toAppend) {
        if (q.contains(id)) continue;

        q.add(id);

        changed = true;
      }

      if (changed) {
        txn.update(ref, {
          'driverQueueIds': q,
        });
      }
    });

    /// IMPORTANT FIX
    if (changed) {
      await autoAssignPendingTrips(routeId);
    }
  }

  /// =========================================================
  /// MOVE DRIVER TO END
  /// =========================================================
  Future<void> moveDriverToQueueEnd({
    required String routeId,
    required String driverId,
  }) async {
    if (driverId.trim().isEmpty) return;

    await _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);

      final snap = await txn.get(ref);

      if (!snap.exists) return;

      final q = parseIds(
        snap.data()?['driverQueueIds'],
      );

      q.removeWhere((id) => id == driverId);

      q.add(driverId);

      txn.update(ref, {
        'driverQueueIds': q,
      });
    });
  }

  /// =========================================================
  /// COMPLETE TRIP
  /// =========================================================
  Future<void> completeTripAndRequeueEnd({
    required String routeId,
    required String driverId,
  }) async {
    if (driverId.isEmpty) return;

    await _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);

      final snap = await txn.get(ref);

      if (!snap.exists) return;

      final q = parseIds(
        snap.data()?['driverQueueIds'],
      );

      q.removeWhere((id) => id == driverId);

      q.add(driverId);

      txn.update(ref, {
        'driverQueueIds': q,
      });

      txn.update(
        _db.collection('drivers').doc(driverId),
        {
          'status': DriverStatus.available,
        },
      );
    });

    /// Try assigning next pending trip
    await autoAssignPendingTrips(routeId);
  }

  /// =========================================================
  /// AUTO ASSIGN PENDING TRIPS
  /// =========================================================
  ///
  /// MAIN FIX:
  /// - When drivers appear in queue
  /// - Assign old scheduled trips immediately
  ///
  Future<void> autoAssignPendingTrips(
    String routeId,
  ) async {
    /// Clean queue first
    await pruneQueueToOnlineAvailableDrivers(
      routeId,
    );

    final routeSnap = await _routeRef(routeId).get();

    if (!routeSnap.exists) return;

    final queue = parseIds(
      routeSnap.data()?['driverQueueIds'],
    );

    if (queue.isEmpty) return;

    /// Avoid composite-index requirement by querying route only, then filtering
    /// and sorting in memory.
    final tripsSnap = await _db
        .collection('trips')
        .where('routeId', isEqualTo: routeId)
        .get();

    final pendingTrips = tripsSnap.docs.where((doc) {
      final trip = doc.data();
      final status = (trip['status'] ?? '').toString().trim().toLowerCase();
      if (status != 'scheduled') return false;
      final assigned = (trip['driverId'] ?? '').toString().trim();
      return assigned.isEmpty;
    }).toList()
      ..sort((a, b) {
        DateTime toDate(dynamic v) {
          if (v is Timestamp) return v.toDate();
          if (v is String) return DateTime.tryParse(v) ?? DateTime(1970);
          return DateTime(1970);
        }

        final ad = toDate(a.data()['createdAt']);
        final bd = toDate(b.data()['createdAt']);
        return ad.compareTo(bd);
      });

    if (pendingTrips.isEmpty) return;

    for (final driverId in queue) {
      final driverSnap =
          await _db.collection('drivers').doc(driverId).get();

      if (!driverSnap.exists) continue;

      final driver = driverSnap.data()!;

      final status = DriverStatus.normalize(
        driver['status'],
      );

      /// Skip unavailable drivers
      if (status == DriverStatus.offline ||
          status == DriverStatus.onTrip) {
        continue;
      }

      final driverVehicleType =
          (driver['vehicleType'] ?? '')
              .toString()
              .trim();

      for (final tripDoc in pendingTrips) {
        final trip = tripDoc.data();

        /// Already assigned
        if ((trip['driverId'] ?? '')
            .toString()
            .isNotEmpty) {
          continue;
        }

        final tripVehicleType =
            (trip['vehicleType'] ?? '')
                .toString()
                .trim();

        /// Vehicle mismatch
        if (tripVehicleType !=
            driverVehicleType) {
          continue;
        }

        /// ASSIGN
        await _db.runTransaction((txn) async {
          final freshTrip =
              await txn.get(tripDoc.reference);

          final freshData = freshTrip.data();

          /// Double-check still unassigned
          if (freshData == null ||
              freshData['driverId'] != null) {
            return;
          }

          txn.update(
            tripDoc.reference,
            {
              'driverId': driverId,
            },
          );

          txn.update(
            _db.collection('drivers').doc(driverId),
            {
              'status': DriverStatus.assigned,
            },
          );
        });

        /// Round-robin
        await moveDriverToQueueEnd(
          routeId: routeId,
          driverId: driverId,
        );

        /// One trip per driver
        break;
      }
    }
  }
}