import 'package:firebase_auth/firebase_auth.dart';

import '../services/notification_service.dart';

class TripNotificationController {
  TripNotificationController({
    NotificationService? notificationService,
    FirebaseAuth? auth,
  })  : _notificationService = notificationService ?? NotificationService(),
        _auth = auth ?? FirebaseAuth.instance;

  final NotificationService _notificationService;
  final FirebaseAuth _auth;

  Future<void> notifyPassengersTripStarted({
    required String routeId,
    required String tripId,
    required List<String> passengerIds,
  }) async {
    final driverId = (_auth.currentUser?.uid ?? '').trim();
    if (driverId.isEmpty) return;

    await _notificationService.createTripStartedNotifications(
      routeId: routeId,
      tripId: tripId,
      driverId: driverId,
      passengerIds: passengerIds,
    );
  }
}
