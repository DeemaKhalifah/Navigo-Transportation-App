import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/trip_driver_request.dart';
import 'route_slot_booking_service.dart';

class TripDriverRequestService {
  TripDriverRequestService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const String _collection = 'tripDriverRequests';

  String? get _uid => _auth.currentUser?.uid;

  Future<String> createRequest({
    required String driverId,
    required String routeId,
    required String scheduleId,
    required int seatsRequested,
    required String lineLabel,
    required String startPoint,
    required String endPoint,
    required String pickupDescription,
  }) async {
    final passengerId = _uid;
    if (passengerId == null || passengerId.isEmpty) {
      throw Exception('You must be signed in to request a trip.');
    }

    final safeDriver = driverId.trim();
    if (safeDriver.isEmpty) {
      throw Exception('Driver is missing.');
    }

    final safeRoute = routeId.trim();
    if (safeRoute.isEmpty) {
      throw Exception('Route is missing.');
    }

    final safeSlot = scheduleId.trim();
    if (safeSlot.isEmpty) {
      throw Exception('Trip slot is missing. Try refreshing the vehicle list.');
    }

    if (seatsRequested < 1) {
      throw Exception('Select at least one seat.');
    }

    final ref = _db.collection(_collection).doc();
    final request = TripDriverRequest(
      requestId: ref.id,
      passengerId: passengerId,
      driverId: safeDriver,
      routeId: safeRoute,
      slotId: safeSlot,
      seatsRequested: seatsRequested,
      lineLabel: lineLabel.trim(),
      startPoint: startPoint.trim(),
      endPoint: endPoint.trim(),
      pickupDescription: pickupDescription.trim(),
      status: TripDriverRequest.pending,
      createdAt: DateTime.now(),
    );

    await ref.set(request.toMap());
    return ref.id;
  }

  Stream<List<TripDriverRequest>> watchPendingForDriver(String driverId) {
    final safe = driverId.trim();
    if (safe.isEmpty) return Stream.value([]);

    return _db
        .collection(_collection)
        .where('driverId', isEqualTo: safe)
        .where('status', isEqualTo: TripDriverRequest.pending)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => TripDriverRequest.fromDoc(d))
              .toList();
          list.sort((a, b) {
            final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return tb.compareTo(ta);
          });
          return list;
        });
  }

  Future<void> acceptRequest(String requestId) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('You must be signed in.');
    }

    final safeReqId = requestId.trim();
    if (safeReqId.isEmpty) {
      throw Exception('Request ID is missing.');
    }

    final reqRef = _db.collection(_collection).doc(safeReqId);

    await _db.runTransaction((tx) async {
      final reqSnap = await tx.get(reqRef);
      if (!reqSnap.exists) {
        throw Exception('Request not found.');
      }

      final map = reqSnap.data() ?? {};
      final driverId = (map['driverId'] ?? '').toString().trim();
      if (driverId != uid) {
        throw Exception('Not allowed to update this request.');
      }

      final status = (map['status'] ?? '').toString();
      if (status != TripDriverRequest.pending) {
        throw Exception('This request is no longer pending.');
      }

      final routeId = (map['routeId'] ?? '').toString().trim();
      final slotId = (map['scheduleId'] ?? map['slotId'] ?? '')
          .toString()
          .trim();
      final passengerId = (map['passengerId'] ?? '').toString().trim();
      final seats = (map['seatsRequested'] as num?)?.toInt() ?? 1;

      await RouteSlotBookingService.appendPassengerSeatsWithTransaction(
        tx,
        _db,
        routeId: routeId,
        slotId: slotId,
        passengerId: passengerId,
        seatsToAdd: seats,
      );

      tx.update(reqRef, {
        'status': TripDriverRequest.accepted,
        'respondedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> declineRequest(String requestId) async {
    final uid = _uid;
    if (uid == null) return;

    final ref = _db.collection(_collection).doc(requestId.trim());
    final snap = await ref.get();
    if (!snap.exists) return;

    final driverId = (snap.data()?['driverId'] ?? '').toString().trim();
    if (driverId != uid) {
      throw Exception('Not allowed to update this request.');
    }

    await ref.update({
      'status': TripDriverRequest.declined,
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String?> passengerDisplayName(String passengerId) async {
    final snap = await _db.collection('users').doc(passengerId).get();
    final d = snap.data() ?? {};
    final first = (d['firstName'] ?? '').toString().trim();
    final last = (d['lastName'] ?? '').toString().trim();
    final full = '$first $last'.trim();
    return full.isEmpty ? null : full;
  }
}
