import 'package:cloud_firestore/cloud_firestore.dart';

/// Stored at `trips/{tripId}` — no trip-level status (use [DriverModel.status]).
class Trip {
  final String tripId;
  final String driverId;
  final String routeId;
  final String slotId;
  final List<String> passengersIds;
  final DateTime departureAt;
  final DateTime arrivalAt;

  Trip({
    required this.tripId,
    required this.driverId,
    required this.routeId,
    required this.slotId,
    required this.passengersIds,
    required this.departureAt,
    required this.arrivalAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'tripId': tripId,
      'driverId': driverId,
      'routeId': routeId,
      'slotId': slotId,
      'passengersIds': passengersIds,
      'departureAt': Timestamp.fromDate(departureAt),
      'arrivalAt': Timestamp.fromDate(arrivalAt),
    };
  }

  factory Trip.fromMap(String tripId, Map<String, dynamic> map) {
    return Trip(
      tripId: map['tripId'] as String? ?? tripId,
      driverId: map['driverId'] ?? '',
      routeId: map['routeId'] ?? '',
      slotId: map['slotId'] as String? ?? map['scheduleSlotId'] as String? ?? '',
      passengersIds: List<String>.from(map['passengersIds'] ?? []),
      departureAt: _readDate(map['departureAt']) ?? DateTime.now(),
      arrivalAt: _readDate(map['arrivalAt']) ?? DateTime.now(),
    );
  }

  static DateTime? _readDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
