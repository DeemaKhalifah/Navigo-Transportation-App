import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/schedule_slot.dart';
import '../models/trip_status.dart';
import '../services/driver_live_trip_service.dart';
import '../services/driver_trips_service.dart';

/// Manages driver home screen business logic:
/// trip watching, live tracking, GPS publishing, and trip ending.
class DriverHomeController extends ChangeNotifier {
  final DriverTripsService _tripsService = DriverTripsService();
  final DriverLiveTripService _liveService = DriverLiveTripService();

  String driverName = 'Driver';
  int assignedTripsCount = 0;
  int onTripCount = 0;
  int passengersOnMap = 0;

  ScheduleSlot? activeSlot;
  String? activeRouteId;
  String? etaText;
  String? tripLine;
  bool isEndingTrip = false;

  List<Map<String, dynamic>> passengerPins = [];

  StreamSubscription? _tripsSub;

  Future<void> loadDriverName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final first = (doc.data()?['firstName'] ?? '').toString().trim();
      final last = (doc.data()?['lastName'] ?? '').toString().trim();
      final name = '$first $last'.trim();
      driverName = name.isNotEmpty ? name : 'Driver';
      notifyListeners();
    } catch (_) {}
  }

  void watchTrips({
    required Function(ScheduleSlot?) onActiveSlotChanged,
  }) {
    _tripsSub = _tripsService.watchDriverTrips().listen((trips) {
      final scheduled = trips
          .where((t) => _tripsService.statusOf(t) == TripStatus.scheduled)
          .length;
      final onTripSlots = trips
          .where((t) => _tripsService.statusOf(t) == TripStatus.onTrip)
          .toList();

      assignedTripsCount = scheduled + onTripSlots.length;
      onTripCount = onTripSlots.length;
      notifyListeners();

      final newActive = onTripSlots.isNotEmpty ? onTripSlots.first : null;
      onActiveSlotChanged(newActive);
    });
  }

  Future<void> endTrip() async {
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null || activeSlot == null) return;

    isEndingTrip = true;
    notifyListeners();

    try {
      await _liveService.completeTrip(
        routeId: activeRouteId ?? '',
        tripId: activeSlot!.slotId,
        driverId: driverId,
      );
      activeSlot = null;
      activeRouteId = null;
      tripLine = null;
      etaText = null;
      passengerPins = [];
    } finally {
      isEndingTrip = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _tripsSub?.cancel();
    super.dispose();
  }
}
