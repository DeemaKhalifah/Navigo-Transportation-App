class Vehicle {
  final String vehicleId;
  final String type;
  final String vehicleType;
  final String vehicleClass;
  final String plateNumber;
  final num seatCount;
  final num capacity;
  final String licenseNumber;

  Vehicle({
    required this.vehicleId,
    required this.type,
    required this.vehicleType,
    required this.vehicleClass,
    required this.plateNumber,
    required this.seatCount,
    required this.capacity,
    required this.licenseNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      "vehicleId": vehicleId,
      "type": type,
      "vehicleType": vehicleType,
      "vehicleClass": vehicleClass,
      "plateNumber": plateNumber,
      "seatCount": seatCount,
      "capacity": capacity,
      "licenseNumber": licenseNumber,
    };
  }

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    final type = (map["type"] ?? map["vehicleType"] ?? "").toString();
    final capacity = map["capacity"] ?? map["seatCount"] ?? 0;

    return Vehicle(
      vehicleId: map["vehicleId"] ?? "",
      type: type,
      vehicleType: (map["vehicleType"] ?? type).toString(),
      vehicleClass: (map["vehicleClass"] ?? "").toString(),
      plateNumber: map["plateNumber"] ?? "",
      seatCount: map["seatCount"] ?? capacity,
      capacity: capacity,
      licenseNumber: map["licenseNumber"] ?? "",
    );
  }
}