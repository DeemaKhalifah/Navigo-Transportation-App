import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/route.dart';
import '../models/schedule_slot.dart';
import '../models/trip_status.dart';

class DriverTripsService {
  DriverTripsService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const String _routesCollection = 'route';

  final Map<String, RouteModel> _routeBySlotId = {};
  final Map<String, String> _statusBySlotId = {};

  String? get currentDriverId => _auth.currentUser?.uid;

  Stream<List<ScheduleSlot>> watchDriverTrips() {
    final driverId = currentDriverId;
    if (driverId == null || driverId.isEmpty) {
      return Stream.value([]);
    }

    return _db.collection(_routesCollection).snapshots().map((snapshot) {
      final now = DateTime.now();
      final List<ScheduleSlot> trips = [];

      _routeBySlotId.clear();
      _statusBySlotId.clear();

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final routeMap = Map<String, dynamic>.from(data);
        routeMap['routeId'] = (routeMap['routeId'] ?? doc.id).toString();

        final RouteModel route = RouteModel.fromMap(routeMap);

        final rawSlots = data['scheduleSlots'];
        if (rawSlots is! List) continue;

        for (int i = 0; i < rawSlots.length; i++) {
          final raw = rawSlots[i];
          if (raw is! Map) continue;

          final slotMap = Map<String, dynamic>.from(raw);
          final slot = ScheduleSlot.fromMap('slot_$i', slotMap);

          if (slot.driverId.trim() != driverId.trim()) continue;

          final fixedSlot = ScheduleSlot(
            slotId: slot.slotId,
            routeId: slot.routeId.isEmpty ? route.routeId : slot.routeId,
            departureAt: slot.departureAt,
            arrivalAt: slot.arrivalAt,
            price: slot.price,
            capacity: slot.capacity,
            vehicleType: slot.vehicleType,
            driverId: slot.driverId,
            passengersIds: List<String>.from(slot.passengersIds),
            frequencyMinutes: slot.frequencyMinutes,
            status: _resolveStatus(
              rawStatus: slot.status,
              departureAt: slot.departureAt,
              arrivalAt: slot.arrivalAt,
              now: now,
            ),
          );

          trips.add(fixedSlot);
          _routeBySlotId[fixedSlot.slotId] = route;
          _statusBySlotId[fixedSlot.slotId] = fixedSlot.status;
        }
      }

      trips.sort((a, b) => b.departureAt.compareTo(a.departureAt));
      return trips;
    });
  }

  RouteModel? routeOf(ScheduleSlot slot) {
    return _routeBySlotId[slot.slotId];
  }

  String lineOf(ScheduleSlot slot) {
    final route = routeOf(slot);
    if (route == null) return 'Route ${slot.routeId}';

    final start = route.startPoint.trim();
    final end = route.endPoint.trim();

    if (start.isEmpty && end.isEmpty) {
      return 'Route ${slot.routeId}';
    }

    return '$start ↔ $end';
  }

  String fromOf(ScheduleSlot slot) {
    final route = routeOf(slot);
    if (route == null) return 'Unknown start';

    final start = route.startPoint.trim();
    return start.isEmpty ? 'Unknown start' : start;
  }

  String toOf(ScheduleSlot slot) {
    final route = routeOf(slot);
    if (route == null) return 'Unknown destination';

    final end = route.endPoint.trim();
    return end.isEmpty ? 'Unknown destination' : end;
  }

  String statusOf(ScheduleSlot slot) {
    return _statusBySlotId[slot.slotId] ?? TripStatus.scheduled;
  }

  int bookedSeatsOf(ScheduleSlot slot) {
    return slot.passengersIds.length;
  }

  String priceTextOf(ScheduleSlot slot) {
    if (slot.price != null) {
      return '${slot.price!.toStringAsFixed(2)} NIS';
    }

    final route = routeOf(slot);
    if (route != null) {
      return '${route.price.toStringAsFixed(2)} NIS';
    }

    return 'N/A';
  }

  String vehicleTextOf(ScheduleSlot slot) {
    return _capitalize(slot.vehicleType);
  }

  String dateTextOf(ScheduleSlot slot) {
    return formatDate(slot.departureAt);
  }

  String timeTextOf(ScheduleSlot slot) {
    return formatTime(slot.departureAt);
  }

  String durationTextOf(ScheduleSlot slot) {
    return formatDuration(slot.arrivalAt.difference(slot.departureAt));
  }

  String _resolveStatus({
    required String rawStatus,
    required DateTime departureAt,
    required DateTime arrivalAt,
    required DateTime now,
  }) {
    final normalized = TripStatus.normalize(rawStatus);

    if (normalized == TripStatus.cancelled) {
      return TripStatus.cancelled;
    }

    if (normalized == TripStatus.completed) {
      return TripStatus.completed;
    }

    if (normalized == TripStatus.onTrip) {
      return TripStatus.onTrip;
    }

    if (arrivalAt.isBefore(now)) {
      return TripStatus.completed;
    }

    return TripStatus.scheduled;
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }

  static String formatDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]} ${dt.year}';
  }

  static String formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String formatDuration(Duration d) {
    final totalMinutes = d.inMinutes.abs();
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours > 0 && minutes > 0) {
      return '${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h';
    } else {
      return '$minutes min';
    }
  }
}
