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
  static const String _driversCollection = 'drivers';
  static const String _usersCollection = 'users';
  static const String _vehiclesCollection = 'vehicles';

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

          final String finalStatus = _resolvePassengerTripStatus(
            rawStatus: map['status'],
            departureAt: slot.departureAt,
            arrivalAt: slot.arrivalAt,
            now: now,
          );

          final fixedSlot = ScheduleSlot(
            slotId: slot.slotId,
            routeId: slot.routeId.isEmpty ? routeId : slot.routeId,
            departureAt: slot.departureAt,
            arrivalAt: slot.arrivalAt,
            price: slot.price,
            capacity: slot.capacity,
            vehicleType: slot.vehicleType,
            driverId: slot.driverId,
            passengersIds: List<String>.from(slot.passengersIds),
            frequencyMinutes: slot.frequencyMinutes,
            status: finalStatus,
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

  String _resolvePassengerTripStatus({
    required dynamic rawStatus,
    required DateTime departureAt,
    required DateTime arrivalAt,
    required DateTime now,
  }) {
    final normalized = TripStatus.normalize(rawStatus?.toString());

    if (normalized == TripStatus.cancelled) {
      return TripStatus.cancelled;
    }

    if (normalized == TripStatus.onTrip) {
      return TripStatus.onTrip;
    }

    if (normalized == TripStatus.completed) {
      return TripStatus.completed;
    }

    if (normalized == TripStatus.scheduled) {
      return TripStatus.scheduled;
    }

    if (now.isBefore(departureAt)) {
      return TripStatus.scheduled;
    }

    if (now.isAfter(arrivalAt)) {
      return TripStatus.completed;
    }

    return TripStatus.onTrip;
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
    return _statusBySlotId[slot.slotId] ?? slot.status;
  }

  Future<int> cancelPassengerScheduledTrip(ScheduleSlot slot) async {
    final uid = currentUserId?.trim();
    if (uid == null || uid.isEmpty) {
      throw Exception('User is not logged in.');
    }

    final routeId = slot.routeId.trim();
    final slotId = slot.slotId.trim();
    if (routeId.isEmpty || slotId.isEmpty) {
      throw Exception('Schedule slot is missing route data.');
    }

    var removedSeats = 0;
    final routeRef = _db.collection(_routesCollection).doc(routeId);
    final subSlotRef = routeRef.collection('scheduleSlots').doc(slotId);

    await _db.runTransaction((tx) async {
      final routeSnap = await tx.get(routeRef);
      final subSnap = await tx.get(subSlotRef);

      if (!routeSnap.exists) {
        throw Exception('Route not found.');
      }

      final routeData = routeSnap.data() as Map<String, dynamic>;
      final rawList = routeData['scheduleSlots'];
      var changedArray = false;
      List<dynamic> scheduleSlots = [];

      if (rawList is List) {
        scheduleSlots = List<dynamic>.from(rawList);

        final index = scheduleSlots.indexWhere(
          (item) =>
              item is Map &&
              (item['slotId'] ?? '').toString().trim() == slotId,
        );
        if (index != -1) {
          final currentMap = Map<String, dynamic>.from(
            scheduleSlots[index] as Map,
          );
          final updated = _removePassengerBookings(
            currentMap['passengersIds'],
            uid,
          );
          if (updated.removedCount > 0) {
            removedSeats = updated.removedCount;
            currentMap['passengersIds'] = updated.bookings;
            scheduleSlots[index] = currentMap;
            changedArray = true;
          }
        }
      }

      var changedSubDoc = false;
      Map<String, dynamic>? updatedSubData;
      if (subSnap.exists) {
        final subData = subSnap.data() ?? <String, dynamic>{};
        updatedSubData = Map<String, dynamic>.from(subData);
        final updated = _removePassengerBookings(
          updatedSubData['passengersIds'],
          uid,
        );
        if (updated.removedCount > 0) {
          removedSeats = removedSeats == 0 ? updated.removedCount : removedSeats;
          updatedSubData['passengersIds'] = updated.bookings;
          changedSubDoc = true;
        }
      }

      if (!changedArray && !changedSubDoc) {
        throw Exception('This passenger is not booked on this trip.');
      }

      if (changedArray) {
        tx.update(routeRef, {'scheduleSlots': scheduleSlots});
      }
      if (changedSubDoc && updatedSubData != null) {
        tx.update(subSlotRef, {
          'passengersIds': updatedSubData['passengersIds'],
        });
      }
    });

    return removedSeats;
  }

  _PassengerBookingRemoval _removePassengerBookings(
    dynamic rawBookings,
    String passengerId,
  ) {
    final current = ScheduleSlot.fromMap(
      'slot',
      {'passengersIds': rawBookings},
    ).passengerBookings;

    final updated = <Map<String, dynamic>>[];
    var removed = 0;

    for (final booking in current) {
      final id = (booking['passengerId'] ?? '').toString().trim();
      if (id == passengerId) {
        removed++;
        continue;
      }
      updated.add(Map<String, dynamic>.from(booking));
    }

    return _PassengerBookingRemoval(bookings: updated, removedCount: removed);
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

  Future<Map<String, String>> getDriverInfo(String driverId) async {
    String plateNumber = 'N/A';
    String phone = 'N/A';

    if (driverId.trim().isEmpty) {
      return {'plateNumber': plateNumber, 'phone': phone};
    }

    try {
      final driverSnap = await _db
          .collection(_driversCollection)
          .doc(driverId)
          .get();
      final driverData = driverSnap.data();
      if (driverData != null) {
        final vehicleId = (driverData['vehicleId'] ?? '').toString().trim();
        if (vehicleId.isNotEmpty) {
          final vehicleSnap = await _db
              .collection(_vehiclesCollection)
              .doc(vehicleId)
              .get();
          final vehicleData = vehicleSnap.data();
          if (vehicleData != null) {
            plateNumber = (vehicleData['plateNumber'] ?? 'N/A')
                .toString()
                .trim();
          }
        }

        final userId = (driverData['userId'] ?? driverId).toString().trim();
        if (userId.isNotEmpty) {
          final userSnap = await _db
              .collection(_usersCollection)
              .doc(userId)
              .get();
          final userData = userSnap.data();
          if (userData != null) {
            phone = (userData['phone'] ?? 'N/A').toString().trim();
          }
        }
      }
    } catch (_) {}

    return {'plateNumber': plateNumber, 'phone': phone};
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

class _PassengerBookingRemoval {
  const _PassengerBookingRemoval({
    required this.bookings,
    required this.removedCount,
  });

  final List<Map<String, dynamic>> bookings;
  final int removedCount;
}
