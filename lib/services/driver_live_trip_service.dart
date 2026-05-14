import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import '../controllers/driver_proximity_controller.dart';
import '../models/driver_status.dart';
import '../models/route.dart';
import '../models/schedule_slot.dart';
import 'route_driver_queue_service.dart';
import 'slot_driver_assignment_service.dart';

class DriverLiveTripService {
  DriverLiveTripService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance,
      _queueSvc = RouteDriverQueueService(firestore: firestore),
      _slotAssign = SlotDriverAssignmentService(firestore: firestore);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final RouteDriverQueueService _queueSvc;
  final SlotDriverAssignmentService _slotAssign;
  final DriverProximityController _proximityController =
      DriverProximityController();

  static const String _routesCollection = 'route';
  static const String _driversCollection = 'drivers';
  static const String _usersCollection = 'users';
  static const String _passengersCollection = 'passengers';

  String? get currentDriverId => _auth.currentUser?.uid;

  Future<void> startTrip({
    required String routeId,
    required String tripId,
    required String driverId,
    double? startLatitude,
    double? startLongitude,
  }) async {
    final safeTripId = tripId.trim();
    final safeDriverId = driverId.trim();

    if (safeTripId.isEmpty) {
      throw Exception('Trip ID is missing.');
    }

    if (safeDriverId.isEmpty) {
      throw Exception('Driver ID is missing.');
    }

    final resolvedRouteId = await _resolveRouteId(
      routeId: routeId,
      tripId: safeTripId,
    );

    if (resolvedRouteId.isEmpty) {
      throw Exception('Route ID is missing or trip was not found.');
    }

    final routeRef = _db.collection(_routesCollection).doc(resolvedRouteId);
    final driverRef = _db.collection(_driversCollection).doc(safeDriverId);

    final routeSnap = await routeRef.get();

    if (!routeSnap.exists) {
      throw Exception('Route not found.');
    }

    final routeData = routeSnap.data() ?? {};
    final rawScheduleSlots = routeData['scheduleSlots'];

    if (rawScheduleSlots is! List) {
      throw Exception('scheduleSlots is missing in this route.');
    }

    final List<Map<String, dynamic>> cleanSlots = [];

    for (final rawSlot in rawScheduleSlots) {
      if (rawSlot is Map) {
        cleanSlots.add(_cleanFirestoreMap(Map<String, dynamic>.from(rawSlot)));
      }
    }

    final index = cleanSlots.indexWhere(
      (slot) => (slot['slotId'] ?? '').toString().trim() == safeTripId,
    );

    if (index == -1) {
      throw Exception('Trip slot not found.');
    }

    final selectedSlot = Map<String, dynamic>.from(cleanSlots[index]);

    selectedSlot['slotId'] = safeTripId;
    selectedSlot['routeId'] = resolvedRouteId;
    selectedSlot['driverId'] = (selectedSlot['driverId'] ?? safeDriverId)
        .toString();
    selectedSlot['status'] = 'onTrip';
    selectedSlot['startedAt'] = Timestamp.now();

    cleanSlots[index] = selectedSlot;

    await routeRef.update({
      'scheduleSlots': cleanSlots,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final driverUpdate = <String, dynamic>{
      'status': DriverStatus.onTrip,
      'isOnline': true,
      'currentRouteId': resolvedRouteId,
      'currentTripId': safeTripId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (startLatitude != null && startLongitude != null) {
      driverUpdate['latitude'] = startLatitude;
      driverUpdate['longitude'] = startLongitude;
      driverUpdate['location'] = {'lat': startLatitude, 'lng': startLongitude};
      driverUpdate['lastLocationUpdate'] = FieldValue.serverTimestamp();
    }

    await driverRef.set(driverUpdate, SetOptions(merge: true));

  }

  Map<String, dynamic> _cleanFirestoreMap(Map<String, dynamic> map) {
    final clean = <String, dynamic>{};

    map.forEach((key, value) {
      if (key.trim().isEmpty) return;

      if (value == null) {
        clean[key] = '';
      } else if (value is Map) {
        clean[key] = _cleanFirestoreMap(Map<String, dynamic>.from(value));
      } else if (value is List) {
        clean[key] = value.map((item) {
          if (item == null) return '';
          if (item is Map) {
            return _cleanFirestoreMap(Map<String, dynamic>.from(item));
          }
          return item;
        }).toList();
      } else {
        clean[key] = value;
      }
    });

    return clean;
  }

  Future<void> completeTrip({
    required String routeId,
    required String tripId,
    required String driverId,
  }) async {
    final safeTripId = tripId.trim();
    final safeDriverId = driverId.trim();

    if (safeTripId.isEmpty) {
      throw Exception('Trip ID is missing.');
    }

    if (safeDriverId.isEmpty) {
      throw Exception('Driver ID is missing.');
    }

    final resolvedRouteId = await _resolveRouteId(
      routeId: routeId,
      tripId: safeTripId,
    );

    if (resolvedRouteId.isEmpty) {
      throw Exception('Route ID is missing or trip was not found.');
    }

    final routeRef = _db.collection(_routesCollection).doc(resolvedRouteId);
    final driverRef = _db.collection(_driversCollection).doc(safeDriverId);

    final routeSnap = await routeRef.get();

    if (!routeSnap.exists) {
      throw Exception('Route not found.');
    }

    final data = routeSnap.data() ?? {};
    final rawScheduleSlots = data['scheduleSlots'];

    if (rawScheduleSlots is! List) {
      throw Exception('scheduleSlots is missing in this route.');
    }

    final rawSlots = rawScheduleSlots
        .whereType<Map>()
        .map((e) => _cleanFirestoreMap(Map<String, dynamic>.from(e)))
        .toList();

    final index = rawSlots.indexWhere(
      (e) => (e['slotId'] ?? '').toString().trim() == safeTripId,
    );

    if (index == -1) {
      throw Exception('Trip slot not found.');
    }

    rawSlots[index]['status'] = 'completed';
    rawSlots[index]['routeId'] = (rawSlots[index]['routeId'] ?? resolvedRouteId)
        .toString();
    rawSlots[index]['completedAt'] = Timestamp.now();

    await routeRef.update({
      'scheduleSlots': rawSlots,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await driverRef.set({
      'status': DriverStatus.available,
      'updatedAt': FieldValue.serverTimestamp(),
      'currentRouteId': FieldValue.delete(),
      'currentTripId': FieldValue.delete(),
    }, SetOptions(merge: true));

    await _queueSvc.syncQueueWithOnlineAvailableDrivers(resolvedRouteId);
    await _slotAssign.autoAssignUpcomingUnassignedSlots(routeId: resolvedRouteId);
  }

  Future<void> cancelTrip({
    required String routeId,
    required String tripId,
    required String driverId,
  }) async {
    final safeTripId = tripId.trim();
    final safeDriverId = driverId.trim();

    if (safeTripId.isEmpty) {
      throw Exception('Trip ID is missing.');
    }

    if (safeDriverId.isEmpty) {
      throw Exception('Driver ID is missing.');
    }

    final resolvedRouteId = await _resolveRouteId(
      routeId: routeId,
      tripId: safeTripId,
    );

    if (resolvedRouteId.isEmpty) {
      throw Exception('Route ID is missing or trip was not found.');
    }

    final routeRef = _db.collection(_routesCollection).doc(resolvedRouteId);
    final driverRef = _db.collection(_driversCollection).doc(safeDriverId);

    final routeSnap = await routeRef.get();

    if (!routeSnap.exists) {
      throw Exception('Route not found.');
    }

    final data = routeSnap.data() ?? {};
    final rawScheduleSlots = data['scheduleSlots'];

    if (rawScheduleSlots is! List) {
      throw Exception('scheduleSlots is missing in this route.');
    }

    final rawSlots = rawScheduleSlots
        .whereType<Map>()
        .map((e) => _cleanFirestoreMap(Map<String, dynamic>.from(e)))
        .toList();

    final index = rawSlots.indexWhere(
      (e) => (e['slotId'] ?? '').toString().trim() == safeTripId,
    );

    if (index == -1) {
      throw Exception('Trip slot not found.');
    }

    rawSlots[index]['status'] = 'cancelled';
    rawSlots[index]['cancelledAt'] = Timestamp.now();

    await routeRef.update({
      'scheduleSlots': rawSlots,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await driverRef.set({
      'status': DriverStatus.available,
      'updatedAt': FieldValue.serverTimestamp(),
      'currentRouteId': FieldValue.delete(),
      'currentTripId': FieldValue.delete(),
    }, SetOptions(merge: true));

    await _queueSvc.syncQueueWithOnlineAvailableDrivers(resolvedRouteId);
    await _slotAssign.autoAssignUpcomingUnassignedSlots(routeId: resolvedRouteId);
  }

  Future<void> updateDriverLocation({
    required String driverId,
    required double latitude,
    required double longitude,
  }) async {
    final safeDriverId = driverId.trim();

    if (safeDriverId.isEmpty) {
      throw Exception('Driver ID is missing.');
    }

    await _db.collection(_driversCollection).doc(safeDriverId).set({
      'latitude': latitude,
      'longitude': longitude,
      'location': {'lat': latitude, 'lng': longitude},
      'lastLocationUpdate': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _proximityController.handleDriverLocationUpdate(
      driverId: safeDriverId,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Stream<Map<String, dynamic>?> watchLiveTrip({
    required String routeId,
    required String tripId,
  }) async* {
    final safeTripId = tripId.trim();

    if (safeTripId.isEmpty) {
      yield null;
      return;
    }

    final resolvedRouteId = await _resolveRouteId(
      routeId: routeId,
      tripId: safeTripId,
    );

    if (resolvedRouteId.isEmpty) {
      yield null;
      return;
    }

    yield* _db
        .collection(_routesCollection)
        .doc(resolvedRouteId)
        .snapshots()
        .asyncMap((routeSnap) async {
          if (!routeSnap.exists) return null;

          final routeData = routeSnap.data() ?? {};
          final routeMap = Map<String, dynamic>.from(routeData);
          routeMap['routeId'] = (routeMap['routeId'] ?? routeSnap.id)
              .toString();

          final RouteModel route = RouteModel.fromMap(routeMap);

          final rawSlots = routeData['scheduleSlots'];
          if (rawSlots is! List) return null;

          ScheduleSlot? slot;

          for (int i = 0; i < rawSlots.length; i++) {
            final raw = rawSlots[i];
            if (raw is! Map) continue;

            final map = Map<String, dynamic>.from(raw);
            final candidate = ScheduleSlot.fromMap('slot_$i', map);

            if (candidate.slotId.trim() == safeTripId) {
              slot = ScheduleSlot(
                slotId: candidate.slotId,
                routeId: candidate.routeId.isEmpty
                    ? route.routeId
                    : candidate.routeId,
                departureAt: candidate.departureAt,
                arrivalAt: candidate.arrivalAt,
                price: candidate.price,
                capacity: candidate.capacity,
                vehicleType: candidate.vehicleType,
                driverId: candidate.driverId,
                passengersIds: List<String>.from(candidate.passengersIds),
                frequencyMinutes: candidate.frequencyMinutes,
                status: (map['status'] ?? candidate.status).toString(),
              );
              break;
            }
          }

          if (slot == null) return null;

          final driverName = await getDriverName(slot.driverId);
          final driverLocation = await getDriverLocation(slot.driverId);
          final passengers = await _getPassengers(slot.passengersIds);

          final startLat = _readLatitude(routeData, 'start');
          final startLng = _readLongitude(routeData, 'start');
          final endLat = _readLatitude(routeData, 'end');
          final endLng = _readLongitude(routeData, 'end');
          final routePolyline =
              (routeData['polyline'] ?? routeData['routePolyline'] ?? '')
                  .toString();

          return {
            'resolvedRouteId': resolvedRouteId,
            'route': route,
            'slot': slot,
            'driverName': driverName,
            'driverLocation': driverLocation,
            'passengers': passengers,
            'startLat': startLat,
            'startLng': startLng,
            'endLat': endLat,
            'endLng': endLng,
            'polyline': routePolyline,
            'routePolyline': routePolyline,
            'etaMinutes': routeData['etaMinutes'],
            'etaText': routeData['etaText'],
          };
        });
  }

  Future<String> _resolveRouteId({
    required String routeId,
    required String tripId,
  }) async {
    final safeRouteId = routeId.trim();
    final safeTripId = tripId.trim();

    if (safeRouteId.isNotEmpty) {
      return safeRouteId;
    }

    if (safeTripId.isEmpty) {
      return '';
    }

    final snapshot = await _db.collection(_routesCollection).get();

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final rawSlots = data['scheduleSlots'];

      if (rawSlots is! List) continue;

      for (final raw in rawSlots) {
        if (raw is! Map) continue;

        final slotId = (raw['slotId'] ?? '').toString().trim();

        if (slotId == safeTripId) {
          return doc.id;
        }
      }
    }

    return '';
  }

  Future<String> getDriverName(String driverId) async {
    final safeDriverId = driverId.trim();

    if (safeDriverId.isEmpty) return 'Driver';

    final userDoc = await _db
        .collection(_usersCollection)
        .doc(safeDriverId)
        .get();

    if (!userDoc.exists) return 'Driver';

    final data = userDoc.data() ?? {};
    final first = (data['firstName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    final full = '$first $last'.trim();

    return full.isEmpty ? 'Driver' : full;
  }

  Future<Map<String, double>?> getDriverLocation(String driverId) async {
    final safeDriverId = driverId.trim();

    if (safeDriverId.isEmpty) return null;

    final doc = await _db
        .collection(_driversCollection)
        .doc(safeDriverId)
        .get();

    if (doc.exists) {
      final fromDriver = _extractLatLng(doc.data() ?? {});
      if (fromDriver != null) return fromDriver;
    }

    return null;
  }

  Stream<Map<String, double>?> watchDriverDocumentLocation(String driverId) {
    final id = driverId.trim();

    if (id.isEmpty) return Stream.value(null);

    return _db.collection(_driversCollection).doc(id).snapshots().map((snap) {
      return _extractLatLng(snap.data() ?? {});
    });
  }

  Stream<List<Map<String, dynamic>>> watchAssignedPassengerPins(
    List<String> passengerIds,
  ) {
    final ids = passengerIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (ids.isEmpty) return Stream.value(const []);

    final subs = <StreamSubscription<DocumentSnapshot>>[];
    final cache = <String, Map<String, dynamic>>{};

    late StreamController<List<Map<String, dynamic>>> controller;

    void emit() {
      final ordered = <Map<String, dynamic>>[];

      for (final id in ids) {
        final row = cache[id];
        if (row != null) ordered.add(row);
      }

      if (!controller.isClosed) controller.add(ordered);
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
      },
    );

    for (final id in ids) {
      subs.add(
        _db.collection(_passengersCollection).doc(id).snapshots().listen((
          snap,
        ) async {
          final passengerData = snap.data() ?? <String, dynamic>{};
          final row = await _passengerPinRow(
            passengerId: id,
            passengerData: passengerData,
          );
          cache[id] = row;
          emit();
        }),
      );
    }

    return controller.stream;
  }

  Future<Map<String, dynamic>> _passengerPinRow({
    required String passengerId,
    required Map<String, dynamic> passengerData,
  }) async {
    final userSnap = await _db
        .collection(_usersCollection)
        .doc(passengerId)
        .get();

    final userData = userSnap.data() ?? {};

    final first = (userData['firstName'] ?? '').toString().trim();
    final last = (userData['lastName'] ?? '').toString().trim();
    final fullName = '$first $last'.trim();

    final pickup = (passengerData['pickupLocationDescription'] ?? '')
        .toString()
        .trim();

    final coords = _extractLatLng(passengerData);

    return {
      'userId': passengerId,
      'name': fullName.isEmpty ? 'Passenger' : fullName,
      'pickup': pickup.isEmpty ? 'Unknown pickup' : pickup,
      'latitude': coords?['lat'],
      'longitude': coords?['lng'],
    };
  }

  Future<List<Map<String, dynamic>>> _getPassengers(
    List<String> passengerIds,
  ) async {
    final result = <Map<String, dynamic>>[];

    for (final rawPassengerId in passengerIds) {
      final passengerId = rawPassengerId.trim();

      if (passengerId.isEmpty) continue;

      final passengerSnap = await _db
          .collection(_passengersCollection)
          .doc(passengerId)
          .get();

      result.add(
        await _passengerPinRow(
          passengerId: passengerId,
          passengerData: passengerSnap.data() ?? {},
        ),
      );
    }

    return result;
  }

  Map<String, double>? _extractLatLng(Map<String, dynamic> data) {
    final directLat =
        _toDouble(data['latitude']) ??
        _toDouble(data['lat']) ??
        _toDouble(data['currentLat']);

    final directLng =
        _toDouble(data['longitude']) ??
        _toDouble(data['lng']) ??
        _toDouble(data['currentLng']);

    if (directLat != null && directLng != null) {
      return {'lat': directLat, 'lng': directLng};
    }

    final location = data['location'];
    if (location is Map) {
      final lat = _toDouble(location['lat']) ?? _toDouble(location['latitude']);
      final lng =
          _toDouble(location['lng']) ?? _toDouble(location['longitude']);

      if (lat != null && lng != null) {
        return {'lat': lat, 'lng': lng};
      }
    }

    final liveLocation = data['liveLocation'];
    if (liveLocation is Map) {
      final lat =
          _toDouble(liveLocation['lat']) ?? _toDouble(liveLocation['latitude']);
      final lng =
          _toDouble(liveLocation['lng']) ??
          _toDouble(liveLocation['longitude']);

      if (lat != null && lng != null) {
        return {'lat': lat, 'lng': lng};
      }
    }

    return null;
  }

  double? _readLatitude(Map<String, dynamic> routeData, String prefix) {
    return _toDouble(routeData['${prefix}Lat']) ??
        _toDouble(routeData['${prefix}Latitude']) ??
        _nestedLocationValue(routeData['${prefix}Location'], 'lat') ??
        _nestedLocationValue(routeData['${prefix}Location'], 'latitude');
  }

  double? _readLongitude(Map<String, dynamic> routeData, String prefix) {
    return _toDouble(routeData['${prefix}Lng']) ??
        _toDouble(routeData['${prefix}Longitude']) ??
        _nestedLocationValue(routeData['${prefix}Location'], 'lng') ??
        _nestedLocationValue(routeData['${prefix}Location'], 'longitude');
  }

  double? _nestedLocationValue(dynamic value, String key) {
    if (value is GeoPoint) {
      if (key == 'lat' || key == 'latitude') return value.latitude;
      if (key == 'lng' || key == 'longitude') return value.longitude;
    }
    if (value is Map) {
      return _toDouble(value[key]);
    }

    return null;
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
    final price = slot.price ?? route.price;
    return '${price.toStringAsFixed(2)} NIS';
  }

  String toText(RouteModel route) {
    return route.endPoint.trim().isEmpty
        ? 'Unknown destination'
        : route.endPoint;
  }

  String pathText(RouteModel route) {
    return lineText(route);
  }

  String etaText({
    required Map<String, double>? from,
    required double? toLat,
    required double? toLng,
  }) {
    if (from == null || toLat == null || toLng == null) return '--';

    final meters = Geolocator.distanceBetween(
      from['lat']!,
      from['lng']!,
      toLat,
      toLng,
    );

    final minutes = (meters / 1000 / 30 * 60).round();

    if (minutes <= 1) return '1 min';

    return '$minutes min';
  }
}
