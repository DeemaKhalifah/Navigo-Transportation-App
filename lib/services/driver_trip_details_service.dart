import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/route.dart';
import '../models/schedule_slot.dart';
import 'geocoding_service.dart';

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

        final slotMap = Map<String, dynamic>.from(raw);
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
          passengerBookings: fixedSlot.passengerBookings,
          fallbackPickup: route.startPoint,
        );

        return {'route': route, 'slot': fixedSlot, 'passengers': passengers};
      }
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> _getPassengersForTrip({
    required List<Map<String, dynamic>> passengerBookings,
    required String fallbackPickup,
  }) async {
    if (passengerBookings.isEmpty) return [];

    final List<Map<String, dynamic>> result = [];

    for (final booking in passengerBookings) {
      final passengerId = (booking['passengerId'] ?? '').toString().trim();
      if (passengerId.isEmpty) continue;
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

      final typedPickup = _cleanPickupText(booking['pickupLocationDescription']);
      final pickup =
          typedPickup.isNotEmpty
              ? typedPickup
              : await _pickupNameFromPassengerLocation(
                    passengerData,
                    fallbackPickup: fallbackPickup,
                  );

      result.add({
        'userId': passengerId,
        'name': fullName.isEmpty ? 'Passenger' : fullName,
        'pickup': pickup.isEmpty ? fallbackPickup : pickup,
      });
    }

    return result;
  }

  Future<String> _pickupNameFromPassengerLocation(
    Map<String, dynamic> passengerData, {
    required String fallbackPickup,
  }) async {
    final directPickup = _cleanPickupText(
      passengerData['pickupLocationDescription'],
    );
    if (directPickup.isNotEmpty) return directPickup;

    final lat = _toDouble(passengerData['latitude']);
    final lng = _toDouble(passengerData['longitude']);

    if (lat == null || lng == null) {
      return fallbackPickup.trim().isEmpty ? 'Unknown pickup' : fallbackPickup;
    }

    final label = await GeocodingService.reverseGeocodeLabel(LatLng(lat, lng));
    if (_looksLikeCoordinates(label)) {
      return fallbackPickup.trim().isEmpty ? 'Unknown pickup' : fallbackPickup;
    }
    return label.trim().isEmpty ? fallbackPickup : label;
  }

  String _cleanPickupText(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return '';
    if (text.toLowerCase() == 'null') return '';
    return text;
  }

  bool _looksLikeCoordinates(String value) {
    final s = value.trim();
    return RegExp(r'^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$').hasMatch(s);
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
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
      return '$minutes min';
    }
  }
}
