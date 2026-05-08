import '../../models/driver_status.dart';

class DriverRow {
  DriverRow({
    required this.driverId,
    required this.userId,
    required this.name,
    required this.vehicleLabel,
    required this.routeLine,
    required this.rawStatus,
    required this.isOnline,
  });

  final String driverId;
  final String userId;
  final String name;
  final String vehicleLabel;
  final String routeLine;

  /// Canonical driver statuses — see [DriverStatus].
  final String rawStatus;

  final bool isOnline;

  String get statusLabel {
    switch (rawStatus) {
      case DriverStatus.available:
        return isOnline ? 'Available' : 'Offline';
      case DriverStatus.assigned:
        return 'Assigned';
      case DriverStatus.onTrip:
        return 'On Trip';
      case DriverStatus.offline:
        return 'Offline';
      default:
        return rawStatus;
    }
  }
}

