import 'package:cloud_firestore/cloud_firestore.dart';
import 'trip_status.dart';

/// Embedded in `route/{routeId}` under the `scheduleSlots` array field.
class ScheduleSlot {
  final String slotId;
  final String routeId;
  final DateTime departureAt;
  final DateTime arrivalAt;
  final double? price;
  final int capacity;
  final String vehicleType;

  /// Assigned driver (`drivers` doc id). Empty if unassigned.
  final String driverId;

  /// Passenger user ids booked on this slot.
  final List<String> passengersIds;
  final List<Map<String, dynamic>> passengerBookings;

  /// Bus only: repeat interval in minutes (optional metadata / generation).
  final int? frequencyMinutes;

  /// NEW: Trip status
  final String status;
  final int? etaMinutes;
  final String? etaText;
  final int? distanceMeters;
  final double? distanceKm;
  final String? distanceText;
  final String? routePolyline;
  final List<Map<String, double>> routePath;
  final Map<String, dynamic>? routeModule;

  ScheduleSlot({
    required this.slotId,
    required this.routeId,
    required this.departureAt,
    required this.arrivalAt,
    this.price,
    required this.capacity,
    required this.vehicleType,
    this.driverId = '',
    List<String>? passengersIds,
    List<Map<String, dynamic>>? passengerBookings,
    this.frequencyMinutes,
    this.status = TripStatus.scheduled, // default
    this.etaMinutes,
    this.etaText,
    this.distanceMeters,
    this.distanceKm,
    this.distanceText,
    this.routePolyline,
    List<Map<String, double>>? routePath,
    this.routeModule,
  }) : passengerBookings = _normalizePassengerBookings(
         passengerBookings: passengerBookings,
         passengersIds: passengersIds,
       ),
       passengersIds = _normalizePassengerBookings(
         passengerBookings: passengerBookings,
         passengersIds: passengersIds,
       ).map((e) => (e['passengerId'] ?? '').toString()).toList(),
       routePath = routePath ?? const [];

  DateTime get serviceDate =>
      DateTime(departureAt.year, departureAt.month, departureAt.day);

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'slotId': slotId,
      'routeId': routeId,
      'departureAt': Timestamp.fromDate(departureAt),
      'arrivalAt': Timestamp.fromDate(arrivalAt),
      'capacity': capacity,
      'vehicleType': vehicleType,
      'driverId': driverId,
      'passengersIds': passengerBookings,
      'status': status, // ✅ added
    };
    if (price != null) m['price'] = price;
    if (frequencyMinutes != null) m['frequencyMinutes'] = frequencyMinutes;
    if (etaMinutes != null) m['etaMinutes'] = etaMinutes;
    if (etaText != null && etaText!.trim().isNotEmpty) m['etaText'] = etaText;
    if (distanceMeters != null) m['distanceMeters'] = distanceMeters;
    if (distanceKm != null) m['distanceKm'] = distanceKm;
    if (distanceText != null && distanceText!.trim().isNotEmpty) {
      m['distanceText'] = distanceText;
    }
    if (routePolyline != null && routePolyline!.trim().isNotEmpty) {
      m['routePolyline'] = routePolyline;
    }
    if (routeModule != null && routeModule!.isNotEmpty) {
      m['routeModule'] = routeModule;
    }
    return m;
  }

  factory ScheduleSlot.fromMap(
    String fallbackSlotId,
    Map<String, dynamic> map,
  ) {
    final id = map['slotId'] as String? ?? fallbackSlotId;
    final now = DateTime.now();
    final parsedDeparture = _parseDate(map['departureAt']);
    final departureAt =
        parsedDeparture ?? now.add(const Duration(days: 3650)); // ~10 years

    final parsedArrival = _parseDate(map['arrivalAt']);
    final arrivalAt = parsedArrival ?? departureAt.add(const Duration(hours: 1));

    return ScheduleSlot(
      slotId: id,
      routeId: map['routeId'] as String? ?? '',
      departureAt: departureAt,
      arrivalAt: arrivalAt,
      price: (map['price'] as num?)?.toDouble(),
      capacity: (map['capacity'] as num?)?.toInt() ?? 0,
      vehicleType: map['vehicleType'] as String? ?? 'bus',
      driverId: map['driverId'] as String? ?? '',
      passengerBookings: _parsePassengerBookings(map['passengersIds']),
      frequencyMinutes: (map['frequencyMinutes'] as num?)?.toInt(),

      // ✅ NEW: normalize status from Firestore
      status: TripStatus.normalize(map['status']),
      etaMinutes: (map['etaMinutes'] as num?)?.toInt(),
      etaText: map['etaText'] as String?,
      distanceMeters: (map['distanceMeters'] as num?)?.toInt(),
      distanceKm: (map['distanceKm'] as num?)?.toDouble(),
      distanceText: map['distanceText'] as String?,
      routePolyline: map['routePolyline'] as String?,
      routePath: _parseRoutePath(map['routePath']),
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

  static List<Map<String, dynamic>> _normalizePassengerBookings({
    required List<Map<String, dynamic>>? passengerBookings,
    required List<String>? passengersIds,
  }) {
    if (passengerBookings != null && passengerBookings.isNotEmpty) {
      return passengerBookings
          .map(
            (entry) => {
              'passengerId': (entry['passengerId'] ?? '').toString().trim(),
              'pickupLocationDescription':
                  (entry['pickupLocationDescription'] ?? '')
                      .toString()
                      .trim(),
            },
          )
          .where((entry) => (entry['passengerId'] ?? '').toString().isNotEmpty)
          .toList();
    }

    if (passengersIds == null || passengersIds.isEmpty) return [];
    return passengersIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .map(
          (id) => <String, dynamic>{
            'passengerId': id,
            'pickupLocationDescription': '',
          },
        )
        .toList();
  }

  static List<Map<String, dynamic>> _parsePassengerBookings(dynamic raw) {
    if (raw is! List) return [];
    final result = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map) {
        final passengerId = (item['passengerId'] ?? item['userId'] ?? '')
            .toString()
            .trim();
        if (passengerId.isEmpty) continue;
        result.add({
          'passengerId': passengerId,
          'pickupLocationDescription':
              (item['pickupLocationDescription'] ??
                      item['pickup'] ??
                      item['pickupLocation'] ??
                      '')
                  .toString()
                  .trim(),
        });
        continue;
      }

      final id = item.toString().trim();
      if (id.isEmpty) continue;
      result.add({'passengerId': id, 'pickupLocationDescription': ''});
    }
    return result;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
