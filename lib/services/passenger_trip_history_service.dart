import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/schedule_slot.dart';
import '../models/trip_status.dart';

class PassengerTripHistoryService {
  PassengerTripHistoryService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const String _routesCollection = 'route';

  final Map<String, String> _lineBySlotId = {};
  final Map<String, String> _fromBySlotId = {};
  final Map<String, String> _toBySlotId = {};
  final Map<String, String> _statusBySlotId = {};

  String? get currentUserId => _auth.currentUser?.uid;

  Stream<List<ScheduleSlot>> watchPassengerTripHistory() {
    final uid = currentUserId;
    if (uid == null) {
      return Stream.value([]);
    }

    return _db.collection(_routesCollection).snapshots().map((snapshot) {
      final now = DateTime.now();
      final List<ScheduleSlot> slots = [];

      _lineBySlotId.clear();
      _fromBySlotId.clear();
      _toBySlotId.clear();
      _statusBySlotId.clear();

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final String routeId = doc.id;
        final String startPoint = (data['startPoint'] ?? data['from'] ?? '')
            .toString()
            .trim();
        final String endPoint = (data['endPoint'] ?? data['to'] ?? '')
            .toString()
            .trim();
        final String line =
            (data['line'] ?? data['routeName'] ?? '$startPoint ↔ $endPoint')
                .toString()
                .trim();

        final rawSlots = data['scheduleSlots'];
        if (rawSlots is! List) continue;

        for (int i = 0; i < rawSlots.length; i++) {
          final raw = rawSlots[i];
          if (raw is! Map) continue;

          final map = Map<String, dynamic>.from(raw);
          final slot = ScheduleSlot.fromMap('slot_$i', map);

          if (!slot.passengersIds.contains(uid)) continue;

          final rawStatus = TripStatus.normalize(
            (map['status'] ?? '').toString(),
          );

          String finalStatus;
          if (rawStatus == TripStatus.cancelled) {
            finalStatus = TripStatus.cancelled;
          } else if (slot.departureAt.isAfter(now)) {
            finalStatus = TripStatus.scheduled;
          } else {
            finalStatus = TripStatus.completed;
          }

          final fixedSlot = ScheduleSlot(
            slotId: slot.slotId,
            routeId: slot.routeId.isEmpty ? routeId : slot.routeId,
            departureAt: slot.departureAt,
            arrivalAt: slot.arrivalAt,
            price: slot.price,
            capacity: slot.capacity,
            vehicleType: slot.vehicleType,
            driverId: slot.driverId,
            passengersIds: slot.passengersIds,
            frequencyMinutes: slot.frequencyMinutes,
          );

          slots.add(fixedSlot);

          _lineBySlotId[fixedSlot.slotId] = line.isEmpty
              ? 'Route ${fixedSlot.routeId}'
              : line;
          _fromBySlotId[fixedSlot.slotId] = startPoint.isEmpty
              ? 'Unknown start'
              : startPoint;
          _toBySlotId[fixedSlot.slotId] = endPoint.isEmpty
              ? 'Unknown destination'
              : endPoint;
          _statusBySlotId[fixedSlot.slotId] = finalStatus;
        }
      }

      slots.sort((a, b) => b.departureAt.compareTo(a.departureAt));
      return slots;
    });
  }

  String lineOf(ScheduleSlot slot) {
    return _lineBySlotId[slot.slotId] ?? 'Route ${slot.routeId}';
  }

  String fromOf(ScheduleSlot slot) {
    return _fromBySlotId[slot.slotId] ?? 'Unknown start';
  }

  String toOf(ScheduleSlot slot) {
    return _toBySlotId[slot.slotId] ?? 'Unknown destination';
  }

  String statusOf(ScheduleSlot slot) {
    return _statusBySlotId[slot.slotId] ?? TripStatus.completed;
  }

  String priceTextOf(ScheduleSlot slot) {
    if (slot.price == null) return 'N/A';
    return '${slot.price!.toStringAsFixed(2)} NIS';
  }

  String vehicleTypeTextOf(ScheduleSlot slot) {
    return capitalize(slot.vehicleType);
  }

  String durationTextOf(ScheduleSlot slot) {
    return formatDuration(slot.arrivalAt.difference(slot.departureAt));
  }

  static String capitalize(String value) {
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
