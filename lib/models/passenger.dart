import 'user.dart';

class Passenger extends UserModel {
  /// Trip IDs — Firestore field is typically `TripHistory` (see [toPassengerMap]).
  final List<String> tripHistory;

  /// Payment data — Firestore field is `paymentMethod` (list or single entry).
  final List<dynamic> paymentMethod;

  Passenger({
    required super.userId,
    required super.firstName,
    required super.lastName,
    required super.phone,
    super.image,
    required super.role,
    required super.isVerified,
    super.isOnline,
    required this.tripHistory,
    required this.paymentMethod,
  });

  @override
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'firstName': firstName,
      'lastName': lastName,
      'phone': phone,
      'image': image,
      'role': role,
      'isVerified': isVerified,
      'isOnline': isOnline,
    };
  }

  /// Fields stored under `passengers/{uid}`.
  Map<String, dynamic> toPassengerMap() {
    return {
      'TripHistory': tripHistory,
      'paymentMethod': paymentMethod,
    };
  }

  factory Passenger.fromMap(Map<String, dynamic> map) {
    return Passenger(
      userId: map['userId'] ?? '',
      firstName: map['firstName'] ?? '',
      lastName: map['lastName'] ?? '',
      phone: map['phone'] ?? '',
      image: map['image'],
      role: map['role'] ?? 'passenger',
      isVerified: map['isVerified'] ?? false,
      isOnline: map['isOnline'] ?? false,
      tripHistory: _parseTripHistory(map),
      paymentMethod: _parsePaymentMethod(map),
    );
  }

  static List<String> _parseTripHistory(Map<String, dynamic> map) {
    for (final key in ['TripHistory', 'tripHistory', 'tripIds']) {
      final v = map[key];
      if (v is List) {
        return v.map((e) => e.toString()).toList();
      }
    }
    return [];
  }

  static List<dynamic> _parsePaymentMethod(Map<String, dynamic> map) {
    final single = map['paymentMethod'];
    if (single is List) {
      return List<dynamic>.from(single);
    }
    if (single != null) {
      return [single];
    }
    final legacy = map['paymentMethods'];
    if (legacy is List) {
      return List<dynamic>.from(legacy);
    }
    return [];
  }
}
