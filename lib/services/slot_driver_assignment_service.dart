import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_status.dart';
import '../models/trip.dart';

/// After a new schedule slot is created, assigns the first FIFO driver from
/// `route/{routeId}/driverQueue` and creates `trips/{tripId}`.
///
/// Uses a transaction so two route managers cannot assign the same driver.
enum SlotAssignmentOutcome {
  assigned,
  noDriversInQueue,
}

class SlotDriverAssignmentResult {
  SlotDriverAssignmentResult._({
    required this.outcome,
    this.driverId,
    this.tripId,
  });

  factory SlotDriverAssignmentResult.assigned({
    required String driverId,
    required String tripId,
  }) {
    return SlotDriverAssignmentResult._(
      outcome: SlotAssignmentOutcome.assigned,
      driverId: driverId,
      tripId: tripId,
    );
  }

  factory SlotDriverAssignmentResult.noDrivers() {
    return SlotDriverAssignmentResult._(
      outcome: SlotAssignmentOutcome.noDriversInQueue,
    );
  }

  final SlotAssignmentOutcome outcome;
  final String? driverId;
  final String? tripId;
}

class SlotDriverAssignmentService {
  SlotDriverAssignmentService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Call only for **new** slots (not edits). Safe to call when queue is empty.
  Future<SlotDriverAssignmentResult> tryAssignDriverForNewSlot({
    required String routeId,
    required String slotId,
    required DateTime departureAt,
    required DateTime arrivalAt,
    int maxAttempts = 8,
  }) async {
    final queueCol = _db
        .collection('route')
        .doc(routeId)
        .collection('driverQueue');
    final driversCol = _db.collection('drivers');
    final tripsCol = _db.collection('trips');

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final head =
          await queueCol.orderBy('joinedAt', descending: false).limit(1).get();
      if (head.docs.isEmpty) {
        return SlotDriverAssignmentResult.noDrivers();
      }

      final driverId = head.docs.first.id;
      final tripRef = tripsCol.doc();

      final success = await _db.runTransaction<bool>((txn) async {
        final qRef = queueCol.doc(driverId);
        final qSnap = await txn.get(qRef);
        if (!qSnap.exists) return false;

        final dRef = driversCol.doc(driverId);
        final dSnap = await txn.get(dRef);
        if (!dSnap.exists) {
          txn.delete(qRef);
          return false;
        }

        final data = dSnap.data()!;
        final st = data['status'] as String?;
        if (st != DriverStatus.available) {
          txn.delete(qRef);
          return false;
        }

        final driverRoute = data['routeId'] as String? ?? '';
        if (driverRoute != routeId) {
          txn.delete(qRef);
          return false;
        }

        final trip = Trip(
          tripId: tripRef.id,
          driverId: driverId,
          routeId: routeId,
          slotId: slotId,
          passengersIds: <String>[],
          departureAt: departureAt,
          arrivalAt: arrivalAt,
        );

        txn.set(tripRef, trip.toMap());
        txn.update(dRef, {'status': DriverStatus.onTrip});
        txn.delete(qRef);
        return true;
      });

      if (success) {
        return SlotDriverAssignmentResult.assigned(
          driverId: driverId,
          tripId: tripRef.id,
        );
      }
    }

    return SlotDriverAssignmentResult.noDrivers();
  }
}
