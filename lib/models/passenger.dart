import 'package:cloud_firestore/cloud_firestore.dart';

class Passenger {
  final String passengerId;
  final String fullName;
  final String phoneNumber;

  // 🔹 LOCATION
  final double? latitude;
  final double? longitude;
  final DateTime? lastLocationUpdate;

  /// Manual pickup label or address (e.g. from schedule screen).
  final String? pickupLocationDescription;

  Passenger({
    required this.passengerId,
    required this.fullName,
    required this.phoneNumber,
    this.latitude,
    this.longitude,
    this.lastLocationUpdate,
    this.pickupLocationDescription,
  });

  // 🔹 TO MAP
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'passengerId': passengerId,
      'fullName': fullName,
      'phoneNumber': phoneNumber,

      // LOCATION
      'latitude': latitude,
      'longitude': longitude,
      'location': latitude != null && longitude != null
          ? {'lat': latitude, 'lng': longitude}
          : null,
      'lastLocationUpdate': lastLocationUpdate != null
          ? Timestamp.fromDate(lastLocationUpdate!)
          : null,
    };

    final pickup = pickupLocationDescription?.trim();
    if (pickup != null && pickup.isNotEmpty) {
      map['pickupLocationDescription'] = pickup;
      map['pickup'] = pickup;
    }

    return map;
  }

  // 🔹 FROM MAP
  factory Passenger.fromMap(Map<String, dynamic> map) {
    return Passenger(
      passengerId: map['passengerId'] ?? '',
      fullName: map['fullName'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',

      latitude: _getLat(map),
      longitude: _getLng(map),
      lastLocationUpdate: _parseDate(map['lastLocationUpdate']),
      pickupLocationDescription: _pickupDescription(map),
    );
  }

  static String? _pickupDescription(Map<String, dynamic> map) {
    final direct = map['pickupLocationDescription']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final pickup = map['pickup']?.toString().trim();
    if (pickup != null && pickup.isNotEmpty) return pickup;
    return null;
  }

  // 🔹 HELPERS
  static double? _getLat(Map<String, dynamic> map) {
    if (map['latitude'] != null) return (map['latitude'] as num).toDouble();

    if (map['location'] is Map && map['location']['lat'] != null) {
      return (map['location']['lat'] as num).toDouble();
    }

    return null;
  }

  static double? _getLng(Map<String, dynamic> map) {
    if (map['longitude'] != null) return (map['longitude'] as num).toDouble();

    if (map['location'] is Map && map['location']['lng'] != null) {
      return (map['location']['lng'] as num).toDouble();
    }

    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    return null;
  }
}
