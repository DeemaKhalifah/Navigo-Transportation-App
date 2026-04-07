class MapService {
  final String routeId; // Firestore document ID
  final String name; // Route name, e.g., "City A → City B"
  final List<Map<String, double>>
  path; // List of GPS points [{"lat": 32.221, "lng": 35.254}, ...]
  final double? distance; // Optional: total distance in km
  final int? estimatedTime; // Optional: estimated time in minutes
  final DateTime? createdAt; // Optional: creation timestamp
  final DateTime? updatedAt; // Optional: last updated timestamp

  MapService({
    required this.routeId,
    required this.name,
    required this.path,
    this.distance,
    this.estimatedTime,
    this.createdAt,
    this.updatedAt,
  });

  // Convert to Firestore map
  Map<String, dynamic> toMap() {
    return {
      "routeId": routeId,
      "name": name,
      "path": path,
      "distance": distance,
      "estimatedTime": estimatedTime,
      "createdAt": createdAt?.toIso8601String(),
      "updatedAt": updatedAt?.toIso8601String(),
    };
  }

  // Create object from Firestore map
  factory MapService.fromMap(Map<String, dynamic> map) {
    return MapService(
      routeId: map["routeId"] ?? "",
      name: map["name"] ?? "",
      path: List<Map<String, double>>.from(
        map["path"].map((point) => Map<String, double>.from(point)),
      ),
      distance: map["distance"] != null
          ? (map["distance"] as num).toDouble()
          : null,
      estimatedTime: map["estimatedTime"],
      createdAt: map["createdAt"] != null
          ? DateTime.parse(map["createdAt"])
          : null,
      updatedAt: map["updatedAt"] != null
          ? DateTime.parse(map["updatedAt"])
          : null,
    );
  }
}
