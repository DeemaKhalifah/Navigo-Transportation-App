import 'package:cloud_firestore/cloud_firestore.dart';

import 'schedule_slot.dart';

class RouteModel {
  final String routeId;
  final String startPoint;
  final String endPoint;
  final double price;
  final List<String> vehicleTypes; // bus, microbus
  final List<ScheduleSlot> scheduleSlots;
  final List<String> driverQueueIds;

  /// Optional coordinate maps (Firestore shape: `{lat: <num>, lng: <num>}`).
  final Map<String, double>? startLocation;
  final Map<String, double>? endLocation;
  final int? etaMinutes;
  final String? etaText;
  final int? distanceMeters;
  final double? distanceKm;
  final String? distanceText;
  final String? routePolyline;
  final List<Map<String, double>> routePath;
  final Map<String, dynamic>? routeModule;

  RouteModel({
    required this.routeId,
    required this.startPoint,
    required this.endPoint,
    required this.price,
    required this.vehicleTypes,
    this.scheduleSlots = const [],
    this.driverQueueIds = const [],
    this.startLocation,
    this.endLocation,
    this.etaMinutes,
    this.etaText,
    this.distanceMeters,
    this.distanceKm,
    this.distanceText,
    this.routePolyline,
    this.routePath = const [],
    this.routeModule,
  });

  // 🔹 Convert to Firestore
  Map<String, dynamic> toMap() {
    return {
      "routeId": routeId,
      "startPoint": startPoint,
      "endPoint": endPoint,
      "price": price,
      "vehicleTypes": vehicleTypes,
      "scheduleSlots": scheduleSlots.map((slot) => slot.toMap()).toList(),
      "driverQueueIds": driverQueueIds,
      if (startLocation != null) "startLocation": startLocation,
      if (endLocation != null) "endLocation": endLocation,
      if (etaMinutes != null) "etaMinutes": etaMinutes,
      if (etaText != null) "etaText": etaText,
      if (distanceMeters != null) "distanceMeters": distanceMeters,
      if (distanceKm != null) "distanceKm": distanceKm,
      if (distanceText != null) "distanceText": distanceText,
      if (routePolyline != null) "routePolyline": routePolyline,
      if (routeModule != null) "routeModule": routeModule,
    };
  }

  // 🔹 From Firestore
  factory RouteModel.fromMap(Map<String, dynamic> map) {
    final rawSlots = map['scheduleSlots'];
    final parsedSlots = <ScheduleSlot>[];
    if (rawSlots is List) {
      for (final item in rawSlots) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(
          item.map((k, v) => MapEntry(k.toString(), v)),
        );
        final slotId = m['slotId']?.toString() ?? '';
        if (slotId.isEmpty) continue;
        parsedSlots.add(ScheduleSlot.fromMap(slotId, m));
      }
    }

    Map<String, double>? parseLocation(dynamic raw) {
      if (raw is GeoPoint) {
        return {'lat': raw.latitude, 'lng': raw.longitude};
      }
      if (raw is! Map) return null;
      final lat =
          (raw['lat'] as num?)?.toDouble() ??
          (raw['latitude'] as num?)?.toDouble();
      final lng =
          (raw['lng'] as num?)?.toDouble() ??
          (raw['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return {'lat': lat, 'lng': lng};
    }

    return RouteModel(
      routeId: map['routeId'] ?? '',
      startPoint: map['startPoint'] ?? '',
      endPoint: map['endPoint'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      vehicleTypes: List<String>.from(map['vehicleTypes'] ?? []),
      scheduleSlots: parsedSlots,
      driverQueueIds: List<String>.from(map['driverQueueIds'] ?? const []),
      startLocation: parseLocation(map['startLocation']),
      endLocation: parseLocation(map['endLocation']),
      etaMinutes: (map['etaMinutes'] as num?)?.toInt(),
      etaText: map['etaText'] as String?,
      distanceMeters: (map['distanceMeters'] as num?)?.toInt(),
      distanceKm: (map['distanceKm'] as num?)?.toDouble(),
      distanceText: map['distanceText'] as String?,
      routePolyline: map['routePolyline'] as String?,
      routePath: _parseRoutePath(map['routePath'] ?? map['path']),
      routeModule: map['routeModule'] is Map
          ? Map<String, dynamic>.from(map['routeModule'] as Map)
          : null,
    );
  }

  static List<Map<String, double>> _parseRoutePath(dynamic raw) {
    if (raw is! List) return const [];
    final points = <Map<String, double>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final lat =
          (item['lat'] as num?)?.toDouble() ??
          (item['latitude'] as num?)?.toDouble();
      final lng =
          (item['lng'] as num?)?.toDouble() ??
          (item['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      points.add({'lat': lat, 'lng': lng});
    }
    return points;
  }
}
