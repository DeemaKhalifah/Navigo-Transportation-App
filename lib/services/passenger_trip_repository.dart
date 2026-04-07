import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/GpsService.dart';
import '../models/route.dart';
import '../models/schedule_slot.dart';

class PassengerTripRepository {
  PassengerTripRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const Map<String, LatLng> _manualDriverLocations = {
    'aVafrXloEIfQOkLlfOnccAj9zAJ2': LatLng(31.9522, 35.2058),
    'BmjHy6Dm7pdiJNtgPKEt9a9i6Vp1': LatLng(32.2207, 35.2556),
  };

  static String buildLineLabel(RouteModel route) =>
      '${route.startPoint} <-----> ${route.endPoint}';

  Future<List<RouteModel>> fetchRoutes() async {
    final routes = <RouteModel>[];

    final snap = await _db.collection('route').get();
    for (final doc in snap.docs) {
      final model = _routeFromDoc(doc.id, doc.data());
      if (model != null) routes.add(model);
    }

    if (routes.isEmpty) {
      final altSnap = await _db.collection('routes').get();
      for (final doc in altSnap.docs) {
        final model = _routeFromDoc(doc.id, doc.data());
        if (model != null) routes.add(model);
      }
    }

    routes.sort((a, b) => buildLineLabel(a).compareTo(buildLineLabel(b)));
    return routes;
  }

  RouteModel? _routeFromDoc(String docId, Map<String, dynamic> data) {
    final start = (data['startPoint'] ?? data['startpoint'] ?? data['from'] ?? '')
        .toString()
        .trim();
    final end =
        (data['endPoint'] ?? data['endpoint'] ?? data['to'] ?? '').toString().trim();
    if (start.isEmpty || end.isEmpty) return null;

    return RouteModel.fromMap({
      ...data,
      'routeId': (data['routeId'] ?? docId).toString(),
      'startPoint': start,
      'endPoint': end,
    });
  }

  Future<RouteModel?> getRouteForLine(String selectedLine) async {
    final routes = await fetchRoutes();
    for (final route in routes) {
      if (buildLineLabel(route) == selectedLine) return route;
    }
    return null;
  }

  Stream<List<ScheduleSlot>> watchSlotsForRoute(String routeId) {
    return _db.collection('route').doc(routeId).snapshots().map((snap) {
      final route = _routeFromDoc(routeId, snap.data() ?? <String, dynamic>{});
      if (route == null) return <ScheduleSlot>[];
      final slots = [...route.scheduleSlots];
      slots.sort((a, b) => a.departureAt.compareTo(b.departureAt));
      return slots;
    });
  }

  Future<void> ensureManualDriverLocations() async {
    final batch = _db.batch();
    for (final entry in _manualDriverLocations.entries) {
      final gps = GpsService(
        tripId: 'driver_${entry.key}',
        driverId: entry.key,
        driverLocation: {
          'lat': entry.value.latitude,
          'lng': entry.value.longitude,
        },
        passengerId: '',
        passengerLocation: const <String, double>{},
        timestamp: DateTime.now(),
        routeId: null,
      );
      batch.set(_db.collection('gps').doc(entry.key), {
        ...gps.toMap(),
        'isManual': true,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> getDriversForLine(String selectedLine) async {
    final route = await getRouteForLine(selectedLine);
    if (route == null) return [];

    return _getDriversByRouteMap({route.routeId: route});
  }

  Future<List<Map<String, dynamic>>> getAllDrivers() async {
    final routes = await fetchRoutes();
    final routesById = {for (final route in routes) route.routeId: route};
    return _getDriversByRouteMap(routesById);
  }

  Future<List<Map<String, dynamic>>> _getDriversByRouteMap(
    Map<String, RouteModel> routesById,
  ) async {
    final driversSnap = await _db
        .collection('drivers')
        .where('isApproved', isEqualTo: true)
        .get();

    final drivers = <Map<String, dynamic>>[];

    for (final driverDoc in driversSnap.docs) {
      final driverData = driverDoc.data();
      final routeId = driverData['routeId']?.toString() ?? '';
      final route = routesById[routeId];
      if (route == null) continue;

      final userId = (driverData['userId'] ?? driverDoc.id).toString();
      final userSnap = await _db.collection('users').doc(userId).get();

      final vehicleId = driverData['vehicleId']?.toString() ?? '';
      final vehicleSnap = vehicleId.isEmpty
          ? null
          : await _db.collection('vehicles').doc(vehicleId).get();

      final location = await _resolveDriverLocation(driverDoc.id);
      if (location == null) continue;

      final userMap = userSnap.data() ?? <String, dynamic>{};
      final vehicleMap =
          (vehicleSnap != null && vehicleSnap.exists) ? vehicleSnap.data() ?? {} : {};

      final name =
          '${userMap['firstName'] ?? ''} ${userMap['lastName'] ?? ''}'.trim();

      drivers.add({
        'id': driverDoc.id,
        'name': name.isEmpty ? 'Driver ${driverDoc.id.substring(0, 6)}' : name,
        'busNumber': vehicleMap['plateNumber']?.toString() ?? 'N/A',
        'line': buildLineLabel(route),
        'from': route.startPoint,
        'to': route.endPoint,
        'availableSeats': (vehicleMap['seatCount'] as num?)?.toInt() ?? 4,
        'price': '${route.price.toStringAsFixed(0)} NIS',
        'eta': 'Live',
        'phone': userMap['phone']?.toString() ?? 'N/A',
        'vehicleType': vehicleMap['type']?.toString() ?? 'Bus',
        'lat': location.latitude,
        'lng': location.longitude,
      });
    }

    return drivers;
  }

  Future<LatLng?> _resolveDriverLocation(String driverId) async {
    if (_manualDriverLocations.containsKey(driverId)) {
      return _manualDriverLocations[driverId];
    }

    final gpsSnap = await _db.collection('gps').doc(driverId).get();
    final gpsMap = gpsSnap.data();
    if (gpsMap == null) return null;

    final location = gpsMap['driverLocation'];
    if (location is! Map) return null;

    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  Future<LatLng?> getSavedPassengerLocation() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final gpsSnap = await _db.collection('gps').doc(uid).get();
    final location = gpsSnap.data()?['passengerLocation'];
    if (location is! Map) return null;

    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  Future<void> savePassengerLocation(LatLng location) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final gps = GpsService(
      tripId: 'passenger_$uid',
      driverId: '',
      driverLocation: const <String, double>{},
      passengerId: uid,
      passengerLocation: {
        'lat': location.latitude,
        'lng': location.longitude,
      },
      timestamp: DateTime.now(),
      routeId: null,
    );

    await _db.collection('gps').doc(uid).set(gps.toMap(), SetOptions(merge: true));
  }
}