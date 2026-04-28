import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/proximity_distance_service.dart';
import '../services/proximity_notification_service.dart';

class DriverProximityController {
  DriverProximityController({
    FirebaseFirestore? firestore,
    ProximityDistanceService? distanceService,
    ProximityNotificationService? notificationService,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _distanceService = distanceService ?? const ProximityDistanceService(),
       _notificationService =
           notificationService ?? ProximityNotificationService();

  final FirebaseFirestore _db;
  final ProximityDistanceService _distanceService;
  final ProximityNotificationService _notificationService;

  static const double proximityRadiusMeters = 500;

  Future<void> handleDriverLocationUpdate({
    required String driverId,
    required double latitude,
    required double longitude,
  }) async {
    final safeDriverId = driverId.trim();
    if (safeDriverId.isEmpty) return;

    final driverSnap = await _db.collection('drivers').doc(safeDriverId).get();
    final driverData = driverSnap.data() ?? {};

    final routeId = (driverData['currentRouteId'] ?? '').toString().trim();
    final tripId = (driverData['currentTripId'] ?? '').toString().trim();

    if (routeId.isEmpty || tripId.isEmpty) return;

    final routeSnap = await _db.collection('route').doc(routeId).get();
    final routeData = routeSnap.data() ?? {};
    final rawSlots = routeData['scheduleSlots'];
    if (rawSlots is! List) return;

    Map<String, dynamic>? slot;
    for (final raw in rawSlots) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final slotId = (map['slotId'] ?? '').toString().trim();
      if (slotId == tripId) {
        slot = map;
        break;
      }
    }

    if (slot == null) return;

    final rawPassengers = slot['passengersIds'];
    if (rawPassengers is! List) return;

    final passengerIds =
        rawPassengers
            .map((e) => e.toString().trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

    if (passengerIds.isEmpty) return;

    for (final passengerId in passengerIds) {
      final passengerSnap = await _db.collection('passengers').doc(passengerId).get();
      final passengerData = passengerSnap.data() ?? {};

      final passengerLat = _extractLat(passengerData);
      final passengerLng = _extractLng(passengerData);
      if (passengerLat == null || passengerLng == null) continue;

      final isNear = _distanceService.isWithinRadius(
        driverLat: latitude,
        driverLng: longitude,
        passengerLat: passengerLat,
        passengerLng: passengerLng,
        radiusMeters: proximityRadiusMeters,
      );

      if (!isNear) continue;

      final meters = _distanceService.calculateMeters(
        driverLat: latitude,
        driverLng: longitude,
        passengerLat: passengerLat,
        passengerLng: passengerLng,
      );
      if (meters == null) continue;

      await _notificationService.notifyPassengerDriverNearby(
        routeId: routeId,
        tripId: tripId,
        driverId: safeDriverId,
        passengerId: passengerId,
        distanceMeters: meters,
        pickupDescription:
            (passengerData['pickupLocationDescription'] ??
                    passengerData['pickup'] ??
                    '')
                .toString(),
      );
    }
  }

  double? _extractLat(Map<String, dynamic> map) {
    final direct = _toDouble(map['latitude']) ?? _toDouble(map['lat']);
    if (direct != null) return direct;
    final location = map['location'];
    if (location is Map) {
      return _toDouble(location['lat']) ?? _toDouble(location['latitude']);
    }
    return null;
  }

  double? _extractLng(Map<String, dynamic> map) {
    final direct = _toDouble(map['longitude']) ?? _toDouble(map['lng']);
    if (direct != null) return direct;
    final location = map['location'];
    if (location is Map) {
      return _toDouble(location['lng']) ?? _toDouble(location['longitude']);
    }
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
