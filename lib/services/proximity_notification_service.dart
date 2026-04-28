import 'package:cloud_firestore/cloud_firestore.dart';

class ProximityNotificationService {
  ProximityNotificationService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String _notificationsCollection = 'notifications';
  static const String _proximityAlertsCollection = 'proximityAlerts';

  Future<void> notifyPassengerDriverNearby({
    required String routeId,
    required String tripId,
    required String driverId,
    required String passengerId,
    required double distanceMeters,
    String pickupDescription = '',
  }) async {
    final safeTripId = tripId.trim();
    final safePassengerId = passengerId.trim();
    final safeDriverId = driverId.trim();
    final safeRouteId = routeId.trim();

    if (safeTripId.isEmpty ||
        safePassengerId.isEmpty ||
        safeDriverId.isEmpty ||
        safeRouteId.isEmpty) {
      return;
    }

    final dedupeId = '${safeTripId}_$safePassengerId';
    final dedupeRef = _db.collection(_proximityAlertsCollection).doc(dedupeId);

    await _db.runTransaction((tx) async {
      final dedupeSnap = await tx.get(dedupeRef);
      if (dedupeSnap.exists) return;

      final notificationRef = _db.collection(_notificationsCollection).doc();
      final rounded = distanceMeters.round();
      final pickupText = pickupDescription.trim();
      final message =
          pickupText.isEmpty
              ? 'Your driver is nearby (${rounded}m away).'
              : 'Your driver is nearby (${rounded}m from $pickupText).';

      tx.set(notificationRef, {
        'notificationId': notificationRef.id,
        'userId': safePassengerId,
        'title': 'Driver Nearby',
        'message': message,
        'body': message,
        'type': 'driver_nearby',
        'driverId': safeDriverId,
        'tripId': safeTripId,
        'routeId': safeRouteId,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      });

      tx.set(dedupeRef, {
        'tripId': safeTripId,
        'passengerId': safePassengerId,
        'driverId': safeDriverId,
        'routeId': safeRouteId,
        'distanceMeters': distanceMeters,
        'notifiedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
