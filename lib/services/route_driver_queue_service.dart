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
    await _routeRef(routeId).update({'driverQueueIds': <String>[]});
  }

  Future<void> setQueue(String routeId, List<String> driverIds) async {
    await _routeRef(routeId).update({'driverQueueIds': driverIds});
  }

  Future<void> appendDriver(String routeId, String driverId) async {
    if (driverId.isEmpty) return;
    await _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);
      final snap = await txn.get(ref);
      if (!snap.exists) return;
      final q = parseIds(snap.data()?['driverQueueIds']);
      if (q.contains(driverId)) return;
      q.add(driverId);
      txn.update(ref, {'driverQueueIds': q});
    });
  }

  Future<void> removeDriver(String routeId, String driverId) async {
    await _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);
      final snap = await txn.get(ref);
      if (!snap.exists) return;
      final q = parseIds(snap.data()?['driverQueueIds']);
      q.removeWhere((id) => id == driverId);
      txn.update(ref, {'driverQueueIds': q});
    });
  }

  /// Removes any drivers from this route queue that are NOT (online + available)
  /// anymore, or whose driver document no longer exists.
  ///
  /// This is used to keep queues clean in real time (no offline/unavailable
  /// drivers shown to route managers).
  Future<void> pruneQueueToOnlineAvailableDrivers(String routeId) async {
    final routeSnap = await _routeRef(routeId).get();
    if (!routeSnap.exists) return;
    final current = parseIds(routeSnap.data()?['driverQueueIds']);
    if (current.isEmpty) return;

    final keep = <String>[];
    for (final id in current) {
      final dSnap = await _db.collection('drivers').doc(id).get();
      if (!dSnap.exists) continue;
      final d = dSnap.data() ?? {};
      final isOnline = d['isOnline'] == true;
      final st = DriverStatus.normalize(d['status'] as String?);
      final sameRoute = (d['routeId'] as String? ?? '') == routeId;
      if (!isOnline) continue;
      if (st != DriverStatus.available) continue;
      if (!sameRoute) continue;
      keep.add(id);
    }

    // No gaps: array order stays, removed entries collapse automatically.
    if (keep.length == current.length) return;
    await _routeRef(routeId).update({'driverQueueIds': keep});
  }

  Future<void> queueAllAvailableDriversSorted(String routeId) async {
    final snap = await _db
        .collection('drivers')
        .where('routeId', isEqualTo: routeId)
        .get();

    final candidates = <({String driverDocId, String userKey})>[];
    for (final d in snap.docs) {
      final st = DriverStatus.normalize(d.data()['status'] as String?);
      if (st != DriverStatus.available) continue;
      final uid = d.data()['userId'] as String? ?? d.id;
      candidates.add((driverDocId: d.id, userKey: uid));
    }

    final names = <String, String>{};
    for (final c in candidates) {
      if (names.containsKey(c.userKey)) continue;
      final u = await _db.collection('users').doc(c.userKey).get();
      final m = u.data();
      final first = m?['firstName'] ?? '';
      final last = m?['lastName'] ?? '';
      final n = '$first $last'.trim();
      names[c.userKey] = n.isEmpty ? c.userKey : n;
    }

    candidates.sort((a, b) {
      final na = names[a.userKey] ?? a.driverDocId;
      final nb = names[b.userKey] ?? b.driverDocId;
      return na.toLowerCase().compareTo(nb.toLowerCase());
    });

    await setQueue(routeId, candidates.map((c) => c.driverDocId).toList());
  }

  /// Ensures that all (online + available) route drivers are present in the queue,
  /// appended to the end (without changing existing order).
  ///
  /// This is the "auto queue" behavior: managers shouldn't have to manually build
  /// or reorder the queue.
  Future<void> syncQueueWithOnlineAvailableDrivers(String routeId) async {
    // First, remove offline/unavailable drivers so UI never shows them.
    await pruneQueueToOnlineAvailableDrivers(routeId);

    final snap = await _db
        .collection('drivers')
        .where('routeId', isEqualTo: routeId)
        .get();

    final toAppend = <String>[];
    for (final d in snap.docs) {
      final data = d.data();
      final st = DriverStatus.normalize(data['status'] as String?);
      final isOnline = data['isOnline'] == true;
      if (!isOnline) continue;
      if (st != DriverStatus.available) continue;
      toAppend.add(d.id);
    }

    if (toAppend.isEmpty) return;

    await _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);
      final routeSnap = await txn.get(ref);
      if (!routeSnap.exists) return;
      final q = parseIds(routeSnap.data()?['driverQueueIds']);
      var changed = false;
      for (final id in toAppend) {
        if (q.contains(id)) continue;
        q.add(id);
        changed = true;
      }
      if (changed) {
        txn.update(ref, {'driverQueueIds': q});
      }
    });
  }

  /// Rotate a driver to the end of the queue.
  /// Used when a driver starts a trip.
  Future<void> moveDriverToQueueEnd({
    required String routeId,
    required String driverId,
  }) async {
    if (driverId.trim().isEmpty) return;
    await _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);
      final snap = await txn.get(ref);
      if (!snap.exists) return;
      final q = parseIds(snap.data()?['driverQueueIds']);
      q.removeWhere((id) => id == driverId);
      q.add(driverId);
      txn.update(ref, {'driverQueueIds': q});
    });
  }

  Future<void> completeTripAndRequeueEnd({
    required String routeId,
    required String driverId,
  }) async {
    if (driverId.isEmpty) return;
    await _db.runTransaction((txn) async {
      final ref = _routeRef(routeId);
      final snap = await txn.get(ref);
      if (!snap.exists) return;
      final q = parseIds(snap.data()?['driverQueueIds']);
      q.removeWhere((id) => id == driverId);
      q.add(driverId);
      txn.update(ref, {'driverQueueIds': q});
      txn.update(_db.collection('drivers').doc(driverId), {
        'status': 'available',
      });
    });
  }
}
