import 'user.dart';

/// Role `route_manager` — base fields in `users/{uid}`, extra fields in `route_manager/{uid}`.
class RouteManagerModel extends UserModel {
  final String email;
  final String routeId;

  RouteManagerModel({
    required super.userId,
    required super.firstName,
    required super.lastName,
    required super.phone,
    super.image,
    required super.role,
    required super.isVerified,
    super.isOnline,
    required this.email,
    required this.routeId,
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

  /// Stored only under `route_manager/{uid}`.
  Map<String, dynamic> toRouteManagerMap() {
    return {
      'email': email,
      'routeId': routeId,
    };
  }

  factory RouteManagerModel.fromMap(Map<String, dynamic> map) {
    return RouteManagerModel(
      userId: map['userId'] ?? '',
      firstName: map['firstName'] ?? '',
      lastName: map['lastName'] ?? '',
      phone: map['phone'] ?? '',
      image: map['image'],
      role: map['role'] ?? 'route_manager',
      isVerified: map['isVerified'] ?? false,
      isOnline: map['isOnline'] ?? false,
      email: map['email'] as String? ?? '',
      routeId: map['routeId'] as String? ?? '',
    );
  }
}
