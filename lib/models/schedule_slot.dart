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

  ScheduleSlot({
    required this.slotId,
    required this.routeId,
    required this.departureAt,
    required this.arrivalAt,
    this.price,
    required this.capacity,
    required this.vehicleType,
  });

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
    };
    if (price != null) m['price'] = price;
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
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
