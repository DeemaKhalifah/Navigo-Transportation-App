import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/schedule_slot.dart';
import '../models/trip_status.dart';

class RouteSlotBookingService {
  RouteSlotBookingService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String routesCollection = 'route';

  Future<void> appendPassengerSeatsToSlot({
    required String routeId,
    required String slotId,
    required String passengerId,
    required int seatsToAdd,
  }) async {
    await _db.runTransaction((tx) async {
      await appendPassengerSeatsWithTransaction(
        tx,
        _db,
        routeId: routeId,
        slotId: slotId,
        passengerId: passengerId,
        seatsToAdd: seatsToAdd,
      );
    });
  }

  static Future<void> appendPassengerSeatsWithTransaction(
    Transaction tx,
    FirebaseFirestore db, {
    required String routeId,
    required String slotId,
    required String passengerId,
    required int seatsToAdd,
  }) async {
    final safeRoute = routeId.trim();
    final safeSlot = slotId.trim();
    final safePassenger = passengerId.trim();

    if (safeRoute.isEmpty) {
      throw Exception('Route ID is missing.');
    }
    if (safeSlot.isEmpty) {
      throw Exception('Schedule slot ID is missing.');
    }
    if (safePassenger.isEmpty) {
      throw Exception('Passenger ID is missing.');
    }
    if (seatsToAdd < 1) {
      throw Exception('At least one seat is required.');
    }

    final routeRef = db.collection(routesCollection).doc(safeRoute);
    final subSlotRef = routeRef.collection('scheduleSlots').doc(safeSlot);

    final subSnap = await tx.get(subSlotRef);
    if (subSnap.exists) {
      final raw = subSnap.data();
      if (raw is! Map) {
        throw Exception('Invalid schedule slot document.');
      }
      final subData = Map<String, dynamic>.from(raw as Map<dynamic, dynamic>);
      final current = ScheduleSlot.fromMap(safeSlot, subData);
      _assertCanAppend(
        current: current,
        passengerId: safePassenger,
        seatsToAdd: seatsToAdd,
      );

      final updated = List<Map<String, dynamic>>.from(current.passengerBookings);
      for (var i = 0; i < seatsToAdd; i++) {
        updated.add({
          'passengerId': safePassenger,
          'pickupLocationDescription': '',
        });
      }

      tx.update(subSlotRef, {
        'passengersIds': updated,
        'status': TripStatus.scheduled,
      });
      return;
    }

    final routeSnap = await tx.get(routeRef);
    if (!routeSnap.exists) {
      throw Exception('Route not found.');
    }

    final data = routeSnap.data() as Map<String, dynamic>;
    final rawList = data['scheduleSlots'];
    if (rawList is! List) {
      throw Exception('Route has no scheduleSlots array.');
    }

    final scheduleSlots = rawList
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final index = scheduleSlots.indexWhere(
      (item) => (item['slotId'] ?? '').toString().trim() == safeSlot,
    );
    if (index == -1) {
      throw Exception('Schedule slot not found on this route.');
    }

    final currentMap = Map<String, dynamic>.from(scheduleSlots[index]);
    final current = ScheduleSlot.fromMap(safeSlot, currentMap);

    _assertCanAppend(
      current: current,
      passengerId: safePassenger,
      seatsToAdd: seatsToAdd,
    );

    final updated = List<Map<String, dynamic>>.from(current.passengerBookings);
    for (var i = 0; i < seatsToAdd; i++) {
      updated.add({
        'passengerId': safePassenger,
        'pickupLocationDescription': '',
      });
    }

    currentMap['passengersIds'] = updated;
    currentMap['status'] = TripStatus.scheduled;
    scheduleSlots[index] = currentMap;

    tx.update(routeRef, {'scheduleSlots': scheduleSlots});
  }

  static void _assertCanAppend({
    required ScheduleSlot current,
    required String passengerId,
    required int seatsToAdd,
  }) {
    final available = current.capacity - current.passengersIds.length;
    if (seatsToAdd > available) {
      throw Exception('Not enough seats on this trip (only $available left).');
    }

    final existingCount = current.passengersIds
        .where((id) => id.trim() == passengerId)
        .length;
    if (existingCount > 0) {
      throw Exception('Passenger is already booked on this trip.');
    }
  }
}
