import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// Bus only: repeat interval in minutes (optional metadata / generation).
  final int? frequencyMinutes;

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
    this.frequencyMinutes,
  }) : passengersIds = passengersIds ?? const [];

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
      'passengersIds': passengersIds,
    };
    if (price != null) m['price'] = price;
    if (frequencyMinutes != null) m['frequencyMinutes'] = frequencyMinutes;
    return m;
  }

  factory ScheduleSlot.fromMap(String fallbackSlotId, Map<String, dynamic> map) {
    final id = map['slotId'] as String? ?? fallbackSlotId;
    return ScheduleSlot(
      slotId: id,
      routeId: map['routeId'] as String? ?? '',
      departureAt: _parseDate(map['departureAt']) ?? DateTime.now(),
      arrivalAt: _parseDate(map['arrivalAt']) ?? DateTime.now(),
      price: (map['price'] as num?)?.toDouble(),
      capacity: (map['capacity'] as num?)?.toInt() ?? 0,
      vehicleType: map['vehicleType'] as String? ?? 'bus',
      driverId: map['driverId'] as String? ?? '',
      passengersIds: _parseIdList(map['passengersIds']),
      frequencyMinutes: (map['frequencyMinutes'] as num?)?.toInt(),
    );
  }

  static List<String> _parseIdList(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
