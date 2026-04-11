import 'package:cloud_firestore/cloud_firestore.dart';

/// Instant trip request from passenger → driver (`tripDriverRequests` collection).
class TripDriverRequest {
  final String requestId;
  final String passengerId;
  final String driverId;
  final String routeId;

  /// Schedule slot id (`scheduleSlots[].slotId` on `route/{routeId}`).
  final String slotId;

  final int seatsRequested;
  final String lineLabel;
  final String startPoint;
  final String endPoint;
  final String pickupDescription;
  final String status;
  final DateTime? createdAt;
  final DateTime? respondedAt;

  const TripDriverRequest({
    required this.requestId,
    required this.passengerId,
    required this.driverId,
    required this.routeId,
    required this.slotId,
    required this.seatsRequested,
    required this.lineLabel,
    required this.startPoint,
    required this.endPoint,
    required this.pickupDescription,
    required this.status,
    this.createdAt,
    this.respondedAt,
  });

  /// Alias for [slotId] when reading Firestore field `scheduleId`.
  String get scheduleId => slotId;

  static const String pending = 'pending';
  static const String accepted = 'accepted';
  static const String declined = 'declined';

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'passengerId': passengerId,
      'driverId': driverId,
      'routeId': routeId,
      'slotId': slotId,
      'scheduleId': slotId,
      'seatsRequested': seatsRequested,
      'lineLabel': lineLabel,
      'startPoint': startPoint,
      'endPoint': endPoint,
      'pickupDescription': pickupDescription,
      'status': status,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
    if (respondedAt != null) {
      m['respondedAt'] = Timestamp.fromDate(respondedAt!);
    }
    return m;
  }

  factory TripDriverRequest.fromDoc(DocumentSnapshot doc) {
    final map = Map<String, dynamic>.from(doc.data() as Map? ?? {});
    final slot = (map['scheduleId'] ?? map['slotId'] ?? '').toString();
    return TripDriverRequest(
      requestId: doc.id,
      passengerId: (map['passengerId'] ?? '').toString(),
      driverId: (map['driverId'] ?? '').toString(),
      routeId: (map['routeId'] ?? '').toString(),
      slotId: slot,
      seatsRequested: (map['seatsRequested'] as num?)?.toInt() ?? 1,
      lineLabel: (map['lineLabel'] ?? '').toString(),
      startPoint: (map['startPoint'] ?? '').toString(),
      endPoint: (map['endPoint'] ?? '').toString(),
      pickupDescription: (map['pickupDescription'] ?? '').toString(),
      status: (map['status'] ?? pending).toString(),
      createdAt: _tsToDate(map['createdAt']),
      respondedAt: _tsToDate(map['respondedAt']),
    );
  }

  static DateTime? _tsToDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }
}
