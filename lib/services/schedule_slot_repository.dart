import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/schedule_slot.dart';

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
        list.add(
          Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))),
        );
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
      _copyRouteTravelDataToSlot(snap.data() ?? {}, m);
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
      _copyRouteTravelDataToSlot(snap.data() ?? {}, m);

      final idx = list.indexWhere((e) => e['slotId'] == slot.slotId);
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

  static void _copyRouteTravelDataToSlot(
    Map<String, dynamic> routeData,
    Map<String, dynamic> slot,
  ) {
    final etaMinutes = routeData['etaMinutes'];
    final etaText = routeData['etaText'];
    final distanceMeters = routeData['distanceMeters'];
    final distanceKm = routeData['distanceKm'];
    final distanceText = routeData['distanceText'];
    final routePolyline = routeData['routePolyline'];
    final routePath = routeData['routePath'] ?? routeData['path'];
    final routeModule = routeData['routeModule'];

    if (etaMinutes != null) slot['etaMinutes'] = etaMinutes;
    if (etaText != null) slot['etaText'] = etaText;
    if (distanceMeters != null) slot['distanceMeters'] = distanceMeters;
    if (distanceKm != null) slot['distanceKm'] = distanceKm;
    if (distanceText != null) slot['distanceText'] = distanceText;
    if (routePolyline != null) slot['routePolyline'] = routePolyline;
    if (routePath != null) slot['routePath'] = routePath;
    if (routeModule != null) slot['routeModule'] = routeModule;

    final departure = _parseDate(slot['departureAt']);
    final minutes = etaMinutes is num ? etaMinutes.toInt() : null;
    if (departure != null && minutes != null) {
      slot['estimatedArrivalAt'] = Timestamp.fromDate(
        departure.add(Duration(minutes: minutes)),
      );
    }
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
