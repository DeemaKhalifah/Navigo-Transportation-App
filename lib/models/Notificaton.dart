import 'user.dart';

class NotificationModel {
  final String notificationId; // Firestore document ID
  final String userId;         // Passenger ID
  final String title;          // Notification title
  final String body;           // Notification message
  final DateTime timestamp;    // When notification was created
  final bool isRead;           // Has the user read it
  final String? tripId;        // Optional: related trip ID
  final String? type;          // Optional: e.g., 'trip_accepted', 'trip_cancelled'

  NotificationModel({
    required this.notificationId,
    required this.userId,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    this.tripId,
    this.type,
  });

  // Convert the object to a map for Firestore
  Map<String, dynamic> toMap() {
    return {
      "notificationId": notificationId,
      "userId": userId,
      "title": title,
      "body": body,
      "timestamp": timestamp.toIso8601String(),
      "isRead": isRead,
      "tripId": tripId,
      "type": type,
    };
  }

  // Create an object from Firestore data
  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      notificationId: map["notificationId"] ?? "",
      userId: map["userId"] ?? "",
      title: map["title"] ?? "",
      body: map["body"] ?? "",
      timestamp: DateTime.parse(map["timestamp"]),
      isRead: map["isRead"] ?? false,
      tripId: map["tripId"],
      type: map["type"],
    );
  }
}