import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/driver_status.dart';

class RouteDriverQueueService {
  RouteDriverQueueService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _routeRef(String routeId) =>
      _db.collection('route').doc(routeId);

  static List<String> parseIds(dynamic raw) {
    if (raw is! List) return [];
    final seen = <String>{};
    final out = <String>[];
    for (final e in raw) {
      final id = e.toString().trim();
      if (id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      out.add(id);
    }
    return out;
  }

  Stream<List<String>> watchQueueIds(String routeId) {
    return _routeRef(routeId)
        .snapshots()
        .map((s) => parseIds(s.data()?['driverQueueIds']));
  }

  Future<void> clearQueue(String routeId) async {
    await _routeRef(routeId).update({'driverQueueIds': <String>[]});
  }

  Future<void> setQueue(String routeId, List<String> driverIds) async {
    await _routeRef(routeId).update({'driverQueueIds': parseIds(driverIds)});
  }

  Future<void> appendDriver(String routeId, String driverId) async {
    final cleanRouteId = routeId.trim();
    final cleanDriverId = driverId.trim();
    if (cleanRouteId.isEmpty || cleanDriverId.isEmpty) return;

    await _db.runTransaction((txn) async {
      final ref = _routeRef(cleanRouteId);
      final snap = await txn.get(ref);

      if (!snap.exists) {
        debugPrint('[Queue] append failed route/$cleanRouteId not found');
        return;
      }

      final q = parseIds(snap.data()?['driverQueueIds']);
      debugPrint('[Queue] append routeId=$cleanRouteId driverId=$cleanDriverId before=$q');

      if (!q.contains(cleanDriverId)) {
        q.add(cleanDriverId);
        txn.update(ref, {'driverQueueIds': q});
      }

      debugPrint('[Queue] append routeId=$cleanRouteId after=$q');
    });
  }

  Future<void> removeDriver(String routeId, String driverId) async {
    final cleanRouteId = routeId.trim();
    final cleanDriverId = driverId.trim();
    if (cleanRouteId.isEmpty || cleanDriverId.isEmpty) return;

    await _db.runTransaction((txn) async {
      final ref = _routeRef(cleanRouteId);
      final snap = await txn.get(ref);
      if (!snap.exists) return;

      final q = parseIds(snap.data()?['driverQueueIds']);
      q.removeWhere((id) => id == cleanDriverId);
      txn.update(ref, {'driverQueueIds': q});

      debugPrint('[Queue] remove routeId=$cleanRouteId driverId=$cleanDriverId after=$q');
    });
  }

  /// Remove drivers that should not stay in the route queue.
  /// Important: assigned drivers can stay in the queue at the end for FIFO rotation,
  /// but they will not be assigned again until their status becomes available.
  Future<void> pruneQueue(String routeId) async {
    final cleanRouteId = routeId.trim();
    if (cleanRouteId.isEmpty) return;

    final routeSnap = await _routeRef(cleanRouteId).get();
    if (!routeSnap.exists) return;

    final current = parseIds(routeSnap.data()?['driverQueueIds']);
    if (current.isEmpty) return;

    final keep = <String>[];

    for (final id in current) {
      final dSnap = await _db.collection('drivers').doc(id).get();
      if (!dSnap.exists) continue;

      final d = dSnap.data() ?? {};
      final st = DriverStatus.normalize(d['status'] as String?);
      final sameRoute = (d['routeId'] ?? '').toString().trim() == cleanRouteId;

      if (!sameRoute) continue;
      if (st == DriverStatus.offline) continue;

      keep.add(id);
    }

    if (keep.length != current.length || keep.join('|') != current.join('|')) {
      await _routeRef(cleanRouteId).update({'driverQueueIds': keep});
      debugPrint('[Queue] prune routeId=$cleanRouteId before=$current after=$keep');
    }
  }

  /// Backward-compatible method name.
  Future<void> pruneQueueToOnlineAvailableDrivers(String routeId) async {
    await pruneQueue(routeId);
  }

  /// Append currently available drivers for this route without changing existing order.
  Future<void> syncQueueWithOnlineAvailableDrivers(String routeId) async {
    final cleanRouteId = routeId.trim();
    if (cleanRouteId.isEmpty) return;

    await pruneQueue(cleanRouteId);

    final snap = await _db
        .collection('drivers')
        .where('routeId', isEqualTo: cleanRouteId)
        .get();

    final availableIds = <String>[];
    for (final d in snap.docs) {
      final data = d.data();
      final st = DriverStatus.normalize(data['status'] as String?);
      if (st == DriverStatus.available) availableIds.add(d.id);
    }

    if (availableIds.isEmpty) {
      debugPrint('[Queue] sync routeId=$cleanRouteId no available drivers found');
      return;
    }

    await _db.runTransaction((txn) async {
      final ref = _routeRef(cleanRouteId);
      final routeSnap = await txn.get(ref);
      if (!routeSnap.exists) return;

      final q = parseIds(routeSnap.data()?['driverQueueIds']);
      final before = List<String>.from(q);

      for (final id in availableIds) {
        if (!q.contains(id)) q.add(id);
      }

      if (q.join('|') != before.join('|')) {
        txn.update(ref, {'driverQueueIds': q});
      }

      debugPrint('[Queue] sync routeId=$cleanRouteId before=$before available=$availableIds after=$q');
    });
  }

  Future<void> queueAllAvailableDriversSorted(String routeId) async {
    final cleanRouteId = routeId.trim();
    if (cleanRouteId.isEmpty) return;

    final snap = await _db
        .collection('drivers')
        .where('routeId', isEqualTo: cleanRouteId)
        .get();

    final ids = <String>[];
    for (final d in snap.docs) {
      final st = DriverStatus.normalize(d.data()['status'] as String?);
      if (st == DriverStatus.available) ids.add(d.id);
    }

    await setQueue(cleanRouteId, ids);
  }

  Future<void> moveDriverToQueueEnd({
    required String routeId,
    required String driverId,
  }) async {
    final cleanRouteId = routeId.trim();
    final cleanDriverId = driverId.trim();
    if (cleanRouteId.isEmpty || cleanDriverId.isEmpty) return;

    await _db.runTransaction((txn) async {
      final ref = _routeRef(cleanRouteId);
      final snap = await txn.get(ref);
      if (!snap.exists) return;

      final q = parseIds(snap.data()?['driverQueueIds']);
      q.removeWhere((id) => id == cleanDriverId);
      q.add(cleanDriverId);

      txn.update(ref, {'driverQueueIds': q});
      debugPrint('[Queue] moveEnd routeId=$cleanRouteId driverId=$cleanDriverId after=$q');
    });
  }

  Future<void> completeTripAndRequeueEnd({
    required String routeId,
    required String driverId,
  }) async {
    final cleanRouteId = routeId.trim();
    final cleanDriverId = driverId.trim();
    if (cleanRouteId.isEmpty || cleanDriverId.isEmpty) return;

    await _db.runTransaction((txn) async {
      final ref = _routeRef(cleanRouteId);
      final snap = await txn.get(ref);
      if (!snap.exists) return;

      final q = parseIds(snap.data()?['driverQueueIds']);
      q.removeWhere((id) => id == cleanDriverId);
      q.add(cleanDriverId);

      txn.update(ref, {'driverQueueIds': q});
      txn.set(
        _db.collection('drivers').doc(cleanDriverId),
        {
          'status': DriverStatus.available,
          'isOnline': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }
}
