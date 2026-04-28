import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/schedule_slot.dart';
import '../models/trip_status.dart';

class PassengerScheduleService {
  PassengerScheduleService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const String _routesCollection = 'route';

  final Map<String, String> _lineBySlotKey = {};
  final Map<String, String> _fromBySlotKey = {};
  final Map<String, String> _toBySlotKey = {};
  final Map<String, int> _availableSeatsBySlotKey = {};
  final Map<String, String> _statusBySlotKey = {};

  String? get currentUserId => _auth.currentUser?.uid;

  Future<List<ScheduleSlot>> findAvailableSchedules({
    String? selectedLine,
    String? vehicleType,
    DateTime? selectedDate,
    TimeOfDay? selectedTime,
  }) async {
    final snapshot = await _db.collection(_routesCollection).get();

    final String normalizedLine = (selectedLine ?? '').trim().toLowerCase();
    final String normalizedVehicle = (vehicleType ?? '').trim().toLowerCase();

    final List<ScheduleSlot> candidates = [];
    final now = DateTime.now();

    _lineBySlotKey.clear();
    _fromBySlotKey.clear();
    _toBySlotKey.clear();
    _availableSeatsBySlotKey.clear();
    _statusBySlotKey.clear();

    for (final doc in snapshot.docs) {
      final data = doc.data();

      final String routeId = doc.id;
      final String fromText = (data['startPoint'] ?? data['from'] ?? '')
          .toString()
          .trim();
      final String toText = (data['endPoint'] ?? data['to'] ?? '')
          .toString()
          .trim();
      final String lineText =
          (data['line'] ??
                  data['routeName'] ??
                  (fromText.isNotEmpty && toText.isNotEmpty
                      ? '$fromText ↔ $toText'
                      : 'Route $routeId'))
              .toString()
              .trim();

      if (normalizedLine.isNotEmpty &&
          !lineText.toLowerCase().contains(normalizedLine)) {
        continue;
      }

      final List<ScheduleSlot> routeSlots = await _loadRouteSlots(
        routeId,
        data,
      );

      for (final slot in routeSlots) {
        final resolvedStatus = _resolveStatus(
          rawStatus: slot.status,
          departureAt: slot.departureAt,
          arrivalAt: slot.arrivalAt,
          now: now,
        );
        if (resolvedStatus != TripStatus.scheduled) continue;
        if (slot.departureAt.isBefore(now)) continue;

        if (normalizedVehicle.isNotEmpty &&
            slot.vehicleType.toLowerCase() != normalizedVehicle &&
            !slot.vehicleType.toLowerCase().contains(normalizedVehicle)) {
          continue;
        }

        final int availableSeats = slot.capacity - slot.passengersIds.length;
        if (availableSeats <= 0) continue;

        final ScheduleSlot fixedSlot = ScheduleSlot(
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
          status: resolvedStatus,
        );

        candidates.add(fixedSlot);

        final slotKey = _slotKey(fixedSlot.routeId, fixedSlot.slotId);
        _lineBySlotKey[slotKey] = lineText.isEmpty
            ? 'Route ${fixedSlot.routeId}'
            : lineText;
        _fromBySlotKey[slotKey] = fromText.isEmpty ? 'Unknown start' : fromText;
        _toBySlotKey[slotKey] = toText.isEmpty ? 'Unknown destination' : toText;
        _availableSeatsBySlotKey[slotKey] = availableSeats;
        _statusBySlotKey[slotKey] = resolvedStatus;
      }
    }

    candidates.sort((a, b) => a.departureAt.compareTo(b.departureAt));

    final bool noFilters =
        normalizedLine.isEmpty &&
        normalizedVehicle.isEmpty &&
        selectedDate == null &&
        selectedTime == null;

    if (noFilters) return candidates;

    List<ScheduleSlot> filtered = candidates;

    if (selectedDate != null) {
      filtered = filtered.where((slot) {
        return slot.departureAt.year == selectedDate.year &&
            slot.departureAt.month == selectedDate.month &&
            slot.departureAt.day == selectedDate.day;
      }).toList();
    }

    if (selectedTime == null) {
      return filtered;
    }

    final List<ScheduleSlot> exactMatches = filtered.where((slot) {
      return slot.departureAt.hour == selectedTime.hour &&
          slot.departureAt.minute == selectedTime.minute;
    }).toList();

    if (exactMatches.isNotEmpty) {
      return exactMatches;
    }

    final int selectedMinutes = selectedTime.hour * 60 + selectedTime.minute;

    final List<ScheduleSlot> nearestMatches = filtered.where((slot) {
      final int slotMinutes =
          slot.departureAt.hour * 60 + slot.departureAt.minute;
      final int diff = (slotMinutes - selectedMinutes).abs();
      return diff <= 60;
    }).toList();

    nearestMatches.sort((a, b) {
      final int aMinutes = a.departureAt.hour * 60 + a.departureAt.minute;
      final int bMinutes = b.departureAt.hour * 60 + b.departureAt.minute;
      final int aDiff = (aMinutes - selectedMinutes).abs();
      final int bDiff = (bMinutes - selectedMinutes).abs();
      return aDiff.compareTo(bDiff);
    });

    return nearestMatches;
  }

  Future<void> confirmSchedule({
    required ScheduleSlot slot,
    required int seatsToBook,
    String? pickupLocationDescription,
  }) async {
    final uid = currentUserId;
    if (uid == null) {
      throw Exception('User is not logged in.');
    }

    if (seatsToBook <= 0) {
      throw Exception('Please select at least 1 seat.');
    }

    final routeRef = _db.collection(_routesCollection).doc(slot.routeId);
    final subSlotRef = routeRef.collection('scheduleSlots').doc(slot.slotId);

    await _db.runTransaction((tx) async {
      final subSnap = await tx.get(subSlotRef);
      if (subSnap.exists) {
        final subData = subSnap.data() as Map<String, dynamic>;
        final currentSlot = ScheduleSlot.fromMap(slot.slotId, subData);
        final availableSeats =
            currentSlot.capacity - currentSlot.passengersIds.length;
        if (seatsToBook > availableSeats) {
          throw Exception(
            'Only $availableSeats seat(s) are available for this schedule.',
          );
        }

        final updatedPassengers = List<Map<String, dynamic>>.from(
          currentSlot.passengerBookings,
        );
        final pickup = (pickupLocationDescription ?? '').trim();
        for (int i = 0; i < seatsToBook; i++) {
          updatedPassengers.add({
            'passengerId': uid,
            'pickupLocationDescription': pickup,
          });
        }

        tx.update(subSlotRef, {
          'passengersIds': updatedPassengers,
          'status': TripStatus.scheduled,
        });
        return;
      }

      final snap = await tx.get(routeRef);
      if (!snap.exists) {
        throw Exception('Route not found.');
      }

      final data = snap.data() as Map<String, dynamic>;
      final rawList = (data['scheduleSlots'] as List? ?? []);
      final List<Map<String, dynamic>> scheduleSlots = rawList
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final index = scheduleSlots.indexWhere((item) {
        return (item['slotId'] ?? '').toString() == slot.slotId;
      });
      if (index == -1) {
        throw Exception('Schedule slot not found.');
      }

      final currentMap = Map<String, dynamic>.from(scheduleSlots[index]);
      final currentSlot = ScheduleSlot.fromMap(slot.slotId, currentMap);
      final availableSeats =
          currentSlot.capacity - currentSlot.passengersIds.length;
      if (seatsToBook > availableSeats) {
        throw Exception(
          'Only $availableSeats seat(s) are available for this schedule.',
        );
      }

      final updatedPassengers = List<Map<String, dynamic>>.from(
        currentSlot.passengerBookings,
      );
      final pickup = (pickupLocationDescription ?? '').trim();
      for (int i = 0; i < seatsToBook; i++) {
        updatedPassengers.add({
          'passengerId': uid,
          'pickupLocationDescription': pickup,
        });
      }

      currentMap['passengersIds'] = updatedPassengers;
      currentMap['status'] = TripStatus.scheduled;
      scheduleSlots[index] = currentMap;
      tx.update(routeRef, {'scheduleSlots': scheduleSlots});
    });
  }

  ScheduleSlot applyLocalBooking({
    required ScheduleSlot slot,
    required int seatsBooked,
    required String? userId,
    String? pickupLocationDescription,
  }) {
    final uid = userId ?? currentUserId ?? '';

    final updatedPassengers = List<Map<String, dynamic>>.from(
      slot.passengerBookings,
    );
    final pickup = (pickupLocationDescription ?? '').trim();
    for (int i = 0; i < seatsBooked; i++) {
      updatedPassengers.add({
        'passengerId': uid,
        'pickupLocationDescription': pickup,
      });
    }

    final updatedSlot = ScheduleSlot(
      slotId: slot.slotId,
      routeId: slot.routeId,
      departureAt: slot.departureAt,
      arrivalAt: slot.arrivalAt,
      price: slot.price,
      capacity: slot.capacity,
      vehicleType: slot.vehicleType,
      driverId: slot.driverId,
      passengerBookings: updatedPassengers,
      frequencyMinutes: slot.frequencyMinutes,
      status: slot.status,
    );

    _availableSeatsBySlotKey[_slotKey(slot.routeId, slot.slotId)] =
        updatedSlot.capacity - updatedSlot.passengersIds.length;

    return updatedSlot;
  }

  String lineOf(ScheduleSlot slot) {
    return _lineBySlotKey[_slotKey(slot.routeId, slot.slotId)] ??
        'Route ${slot.routeId}';
  }

  String fromOf(ScheduleSlot slot) {
    return _fromBySlotKey[_slotKey(slot.routeId, slot.slotId)] ??
        'Unknown start';
  }

  String toOf(ScheduleSlot slot) {
    return _toBySlotKey[_slotKey(slot.routeId, slot.slotId)] ??
        'Unknown destination';
  }

  int availableSeatsOf(ScheduleSlot slot) {
    return _availableSeatsBySlotKey[_slotKey(slot.routeId, slot.slotId)] ??
        (slot.capacity - slot.passengersIds.length);
  }

  String statusOf(ScheduleSlot slot) {
    return _statusBySlotKey[_slotKey(slot.routeId, slot.slotId)] ??
        TripStatus.scheduled;
  }

  String _slotKey(String routeId, String slotId) => '$routeId::$slotId';

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

  Future<List<ScheduleSlot>> _loadRouteSlots(
    String routeId,
    Map<String, dynamic> routeData,
  ) async {
    final subSnap = await _db
        .collection(_routesCollection)
        .doc(routeId)
        .collection('scheduleSlots')
        .get();

    if (subSnap.docs.isNotEmpty) {
      return subSnap.docs.map((doc) {
        final map = doc.data();
        final slot = ScheduleSlot.fromMap(doc.id, map);
        return ScheduleSlot(
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
          status: slot.status,
        );
      }).toList();
    }

    final rawSlots = routeData['scheduleSlots'];
    if (rawSlots is! List) return <ScheduleSlot>[];

    final List<ScheduleSlot> slots = [];
    for (int i = 0; i < rawSlots.length; i++) {
      final raw = rawSlots[i];
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final slot = ScheduleSlot.fromMap('slot_$i', map);
      slots.add(
        ScheduleSlot(
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
          status: slot.status,
        ),
      );
    }
    return slots;
  }

  String priceTextOf(ScheduleSlot slot) {
    if (slot.price == null) return 'N/A';
    return '${slot.price!.toStringAsFixed(2)} NIS';
  }

  String vehicleTextOf(ScheduleSlot slot) {
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
