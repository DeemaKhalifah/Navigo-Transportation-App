import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/schedule_slot.dart';
import '../models/waiting_trip_request.dart';
import 'schedule_slot_repository.dart';
import 'slot_driver_assignment_service.dart';

class WaitingTripRequestService {
  WaitingTripRequestService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const int _managerNotifyPassengerThreshold = 4;
  static const int _timeWindowMinutes = 15;

  Stream<List<WaitingTripGroup>> watchPendingGroupsForRoute(String routeId) {
    final safeRouteId = routeId.trim();
    if (safeRouteId.isEmpty) return Stream.value(const []);

    return _db
        .collection('waitingTripGroups')
        .where('routeId', isEqualTo: safeRouteId)
        .where('status', whereIn: ['pending', 'manager_notified'])
        .snapshots()
        .map((snapshot) {
          final groups = snapshot.docs
              .map((doc) => WaitingTripGroup.fromMap(doc.id, doc.data()))
              .toList();
          groups.sort((a, b) => a.departureAt.compareTo(b.departureAt));
          return groups;
        });
  }

  Stream<List<WaitingTripRequest>> watchRequestsForGroup(String groupId) {
    final safeGroupId = groupId.trim();
    if (safeGroupId.isEmpty) return Stream.value(const []);

    return _db
        .collection('waitingTripRequests')
        .where('groupId', isEqualTo: safeGroupId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map((doc) => WaitingTripRequest.fromMap(doc.id, doc.data()))
              .toList();
          requests.sort((a, b) => a.requestedAt.compareTo(b.requestedAt));
          return requests;
        });
  }

  Future<WaitingTripSubmitResult> submitRequest({
    required String selectedLine,
    required DateTime selectedDate,
    required int hour,
    required int minute,
    required String? vehicleType,
    required int seatsRequested,
    String? pickupLocationDescription,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) {
      throw const WaitingTripRequestException('waitingListLoginRequired');
    }
    if (selectedLine.trim().isEmpty) {
      throw const WaitingTripRequestException('selectLineFirst');
    }
    if (seatsRequested <= 0) {
      throw const WaitingTripRequestException('waitingListSelectSeat');
    }

    final route = await _resolveRoute(selectedLine);
    final routeId = route.id;
    final normalizedVehicle = _normalizeVehicleType(vehicleType);
    final departureAt = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      hour,
      minute,
    );
    if (departureAt.isBefore(DateTime.now())) {
      throw const WaitingTripRequestException('waitingListFutureDateTime');
    }

    final existingGroupId = await _findMatchingPendingGroupId(
      routeId: routeId,
      departureAt: departureAt,
      vehicleType: normalizedVehicle,
    );
    final groupId =
        existingGroupId ?? _groupId(routeId, departureAt, normalizedVehicle);
    final requestId = '${groupId}_$uid';
    final groupRef = _db.collection('waitingTripGroups').doc(groupId);
    final requestRef = _db.collection('waitingTripRequests').doc(requestId);
    final routeRef = _db.collection('route').doc(routeId);
    final requestedAt = DateTime.now();
    final managerIds = await _routeManagerUserIds(routeId);
    final passengerName = await _currentPassengerName(uid);

    final result = await _db.runTransaction<WaitingTripSubmitResult>((
      tx,
    ) async {
      final freshRouteSnap = await tx.get(routeRef);
      if (!freshRouteSnap.exists || freshRouteSnap.data() == null) {
        throw const WaitingTripRequestException('waitingListRouteNotFound');
      }

      final freshRouteData = freshRouteSnap.data()!;
      final groupSnap = await tx.get(groupRef);
      final existingPassengers = <String>{
        if (groupSnap.exists)
          ...List<String>.from(groupSnap.data()?['passengerIds'] ?? const []),
      };
      existingPassengers.add(uid);

      final requestEntry = {
        'passengerId': uid,
        'passengerName': passengerName,
        'seatsRequested': seatsRequested,
        'pickupLocationDescription': (pickupLocationDescription ?? '').trim(),
        'requestedAt': Timestamp.fromDate(requestedAt),
      };

      final request = WaitingTripRequest(
        requestId: requestId,
        groupId: groupId,
        routeId: routeId,
        passengerId: uid,
        passengerName: passengerName,
        requestedAt: requestedAt,
        departureAt: departureAt,
        seatsRequested: seatsRequested,
        vehicleType: normalizedVehicle,
        pickupLocationDescription: (pickupLocationDescription ?? '').trim(),
        status: 'pending',
      );

      tx.set(requestRef, {
        ...request.toMap(),
        'requestedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final groupRequests = _mergeGroupRequests(
        groupSnap.data()?['requests'],
        requestEntry,
      );
      final totalRequestedSeats = _totalRequestedSeats(groupRequests);
      final alreadyNotified = groupSnap.data()?['routeManagerNotified'] == true;
      final shouldNotifyManager =
          managerIds.isNotEmpty &&
          !alreadyNotified &&
          existingPassengers.length >= _managerNotifyPassengerThreshold;

      final groupDepartureAt =
          _parseDate(groupSnap.data()?['departureAt']) ?? departureAt;
      final groupData = {
        'groupId': groupId,
        'routeId': routeId,
        'lineLabel': _lineLabel(routeId, freshRouteData),
        'departureAt': Timestamp.fromDate(groupDepartureAt),
        'dateKey': _dateKey(groupDepartureAt),
        'timeKey': _timeKey(groupDepartureAt),
        'vehicleType': normalizedVehicle,
        'passengerIds': existingPassengers.toList(),
        'passengerCount': existingPassengers.length,
        'requestedSeatCount': totalRequestedSeats,
        'requests': groupRequests,
        'status': alreadyNotified || shouldNotifyManager
            ? 'manager_notified'
            : 'pending',
        'routeManagerNotified': alreadyNotified || shouldNotifyManager,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!groupSnap.exists) 'createdAt': FieldValue.serverTimestamp(),
      };

      tx.set(groupRef, groupData, SetOptions(merge: true));

      if (shouldNotifyManager) {
        for (final managerId in managerIds) {
          final notificationRef = _db.collection('notifications').doc();
          tx.set(notificationRef, {
            'notificationId': notificationRef.id,
            'userId': managerId,
            'title': 'Waiting list trip request',
            'message': _managerNotificationMessage(
              departureAt: groupDepartureAt,
              passengerCount: existingPassengers.length,
              requestedSeatCount: totalRequestedSeats,
            ),
            'body': _managerNotificationMessage(
              departureAt: groupDepartureAt,
              passengerCount: existingPassengers.length,
              requestedSeatCount: totalRequestedSeats,
            ),
            'titleKey': 'waitingTripManagerTitle',
            'messageKey': 'waitingTripManagerMessage',
            'type': 'waiting_trip_manager_request',
            'routeId': routeId,
            'waitingTripGroupId': groupId,
            'departureAt': Timestamp.fromDate(groupDepartureAt),
            'requestedSeatCount': totalRequestedSeats,
            'passengerCount': existingPassengers.length,
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      }

      return WaitingTripSubmitResult(
        routeManagerNotified: shouldNotifyManager,
        groupId: groupId,
        routeId: routeId,
        waitingPassengerCount: existingPassengers.length,
        waitingSeatCount: totalRequestedSeats,
      );
    });

    return result;
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>> _resolveRoute(
    String selectedLine,
  ) async {
    final safeLine = selectedLine.trim().toLowerCase();
    final snap = await _db.collection('route').get();
    for (final doc in snap.docs) {
      final data = doc.data();
      final aliases = _lineAliases(
        doc.id,
        data,
      ).map((value) => value.trim().toLowerCase()).toList();
      if (aliases.any(
        (line) =>
            line == safeLine ||
            line.contains(safeLine) ||
            safeLine.contains(line),
      )) {
        return doc;
      }
    }
    throw const WaitingTripRequestException('waitingListRouteNotFound');
  }

  Future<void> completeGroupWithTrip({
    required String groupId,
    required String tripId,
  }) async {
    final groupRef = _db.collection('waitingTripGroups').doc(groupId);
    final groupSnap = await groupRef.get();
    if (!groupSnap.exists) return;

    final groupData = groupSnap.data() ?? {};
    final passengerIds = List<String>.from(
      groupData['passengerIds'] ?? const [],
    ).where((id) => id.trim().isNotEmpty).toSet().toList();
    final routeId = (groupData['routeId'] ?? '').toString();

    final batch = _db.batch();
    batch.set(groupRef, {
      'status': 'trip_created',
      'tripId': tripId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final snap = await _db
        .collection('waitingTripRequests')
        .where('groupId', isEqualTo: groupId)
        .where('status', isEqualTo: 'pending')
        .get();
    for (final doc in snap.docs) {
      batch.set(doc.reference, {
        'status': 'trip_created',
        'tripId': tripId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    for (final passengerId in passengerIds) {
      final notificationRef = _db.collection('notifications').doc();
      batch.set(notificationRef, {
        'notificationId': notificationRef.id,
        'userId': passengerId,
        'title': 'New trip created',
        'message': 'A new trip was created for your requested date and time.',
        'body': 'A new trip was created for your requested date and time.',
        'titleKey': 'waitingTripCreatedTitle',
        'messageKey': 'waitingTripCreatedMessage',
        'type': 'waiting_trip_created',
        'routeId': routeId,
        'tripId': tripId,
        'waitingTripGroupId': groupId,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Future<String> makeTripForGroup(WaitingTripGroup group) async {
    final groupRef = _db.collection('waitingTripGroups').doc(group.groupId);
    final routeRef = _db.collection('route').doc(group.routeId);

    final groupSnap = await groupRef.get();
    if (!groupSnap.exists) {
      throw const WaitingTripRequestException('waitingListRouteNotFound');
    }

    final status = (groupSnap.data()?['status'] ?? '').toString();
    final existingTripId = (groupSnap.data()?['tripId'] ?? '').toString();
    if (status == 'trip_created' && existingTripId.trim().isNotEmpty) {
      return existingTripId.trim();
    }

    final routeSnap = await routeRef.get();
    if (!routeSnap.exists) {
      throw const WaitingTripRequestException('waitingListRouteNotFound');
    }

    final routeData = routeSnap.data() ?? {};
    final departureAt =
        _parseDate(groupSnap.data()?['departureAt']) ?? group.departureAt;
    final vehicleType = _tripVehicleType(
      group.vehicleType,
      group.requestedSeatCount,
    );
    final etaMinutes = (routeData['etaMinutes'] as num?)?.toInt();
    final arrivalAt = departureAt.add(
      Duration(minutes: etaMinutes ?? (vehicleType == 'bus' ? 60 : 45)),
    );
    final price = (routeData['price'] as num?)?.toDouble();

    final slot = ScheduleSlot(
      slotId: '',
      routeId: group.routeId,
      departureAt: departureAt,
      arrivalAt: arrivalAt,
      price: price,
      capacity: _capacityForWaitingTrip(vehicleType, group.requestedSeatCount),
      vehicleType: vehicleType,
    );

    final slotId = await ScheduleSlotRepository(firestore: _db).addSlot(slot);
    await SlotDriverAssignmentService(
      firestore: _db,
    ).autoAssignUpcomingUnassignedSlots(routeId: group.routeId);
    await completeGroupWithTrip(groupId: group.groupId, tripId: slotId);
    return slotId;
  }

  Future<String?> _findMatchingPendingGroupId({
    required String routeId,
    required DateTime departureAt,
    required String vehicleType,
  }) async {
    final snap = await _db
        .collection('waitingTripGroups')
        .where('routeId', isEqualTo: routeId)
        .where('dateKey', isEqualTo: _dateKey(departureAt))
        .where('vehicleType', isEqualTo: vehicleType)
        .where('status', whereIn: ['pending', 'manager_notified'])
        .get();

    String? bestGroupId;
    var bestDifference = _timeWindowMinutes + 1;
    for (final doc in snap.docs) {
      final groupDeparture = _parseDate(doc.data()['departureAt']);
      if (groupDeparture == null) continue;
      final diff = groupDeparture.difference(departureAt).inMinutes.abs();
      if (diff <= _timeWindowMinutes && diff < bestDifference) {
        bestDifference = diff;
        bestGroupId = doc.id;
      }
    }

    return bestGroupId;
  }

  Future<List<String>> _routeManagerUserIds(String routeId) async {
    final userIds = <String>{};

    final usersSnap = await _db
        .collection('users')
        .where('role', isEqualTo: 'route_manager')
        .where('routeId', isEqualTo: routeId)
        .get();
    for (final doc in usersSnap.docs) {
      userIds.add(doc.id);
    }

    final legacyManagersSnap = await _db
        .collection('route_manger')
        .where('routeId', isEqualTo: routeId)
        .get();
    for (final doc in legacyManagersSnap.docs) {
      final userId = (doc.data()['userId'] ?? doc.id).toString().trim();
      if (userId.isNotEmpty) userIds.add(userId);
    }

    final managersSnap = await _db
        .collection('route_manager')
        .where('routeId', isEqualTo: routeId)
        .get();
    for (final doc in managersSnap.docs) {
      final userId = (doc.data()['userId'] ?? doc.id).toString().trim();
      if (userId.isNotEmpty) userIds.add(userId);
    }

    return userIds.toList();
  }

  Future<String> _currentPassengerName(String uid) async {
    final userSnap = await _db.collection('users').doc(uid).get();
    final data = userSnap.data() ?? {};
    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    final joinedName = '$firstName $lastName'.trim();
    final name = (data['fullName'] ?? data['name'] ?? joinedName)
        .toString()
        .trim();
    return name;
  }

  String _managerNotificationMessage({
    required DateTime departureAt,
    required int passengerCount,
    required int requestedSeatCount,
  }) {
    return 'Waiting list reached $requestedSeatCount requested seats from '
        '$passengerCount passengers.\n'
        'Date: ${_displayDate(departureAt)}\n'
        'Time: ${_displayTime(departureAt)}\n'
        'Seats: $requestedSeatCount';
  }

  String _tripVehicleType(String value, int requestedSeats) {
    final normalized = ScheduleSlot.normalizeVehicleType(value);
    if (requestedSeats > 7) return 'bus';
    if (normalized == 'bus') return 'bus';
    return 'microbus';
  }

  int _capacityForWaitingTrip(String vehicleType, int requestedSeats) {
    if (vehicleType == 'bus') return requestedSeats > 14 ? 45 : 14;
    return requestedSeats > 7 ? requestedSeats : 7;
  }

  List<Map<String, dynamic>> _mergeGroupRequests(
    dynamic raw,
    Map<String, dynamic> requestEntry,
  ) {
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(
            Map<String, dynamic>.from(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      }
    }
    final passengerId = (requestEntry['passengerId'] ?? '').toString();
    final index = list.indexWhere((item) => item['passengerId'] == passengerId);
    if (index >= 0) {
      list[index] = requestEntry;
    } else {
      list.add(requestEntry);
    }
    return list;
  }

  int _totalRequestedSeats(List<Map<String, dynamic>> requests) {
    return requests.fold<int>(
      0,
      (total, item) => total + ((item['seatsRequested'] as num?)?.toInt() ?? 1),
    );
  }

  String _normalizeVehicleType(String? value) {
    final v = (value ?? '').toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    if (v.contains('bus') && !v.contains('micro')) return 'bus';
    return 'microbus';
  }

  String _lineLabel(String routeId, Map<String, dynamic> data) {
    final fromText = (data['startPoint'] ?? data['from'] ?? '')
        .toString()
        .trim();
    final toText = (data['endPoint'] ?? data['to'] ?? '').toString().trim();
    return (data['line'] ??
            data['routeName'] ??
            (fromText.isNotEmpty && toText.isNotEmpty
                ? '$fromText ↔ $toText'
                : 'Route $routeId'))
        .toString()
        .trim();
  }

  List<String> _lineAliases(String routeId, Map<String, dynamic> data) {
    final fromText = (data['startPoint'] ?? data['from'] ?? '')
        .toString()
        .trim();
    final toText = (data['endPoint'] ?? data['to'] ?? '').toString().trim();
    final explicitLine = (data['line'] ?? data['routeName'] ?? '')
        .toString()
        .trim();

    return {
      _lineLabel(routeId, data),
      if (explicitLine.isNotEmpty) explicitLine,
      if (fromText.isNotEmpty && toText.isNotEmpty) '$fromText <-----> $toText',
      if (fromText.isNotEmpty && toText.isNotEmpty) '$fromText ↔ $toText',
      if (fromText.isNotEmpty && toText.isNotEmpty) '$fromText -> $toText',
      if (fromText.isNotEmpty && toText.isNotEmpty) '$fromText → $toText',
      routeId,
      (data['routeId'] ?? '').toString().trim(),
    }.where((value) => value.trim().isNotEmpty).toList();
  }

  String _groupId(String routeId, DateTime date, String vehicleType) {
    final safeRoute = routeId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return '${safeRoute}_${_dateKey(date)}_${_timeKey(date)}_$vehicleType';
  }

  String _dateKey(DateTime date) {
    return '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  String _timeKey(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}';
  }

  String _displayDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _displayTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
