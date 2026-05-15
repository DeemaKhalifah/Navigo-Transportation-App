import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String notificationId;
  final String userId;
  final String title;
  final String message;
  final String titleKey;
  final String messageKey;
  final String type;
  final String driverId;
  final String tripId;
  final String routeId;
  final String waitingTripGroupId;
  final int requestedSeatCount;
  final int passengerCount;
  final DateTime? departureAt;
  final bool isRead;
  final DateTime timestamp;

  NotificationModel({
    required this.notificationId,
    required this.userId,
    required this.title,
    required this.message,
    this.titleKey = '',
    this.messageKey = '',
    required this.type,
    required this.driverId,
    required this.tripId,
    required this.routeId,
    this.waitingTripGroupId = '',
    this.requestedSeatCount = 0,
    this.passengerCount = 0,
    this.departureAt,
    required this.isRead,
    required this.timestamp,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    final rawTimestamp = map['timestamp'];

    DateTime parsedTime = DateTime.now();
    if (rawTimestamp is Timestamp) {
      parsedTime = rawTimestamp.toDate();
    }

    return NotificationModel(
      notificationId: (map['notificationId'] ?? '').toString(),
      userId: (map['userId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      message: (map['message'] ?? map['body'] ?? '').toString(),
      titleKey: (map['titleKey'] ?? '').toString(),
      messageKey: (map['messageKey'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      driverId: (map['driverId'] ?? '').toString(),
      tripId: (map['tripId'] ?? '').toString(),
      routeId: (map['routeId'] ?? '').toString(),
      waitingTripGroupId: (map['waitingTripGroupId'] ?? '').toString(),
      requestedSeatCount: (map['requestedSeatCount'] as num?)?.toInt() ?? 0,
      passengerCount: (map['passengerCount'] as num?)?.toInt() ?? 0,
      departureAt: _parseDate(map['departureAt']),
      isRead: map['isRead'] == true,
      timestamp: parsedTime,
    );
  }

  Map<String, dynamic> toMapForCreate() {
    return {
      'notificationId': notificationId,
      'userId': userId,
      'title': title,
      'message': message,
      'body': message,
      if (titleKey.trim().isNotEmpty) 'titleKey': titleKey.trim(),
      if (messageKey.trim().isNotEmpty) 'messageKey': messageKey.trim(),
      'type': type,
      'driverId': driverId,
      'tripId': tripId,
      'routeId': routeId,
      if (waitingTripGroupId.trim().isNotEmpty)
        'waitingTripGroupId': waitingTripGroupId.trim(),
      if (requestedSeatCount > 0) 'requestedSeatCount': requestedSeatCount,
      if (passengerCount > 0) 'passengerCount': passengerCount,
      if (departureAt != null) 'departureAt': Timestamp.fromDate(departureAt!),
      'isRead': isRead,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
