import 'schedule_slot.dart';

class RouteModel {
  final String routeId;
  final String startPoint;
  final String endPoint;
  final double price;
  final List<String> vehicleTypes; // bus, microbus
  final List<ScheduleSlot> scheduleSlots;
  final List<String> driverQueueIds;

  RouteModel({
    required this.routeId,
    required this.startPoint,
    required this.endPoint,
    required this.price,
    required this.vehicleTypes,
    this.scheduleSlots = const [],
    this.driverQueueIds = const [],
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
    );
  }
}