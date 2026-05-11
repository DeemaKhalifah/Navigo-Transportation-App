class AdminDashboardModel {
  final int totalUsers;
  final int totalDrivers;
  final int pendingDrivers;
  final int totalRoutes;
  final int activeTrips;
  final List<AdminActivityItem> activities;
  final List<AdminApprovalItem> approvals;
  final List<AdminReportItem> reports;

  AdminDashboardModel({
    required this.totalUsers,
    required this.totalDrivers,
    required this.pendingDrivers,
    required this.totalRoutes,
    required this.activeTrips,
    required this.activities,
    required this.approvals,
    required this.reports,
  });
}

class AdminActivityItem {
  final String title;
  final String subtitle;
  final DateTime? timestamp;

  AdminActivityItem({
    required this.title,
    required this.subtitle,
    this.timestamp,
  });
}

class AdminApprovalItem {
  final String id;
  final String userId;
  final String type;
  final String name;
  final String details;
  final String status;

  AdminApprovalItem({
    required this.id,
    required this.userId,
    required this.type,
    required this.name,
    required this.details,
    required this.status,
  });
}

class AdminReportItem {
  final String id;
  final String senderName;
  final String senderRole;
  final String routeId;
  final String routeLabel;
  final String message;
  final String status;
  final DateTime? createdAt;
  final DateTime? sentToAdminAt;

  AdminReportItem({
    required this.id,
    required this.senderName,
    required this.senderRole,
    required this.routeId,
    required this.routeLabel,
    required this.message,
    required this.status,
    this.createdAt,
    this.sentToAdminAt,
  });
}

class AdminDriverItem {
  final String driverId;
  final String userId;
  final String fullName;
  final String email;
  final String phone;
  final String status;
  final String approvalStatus;
  final bool isApproved;
  final bool isOnline;
  final String routeId;
  final String routeLabel;
  final String vehicleId;
  final String vehicleType;
  final String plateNumber;
  final String licenseNumber;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AdminDriverItem({
    required this.driverId,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.status,
    required this.approvalStatus,
    required this.isApproved,
    required this.isOnline,
    required this.routeId,
    required this.routeLabel,
    required this.vehicleId,
    required this.vehicleType,
    required this.plateNumber,
    required this.licenseNumber,
    this.createdAt,
    this.updatedAt,
  });
}

class AdminPassengerItem {
  final String passengerId;
  final String userId;
  final String fullName;
  final String email;
  final String phone;
  final bool isVerified;
  final bool isOnline;
  final String pickupLocationDescription;
  final double? latitude;
  final double? longitude;
  final DateTime? lastLocationUpdate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AdminPassengerItem({
    required this.passengerId,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.isVerified,
    required this.isOnline,
    required this.pickupLocationDescription,
    this.latitude,
    this.longitude,
    this.lastLocationUpdate,
    this.createdAt,
    this.updatedAt,
  });
}

class AdminTripItem {
  final String routeId;
  final String routeLabel;
  final String slotId;
  final DateTime? departureAt;
  final DateTime? arrivalAt;
  final String status;
  final String vehicleType;
  final String driverId;
  final int capacity;
  final int passengerCount;
  final double? price;

  AdminTripItem({
    required this.routeId,
    required this.routeLabel,
    required this.slotId,
    required this.departureAt,
    required this.arrivalAt,
    required this.status,
    required this.vehicleType,
    required this.driverId,
    required this.capacity,
    required this.passengerCount,
    this.price,
  });
}
