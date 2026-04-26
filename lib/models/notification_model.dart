import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String notificationId;
  final String userId;
  final String title;
  final String message;
  final String type;
  final String driverId;
  final String tripId;
  final String routeId;
  final bool isRead;
  final DateTime timestamp;

  NotificationModel({
    required this.notificationId,
    required this.userId,
    required this.title,
    required this.message,
    required this.type,
    required this.driverId,
    required this.tripId,
    required this.routeId,
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
      type: (map['type'] ?? '').toString(),
      driverId: (map['driverId'] ?? '').toString(),
      tripId: (map['tripId'] ?? '').toString(),
      routeId: (map['routeId'] ?? '').toString(),
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
      'type': type,
      'driverId': driverId,
      'tripId': tripId,
      'routeId': routeId,
      'isRead': isRead,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}