import 'driver_status.dart';
import 'user.dart';

class DriverModel extends UserModel {
  /// Same as [userId] for auth-backed drivers; document id is `drivers/{driverId}`.
  final String driverId;
  final String vehicleId;
  final String routeId;

  /// `offline` | `available` | `assigned` | `onTrip` — see [DriverStatus].
  final String status;
 
  final bool isApproved;

  DriverModel({
    required super.userId,
    required super.firstName,
    required super.lastName,
    required super.phone,
    super.image,
    required super.role,
    required super.isVerified,
    super.isOnline,
    String? driverId,
    required this.vehicleId,
    required this.routeId,
    required this.status,
    required this.isApproved,
  })  : driverId = driverId ?? userId;

  @override
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'driverId': driverId,
      'firstName': firstName,
      'lastName': lastName,
      'phone': phone,
      'image': image,
      'role': role,
      'isVerified': isVerified,
      'isOnline': isOnline,
      'vehicleId': vehicleId,
      'routeId': routeId,
      'status': status,
      'isApproved': isApproved,
    };
  }

  /// Fields stored under `drivers/{driverId}` (typically `driverId` == auth uid).
  Map<String, dynamic> toDriverMap() {
    return {
      'userId': userId,
      'routeId': routeId,
      'vehicleId': vehicleId,
      'status': status,
      'isApproved': isApproved,
    };
  }

  factory DriverModel.fromMap(Map<String, dynamic> map) {
    final legacyVehicle = map['vehicle'] as String?;
    final legacyRoute = map['route'] as String?;
    final uid = map['userId'] ?? '';
    final did = map['driverId'] as String? ?? uid;

    final legacyAvailability = map['availability'];
    final rawStatus = map['status'];
    String resolvedStatus = DriverStatus.normalize(rawStatus as String?);
    if (rawStatus == null && legacyAvailability == true) {
      resolvedStatus = DriverStatus.available;
    }

    return DriverModel(
      userId: uid,
      firstName: map['firstName'] ?? '',
      lastName: map['lastName'] ?? '',
      phone: map['phone'] ?? '',
      image: map['image'],
      role: map['role'] ?? 'driver',
      isVerified: map['isVerified'] ?? false,
      isOnline: map['isOnline'] ?? false,
      driverId: did,
      vehicleId: map['vehicleId'] as String? ?? legacyVehicle ?? '',
      routeId: map['routeId'] as String? ?? legacyRoute ?? '',
      status: resolvedStatus,
      isApproved: map['isApproved'] ?? false,
    );
  }
}
