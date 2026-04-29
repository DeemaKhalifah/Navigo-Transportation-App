import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notification_model.dart';

class NotificationService {
  NotificationService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<void> createRouteManagerDriverNotifications({
    required String routeId,
    required String senderId,
    required String message,
    required List<String> driverUserIds,
    Map<String, String> driverDocIdsByUserId = const {},
    String receiverScope = 'specific',
  }) async {
    final safeRouteId = routeId.trim();
    final safeSenderId = senderId.trim();
    final safeMessage = message.trim();
    final uniqueDriverUserIds = driverUserIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (safeRouteId.isEmpty) {
      throw ArgumentError('Route is missing.');
    }
    if (safeMessage.isEmpty) {
      throw ArgumentError('Notification message is required.');
    }
    if (uniqueDriverUserIds.isEmpty) {
      throw ArgumentError('Choose at least one driver.');
    }

    final batch = _db.batch();

    for (final userId in uniqueDriverUserIds) {
      final ref = _db.collection('notifications').doc();
      final driverDocId = (driverDocIdsByUserId[userId] ?? '').trim();

      batch.set(ref, {
        'notificationId': ref.id,
        'userId': userId,
        'title': 'Route Manager Message',
        'message': safeMessage,
        'body': safeMessage,
        'type': 'route_manager_message',
        'driverId': driverDocId,
        'tripId': '',
        'routeId': safeRouteId,
        'senderId': safeSenderId,
        'senderRole': 'route_manager',
        'receiverScope': receiverScope,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Future<void> createTripStartedNotifications({
    required String routeId,
    required String tripId,
    required String driverId,
    required List<String> passengerIds,
  }) async {
    final uniquePassengerIds = passengerIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (uniquePassengerIds.isEmpty) return;

    final batch = _db.batch();

    for (final passengerId in uniquePassengerIds) {
      final ref = _db.collection('notifications').doc();

      batch.set(ref, {
        'notificationId': ref.id,
        'userId': passengerId,
        'title': 'Trip Started',
        'message': 'Your trip has started 🚍',
        'body': 'Your trip has started 🚍',
        'type': 'trip_started',
        'driverId': driverId,
        'tripId': tripId,
        'routeId': routeId,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Stream<List<NotificationModel>> watchUserNotifications(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final notifications = snapshot.docs.map((doc) {
            return NotificationModel.fromMap({
              ...doc.data(),
              'notificationId': doc.id,
            });
          }).toList();

          notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));

          return notifications;
        });
  }

  Stream<int> watchUnreadCount(String userId) {
    final safeUserId = userId.trim();
    if (safeUserId.isEmpty) return Stream.value(0);

    return watchUserNotifications(safeUserId).map(
      (notifications) => notifications.where((n) => !n.isRead).length,
    );
  }

  Future<void> markAsRead(String notificationId) async {
    final id = notificationId.trim();
    if (id.isEmpty) return;

    await _db.collection('notifications').doc(id).set({
      'isRead': true,
    }, SetOptions(merge: true));
  }
}
