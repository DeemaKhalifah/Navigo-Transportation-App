class GpsService {
  final String tripId; // Firestore document ID
  final String driverId;
  final Map<String, double> driverLocation; // {"lat": 32.221, "lng": 35.254}

  final String passengerId;
  final Map<String, double> passengerLocation; // {"lat": 32.223, "lng": 35.256}

  final DateTime timestamp; // last update time
  final String? routeId; // optional, link to route

  GpsService({
    required this.tripId,
    required this.driverId,
    required this.driverLocation,
    required this.passengerId,
    required this.passengerLocation,
    required this.timestamp,
    this.routeId,
  });

  // Convert to Firestore map
  Map<String, dynamic> toMap() {
    return {
      "tripId": tripId,
      "driverId": driverId,
      "driverLocation": driverLocation,
      "passengerId": passengerId,
      "passengerLocation": passengerLocation,
      "timestamp": timestamp.toIso8601String(),
      "routeId": routeId,
    };
  }

  // Create object from Firestore map
  factory GpsService.fromMap(Map<String, dynamic> map) {
    return GpsService(
      tripId: map["tripId"] ?? "",
      driverId: map["driverId"] ?? "",
      driverLocation: Map<String, double>.from(map["driverLocation"]),
      passengerId: map["passengerId"] ?? "",
      passengerLocation: Map<String, double>.from(map["passengerLocation"]),
      timestamp: DateTime.parse(map["timestamp"]),
      routeId: map["routeId"],
    );
  }
}
