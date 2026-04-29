import 'schedule_slot.dart';

class RouteModel {
  final String routeId;
  final String startPoint;
  final String endPoint;
  final double price;
  final List<String> vehicleTypes; // bus, microbus
  final List<ScheduleSlot> scheduleSlots;
  final List<String> driverQueueIds;
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
      if (etaMinutes != null) "etaMinutes": etaMinutes,
      if (etaText != null) "etaText": etaText,
      if (distanceMeters != null) "distanceMeters": distanceMeters,
      if (distanceKm != null) "distanceKm": distanceKm,
      if (distanceText != null) "distanceText": distanceText,
      if (routePolyline != null) "routePolyline": routePolyline,
      if (routePath.isNotEmpty) "routePath": routePath,
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

    return RouteModel(
      routeId: map['routeId'] ?? '',
      startPoint: map['startPoint'] ?? '',
      endPoint: map['endPoint'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      vehicleTypes: List<String>.from(map['vehicleTypes'] ?? []),
      scheduleSlots: parsedSlots,
      driverQueueIds: List<String>.from(map['driverQueueIds'] ?? const []),
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
      final lat = (item['lat'] as num?)?.toDouble();
      final lng = (item['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      points.add({'lat': lat, 'lng': lng});
    }
    return points;
  }
}
