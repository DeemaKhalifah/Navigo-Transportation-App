import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/route.dart';
import '../models/schedule_slot.dart';

class DriverTripDetailsService {
  DriverTripDetailsService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String _routesCollection = 'route';
  static const String _usersCollection = 'users';
  static const String _passengersCollection = 'passengers';

  Future<Map<String, dynamic>?> getTripDetails({
    required String tripId,
    String? routeId,
  }) async {
    final routeDocs = routeId != null && routeId.trim().isNotEmpty
        ? [await _db.collection(_routesCollection).doc(routeId).get()]
        : await _db.collection(_routesCollection).get().then((s) => s.docs);

    for (final doc in routeDocs) {
      if (!doc.exists) continue;

      final data = doc.data();
      if (data == null) continue;

      final routeMap = Map<String, dynamic>.from(data);
      routeMap['routeId'] = (routeMap['routeId'] ?? doc.id).toString();

      final RouteModel route = RouteModel.fromMap(routeMap);

      final rawSlots = data['scheduleSlots'];
      if (rawSlots is! List) continue;

      for (int i = 0; i < rawSlots.length; i++) {
        final raw = rawSlots[i];
        if (raw is! Map) continue;

        final slotMap = Map<String, dynamic>.from(raw as Map);
        final slot = ScheduleSlot.fromMap('slot_$i', slotMap);

        if (slot.slotId != tripId) continue;

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
          status: slot.status,
        );

        final passengers = await _getPassengersForTrip(
          passengerIds: fixedSlot.passengersIds,
          fallbackPickup: route.startPoint,
        );

        return {'route': route, 'slot': fixedSlot, 'passengers': passengers};
      }
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> _getPassengersForTrip({
    required List<String> passengerIds,
    required String fallbackPickup,
  }) async {
    if (passengerIds.isEmpty) return [];

    final List<Map<String, dynamic>> result = [];

    for (final passengerId in passengerIds) {
      final userSnap = await _db
          .collection(_usersCollection)
          .doc(passengerId)
          .get();
      final passengerSnap = await _db
          .collection(_passengersCollection)
          .doc(passengerId)
          .get();

      final userData = userSnap.data() ?? {};
      final passengerData = passengerSnap.data() ?? {};

      final firstName = (userData['firstName'] ?? '').toString().trim();
      final lastName = (userData['lastName'] ?? '').toString().trim();
      final fullName = '$firstName $lastName'.trim();

      final pickup =
          (passengerData['pickup'] ??
                  passengerData['pickupPoint'] ??
                  passengerData['pickupLocation'] ??
                  fallbackPickup)
              .toString()
              .trim();

      result.add({
        'userId': passengerId,
        'name': fullName.isEmpty ? 'Passenger' : fullName,
        'pickup': pickup.isEmpty ? fallbackPickup : pickup,
      });
    }

    return result;
  }

  String lineText(RouteModel route) {
    final start = route.startPoint.trim();
    final end = route.endPoint.trim();

    if (start.isEmpty && end.isEmpty) {
      return 'Route ${route.routeId}';
    }

    return '$start ↔ $end';
  }

  String priceText(ScheduleSlot slot, RouteModel route) {
    if (slot.price != null) {
      return '${slot.price!.toStringAsFixed(2)} NIS';
    }
    return '${route.price.toStringAsFixed(2)} NIS';
  }

  String vehicleText(ScheduleSlot slot) {
    if (slot.vehicleType.isEmpty) return 'Unknown';
    return slot.vehicleType[0].toUpperCase() +
        slot.vehicleType.substring(1).toLowerCase();
  }

  String dateText(ScheduleSlot slot) {
    return formatDate(slot.departureAt);
  }

  String timeText(ScheduleSlot slot) {
    return formatTime(slot.departureAt);
  }

  String durationText(ScheduleSlot slot) {
    return formatDuration(slot.arrivalAt.difference(slot.departureAt));
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
      return '${minutes} min';
    }
  }
}
