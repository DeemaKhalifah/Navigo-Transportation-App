class Vehicle {
  final String vehicleId;
  final String type;
  final String plateNumber;
  final num seatCount;
  final String licenseNumber;

  Vehicle({
    required this.vehicleId,
    required this.type,
    required this.plateNumber,
    required this.seatCount,
    required this.licenseNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      "vehicleId": vehicleId,
      "type": type,
      "plateNumber": plateNumber,
      "seatCount": seatCount,
      "licenseNumber": licenseNumber,
    };
  }

  factory Vehicle.fromMap(Map<String, dynamic> map) {
    return Vehicle(
      vehicleId: map["vehicleId"] ?? "",
      type: map["type"] ?? "",
      plateNumber: map["plateNumber"] ?? "",
      seatCount: map["seatCount"] ?? 0,
      licenseNumber: map["licenseNumber"] ?? "",
    );
  }
}
