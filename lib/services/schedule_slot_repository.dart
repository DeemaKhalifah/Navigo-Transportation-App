import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/schedule_slot.dart';

/// Schedule slots are stored **on the route document**:
/// `route/{routeId}` → field `scheduleSlots`: `[ { slotId, routeId, departureAt, ... }, ... ]`
///
/// The [routeId] on the manager profile (`users` / `route_manager`) selects this document.
class ScheduleSlotRepository {
  ScheduleSlotRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _routeRef(String routeId) {
    return _db.collection('route').doc(routeId);
  }

  String _newSlotId() => _db.collection('_').doc().id;

  static List<Map<String, dynamic>> parseSlotList(dynamic raw) {
    if (raw is! List) return [];
    final list = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) {
        list.add(Map<String, dynamic>.from(
          e.map((k, v) => MapEntry(k.toString(), v)),
        ));
      }
    }
    return list;
  }

  Stream<List<ScheduleSlot>> watchSlots(String routeId) {
    return _routeRef(routeId).snapshots().map((snap) {
      final raw = snap.data()?['scheduleSlots'];
      final maps = parseSlotList(raw);
      final out = <ScheduleSlot>[];
      for (final m in maps) {
        final sid = m['slotId'] as String? ?? '';
        if (sid.isEmpty) continue;
        out.add(ScheduleSlot.fromMap(sid, m));
      }
      out.sort((a, b) => a.departureAt.compareTo(b.departureAt));
      return out;
    });
  }

  /// Appends a slot to `route.scheduleSlots`. Returns generated [slotId].
  Future<String> addSlot(ScheduleSlot slot) async {
    final routeId = slot.routeId;
    final routeRef = _routeRef(routeId);
    final slotId = _newSlotId();

    await _db.runTransaction((txn) async {
      final snap = await txn.get(routeRef);
      if (!snap.exists) {
        throw StateError('Route document not found: route/$routeId');
      }
      final list = parseSlotList(snap.data()?['scheduleSlots']);
      final m = slot.toMap();
      m['slotId'] = slotId;
      m['routeId'] = routeId;
      list.add(m);
      txn.update(routeRef, {'scheduleSlots': list});
    });

    return slotId;
  }

  Future<void> upsertSlot(ScheduleSlot slot) async {
    final routeRef = _routeRef(slot.routeId);

    await _db.runTransaction((txn) async {
      final snap = await txn.get(routeRef);
      if (!snap.exists) {
        throw StateError('Route document not found: route/${slot.routeId}');
      }
      final list = parseSlotList(snap.data()?['scheduleSlots']);
      final m = slot.toMap();
      m['slotId'] = slot.slotId;
      m['routeId'] = slot.routeId;

      final idx = list.indexWhere(
        (e) => e['slotId'] == slot.slotId,
      );
      if (idx >= 0) {
        list[idx] = m;
      } else {
        list.add(m);
      }
      txn.update(routeRef, {'scheduleSlots': list});
    });
  }

  Future<void> deleteSlot(String routeId, String slotId) async {
    final routeRef = _routeRef(routeId);

    await _db.runTransaction((txn) async {
      final snap = await txn.get(routeRef);
      if (!snap.exists) return;
      final list = parseSlotList(snap.data()?['scheduleSlots']);
      list.removeWhere((e) => e['slotId'] == slotId);
      txn.update(routeRef, {'scheduleSlots': list});
    });
  }
}
