import 'package:cloud_firestore/cloud_firestore.dart';

class WaitingTripRequest {
  final String requestId;
  final String groupId;
  final String routeId;
  final String passengerId;
  final String passengerName;
  final DateTime requestedAt;
  final DateTime departureAt;
  final int seatsRequested;
  final String vehicleType;
  final String pickupLocationDescription;
  final String status;
  final String tripId;

  const WaitingTripRequest({
    required this.requestId,
    required this.groupId,
    required this.routeId,
    required this.passengerId,
    this.passengerName = '',
    required this.requestedAt,
    required this.departureAt,
    required this.seatsRequested,
    required this.vehicleType,
    required this.pickupLocationDescription,
    required this.status,
    this.tripId = '',
  });

  factory WaitingTripRequest.fromMap(
    String fallbackId,
    Map<String, dynamic> map,
  ) {
    return WaitingTripRequest(
      requestId: (map['requestId'] ?? fallbackId).toString(),
      groupId: (map['groupId'] ?? '').toString(),
      routeId: (map['routeId'] ?? '').toString(),
      passengerId: (map['passengerId'] ?? '').toString(),
      passengerName: (map['passengerName'] ?? '').toString(),
      requestedAt: _parseDate(map['requestedAt']) ?? DateTime.now(),
      departureAt: _parseDate(map['departureAt']) ?? DateTime.now(),
      seatsRequested: (map['seatsRequested'] as num?)?.toInt() ?? 1,
      vehicleType: (map['vehicleType'] ?? 'microbus').toString(),
      pickupLocationDescription: (map['pickupLocationDescription'] ?? '')
          .toString(),
      status: (map['status'] ?? 'pending').toString(),
      tripId: (map['tripId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'groupId': groupId,
      'routeId': routeId,
      'passengerId': passengerId,
      'passengerName': passengerName,
      'requestedAt': Timestamp.fromDate(requestedAt),
      'departureAt': Timestamp.fromDate(departureAt),
      'seatsRequested': seatsRequested,
      'vehicleType': vehicleType,
      'pickupLocationDescription': pickupLocationDescription,
      'status': status,
      'tripId': tripId,
    };
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

class WaitingTripSubmitResult {
  final bool routeManagerNotified;
  final String groupId;
  final String routeId;
  final String? tripId;
  final int waitingPassengerCount;
  final int waitingSeatCount;

  const WaitingTripSubmitResult({
    required this.routeManagerNotified,
    required this.groupId,
    required this.routeId,
    required this.waitingPassengerCount,
    required this.waitingSeatCount,
    this.tripId,
  });
}

class WaitingTripGroup {
  final String groupId;
  final String routeId;
  final String lineLabel;
  final DateTime departureAt;
  final String vehicleType;
  final List<String> passengerIds;
  final int passengerCount;
  final int requestedSeatCount;
  final String status;
  final bool routeManagerNotified;

  const WaitingTripGroup({
    required this.groupId,
    required this.routeId,
    required this.lineLabel,
    required this.departureAt,
    required this.vehicleType,
    required this.passengerIds,
    required this.passengerCount,
    required this.requestedSeatCount,
    required this.status,
    required this.routeManagerNotified,
  });

  factory WaitingTripGroup.fromMap(
    String fallbackId,
    Map<String, dynamic> map,
  ) {
    final passengers = List<String>.from(map['passengerIds'] ?? const []);
    return WaitingTripGroup(
      groupId: (map['groupId'] ?? fallbackId).toString(),
      routeId: (map['routeId'] ?? '').toString(),
      lineLabel: (map['lineLabel'] ?? '').toString(),
      departureAt:
          WaitingTripRequest._parseDate(map['departureAt']) ?? DateTime.now(),
      vehicleType: (map['vehicleType'] ?? 'microbus').toString(),
      passengerIds: passengers,
      passengerCount:
          (map['passengerCount'] as num?)?.toInt() ?? passengers.length,
      requestedSeatCount: (map['requestedSeatCount'] as num?)?.toInt() ?? 0,
      status: (map['status'] ?? 'pending').toString(),
      routeManagerNotified: map['routeManagerNotified'] == true,
    );
  }
}

class WaitingTripRequestException implements Exception {
  final String messageKey;

  const WaitingTripRequestException(this.messageKey);

  @override
  String toString() => messageKey;
}
