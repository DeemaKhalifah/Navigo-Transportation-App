import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/route.dart';
import '../models/schedule_slot.dart';
import '../models/driver_status.dart';
import '../models/trip_status.dart';

class PassengerTripRepository {
  PassengerTripRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const String _routeCollection = 'route';
  static const String _driversCollection = 'drivers';
  static const String _usersCollection = 'users';
  static const String _vehiclesCollection = 'vehicles';
  static const String _passengersCollection = 'passengers';

  String? get currentUserId => _auth.currentUser?.uid;

  static String buildLineLabel(RouteModel route) =>
      '${route.startPoint} <-----> ${route.endPoint}';

  Future<List<RouteModel>> fetchRoutes() async {
    final routes = <RouteModel>[];

    final snap = await _db.collection(_routeCollection).get();
    for (final doc in snap.docs) {
      final model = _routeFromDoc(doc.id, doc.data());
      if (model != null) {
        routes.add(model);
      }
    }

    routes.sort((a, b) => buildLineLabel(a).compareTo(buildLineLabel(b)));
    return routes;
  }

  RouteModel? _routeFromDoc(String docId, Map<String, dynamic> data) {
    final start =
        (data['startPoint'] ?? data['startpoint'] ?? data['from'] ?? '')
            .toString()
            .trim();

    final end = (data['endPoint'] ?? data['endpoint'] ?? data['to'] ?? '')
        .toString()
        .trim();

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
      if (buildLineLabel(route) == selectedLine) {
        return route;
      }
    }
    return null;
  }

  Stream<List<ScheduleSlot>> watchSlotsForRoute(String routeId) {
    return _db.collection(_routeCollection).doc(routeId).snapshots().map((
      snap,
    ) {
      final route = _routeFromDoc(routeId, snap.data() ?? <String, dynamic>{});
      if (route == null) return <ScheduleSlot>[];

      final slots = [...route.scheduleSlots];
      slots.sort((a, b) => a.departureAt.compareTo(b.departureAt));
      return slots;
    });
  }

  static ScheduleSlot? selectActiveTripSlotForDriver(
    RouteModel route,
    String driverDocId,
  ) {
    final now = DateTime.now();
    final candidates = <ScheduleSlot>[];

    for (final slot in route.scheduleSlots) {
      if (slot.driverId.trim() != driverDocId.trim()) continue;

      final status = TripStatus.normalize(slot.status);
      if (status != TripStatus.onTrip) continue;
      if (slot.arrivalAt.isBefore(now)) continue;

      final availableSeats = slot.capacity - slot.passengersIds.length;
      if (availableSeats < 1) continue;

      candidates.add(slot);
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => a.departureAt.compareTo(b.departureAt));
    return candidates.first;
  }

  Future<List<Map<String, dynamic>>> getDriversForLine(
    String selectedLine,
  ) async {
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
        .collection(_driversCollection)
        .where('isApproved', isEqualTo: true)
        .get();

    final drivers = <Map<String, dynamic>>[];

    for (final driverDoc in driversSnap.docs) {
      final driverData = driverDoc.data();
      final routeId = (driverData['routeId'] ?? '').toString().trim();
      final route = routesById[routeId];

      if (route == null) continue;
      final driverStatus = DriverStatus.normalize(
        driverData['status']?.toString(),
      );
      if (driverStatus != DriverStatus.onTrip) continue;

      final userId = (driverData['userId'] ?? driverDoc.id).toString();
      final userSnap = await _db.collection(_usersCollection).doc(userId).get();

      final vehicleId = (driverData['vehicleId'] ?? '').toString().trim();
      final vehicleSnap = vehicleId.isEmpty
          ? null
          : await _db.collection(_vehiclesCollection).doc(vehicleId).get();

      final location = await _resolveDriverLocation(driverDoc.id);
      if (location == null) continue;

      final offerSlot = selectActiveTripSlotForDriver(route, driverDoc.id);
      if (offerSlot == null) continue;

      final availableSeats =
          offerSlot.capacity - offerSlot.passengersIds.length;

      final userMap = userSnap.data() ?? <String, dynamic>{};
      final vehicleMap = (vehicleSnap != null && vehicleSnap.exists)
          ? vehicleSnap.data() ?? {}
          : {};

      final driverName =
          '${userMap['firstName'] ?? ''} ${userMap['lastName'] ?? ''}'.trim();

      drivers.add({
        'id': driverDoc.id,
        'routeId': route.routeId,
        'slotId': offerSlot.slotId,
        'scheduleId': offerSlot.slotId,
        'name': driverName.isEmpty
            ? 'Driver ${driverDoc.id.substring(0, 6)}'
            : driverName,
        'busNumber': vehicleMap['plateNumber']?.toString() ?? 'N/A',
        'line': buildLineLabel(route),
        'from': route.startPoint,
        'to': route.endPoint,
        'availableSeats': availableSeats,
        'price': '${route.price.toStringAsFixed(0)} NIS',
        'eta': offerSlot.etaText ?? route.etaText ?? 'Live',
        'etaMinutes': offerSlot.etaMinutes ?? route.etaMinutes,
        'phone': userMap['phone']?.toString() ?? 'N/A',
        'vehicleType': vehicleMap['type']?.toString() ?? 'Bus',
        'lat': location.latitude,
        'lng': location.longitude,
      });
    }

    return drivers;
  }

  Future<LatLng?> _resolveDriverLocation(String driverId) async {
    final driverSnap = await _db
        .collection(_driversCollection)
        .doc(driverId)
        .get();
    final data = driverSnap.data();
    if (data == null) return null;

    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();

    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }

    return _latLngFromMap(data['location']);
  }

  Future<LatLng?> getSavedPassengerLocation() async {
    final uid = currentUserId;
    if (uid == null || uid.trim().isEmpty) return null;

    final passengerSnap = await _db
        .collection(_passengersCollection)
        .doc(uid)
        .get();

    final data = passengerSnap.data();
    if (data == null) return null;

    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();

    if (lat != null && lng != null) {
      return LatLng(lat, lng);
    }

    return null;
  }

  static LatLng? _latLngFromMap(dynamic location) {
    if (location is GeoPoint) {
      return LatLng(location.latitude, location.longitude);
    }
    if (location is! Map) return null;

    final lat =
        (location['lat'] as num?)?.toDouble() ??
        (location['latitude'] as num?)?.toDouble();
    final lng =
        (location['lng'] as num?)?.toDouble() ??
        (location['longitude'] as num?)?.toDouble();

    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  Future<void> syncPassengerDocumentLocation(
    LatLng location, {
    String? pickupLocationDescription,
  }) async {
    final uid = currentUserId;
    if (uid == null || uid.trim().isEmpty) return;

    final passengerPayload = <String, dynamic>{
      'latitude': location.latitude,
      'longitude': location.longitude,
      'lastLocationUpdate': FieldValue.serverTimestamp(),
    };

    final trimmedPickup = pickupLocationDescription?.trim();
    if (trimmedPickup != null && trimmedPickup.isNotEmpty) {
      passengerPayload['pickupLocationDescription'] = trimmedPickup;
    }

    await _db
        .collection(_passengersCollection)
        .doc(uid)
        .set(passengerPayload, SetOptions(merge: true));
  }

  Future<void> syncPassengerLiveLocation(LatLng location) async {
    await syncPassengerDocumentLocation(location);
  }

  Future<void> savePassengerLocation(LatLng location) async {
    await syncPassengerDocumentLocation(location);
  }
}
