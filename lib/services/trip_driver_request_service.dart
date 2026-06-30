import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/driver_status.dart';
import '../models/schedule_slot.dart';
import '../models/trip_driver_request.dart';
import '../models/trip_status.dart';
import 'route_slot_booking_service.dart';

class TripDriverRequestService {
  TripDriverRequestService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  static const String _notificationsCollection = 'notifications';

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
    await _db.runTransaction((tx) async {
      await _assertTripStillAvailable(
        tx,
        driverId: safeDriver,
        routeId: safeRoute,
        slotId: safeSlot,
        seatsRequested: seatsRequested,
      );

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

      tx.set(ref, request.toMap());
    });
    await _createDriverRequestNotification(
      driverId: safeDriver,
      routeId: safeRoute,
      requestId: ref.id,
      lineLabel: lineLabel.trim(),
      seatsRequested: seatsRequested,
    );
    return ref.id;
  }

  Future<void> _assertTripStillAvailable(
    Transaction tx, {
    required String driverId,
    required String routeId,
    required String slotId,
    required int seatsRequested,
  }) async {
    final routeRef = _db.collection('route').doc(routeId);
    final driverRef = _db.collection('drivers').doc(driverId);

    final routeSnap = await tx.get(routeRef);
    final driverSnap = await tx.get(driverRef);

    if (!routeSnap.exists || routeSnap.data() == null) {
      throw Exception('This trip is no longer available.');
    }
    if (!driverSnap.exists || driverSnap.data() == null) {
      throw Exception('This trip is no longer available.');
    }

    final driverData = driverSnap.data()!;
    final isApproved = driverData['isApproved'] == true;
    final driverStatus = DriverStatus.normalize(
      driverData['status']?.toString(),
    );
    if (!isApproved || driverStatus != DriverStatus.onTrip) {
      throw Exception('This trip is no longer available.');
    }

    final currentRouteId = (driverData['currentRouteId'] ?? '').toString().trim();
    if (currentRouteId.isNotEmpty && currentRouteId != routeId) {
      throw Exception('This trip is no longer available.');
    }

    final currentTripId = (driverData['currentTripId'] ?? '').toString().trim();
    if (currentTripId.isNotEmpty && currentTripId != slotId) {
      throw Exception('This trip is no longer available.');
    }

    if (!_hasDriverLocation(driverData)) {
      throw Exception('This trip is no longer available.');
    }

    final routeData = routeSnap.data()!;
    final rawSlots = routeData['scheduleSlots'];
    if (rawSlots is! List) {
      throw Exception('This trip is no longer available.');
    }

    Map<String, dynamic>? slotMap;
    for (final rawSlot in rawSlots) {
      if (rawSlot is! Map) continue;
      final candidate = Map<String, dynamic>.from(rawSlot);
      if ((candidate['slotId'] ?? '').toString().trim() == slotId) {
        slotMap = candidate;
        break;
      }
    }

    if (slotMap == null) {
      throw Exception('This trip is no longer available.');
    }

    final slot = ScheduleSlot.fromMap(slotId, slotMap);
    final status = TripStatus.normalize(slot.status);
    final assignedDriver = slot.driverId.trim();
    if (status != TripStatus.onTrip || assignedDriver != driverId) {
      throw Exception('This trip is no longer available.');
    }

    if (slot.arrivalAt.isBefore(DateTime.now())) {
      throw Exception('This trip is no longer available.');
    }

    final availableSeats = slot.capacity - slot.passengersIds.length;
    if (availableSeats < 1) {
      throw Exception('This trip is no longer available.');
    }
    if (seatsRequested > availableSeats) {
      throw Exception('Not enough seats on this trip (only $availableSeats left).');
    }
  }

  bool _hasDriverLocation(Map<String, dynamic> driverData) {
    final lat = (driverData['latitude'] as num?)?.toDouble();
    final lng = (driverData['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null) return true;

    final location = driverData['location'];
    if (location is GeoPoint) return true;
    if (location is! Map) return false;

    final locLat =
        (location['lat'] as num?)?.toDouble() ??
        (location['latitude'] as num?)?.toDouble();
    final locLng =
        (location['lng'] as num?)?.toDouble() ??
        (location['longitude'] as num?)?.toDouble();
    return locLat != null && locLng != null;
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

  Stream<int> watchPendingCountForDriver(String driverId) {
    return watchPendingForDriver(driverId).map((list) => list.length);
  }

  Stream<int> watchUnacceptedCountForRoute(String routeId) {
    final safe = routeId.trim();
    if (safe.isEmpty) return Stream.value(0);

    return _db
        .collection(_collection)
        .where('routeId', isEqualTo: safe)
        .snapshots()
        .map((snap) {
          var count = 0;
          for (final doc in snap.docs) {
            final status = (doc.data()['status'] ?? '')
                .toString()
                .toLowerCase();
            if (status != TripDriverRequest.accepted) {
              count++;
            }
          }
          return count;
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

  Future<void> _createDriverRequestNotification({
    required String driverId,
    required String routeId,
    required String requestId,
    required String lineLabel,
    required int seatsRequested,
  }) async {
    final ref = _db.collection(_notificationsCollection).doc();
    final lineText = lineLabel.isEmpty ? 'مسارك' : lineLabel;
    final seatWord = seatsRequested == 1 ? 'مقعد' : 'مقاعد';
    final message = 'طلب راكب حجز $seatsRequested $seatWord على $lineText.';

    await ref.set({
      'notificationId': ref.id,
      'userId': driverId,
      'title': 'طلب رحلة جديد',
      'message': message,
      'body': message,
      'type': 'driver_request',
      'routeId': routeId,
      'requestId': requestId,
      'isRead': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
