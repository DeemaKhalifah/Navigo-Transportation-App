import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/admin_dashboard_model.dart';

class AdminDashboardService {
  AdminDashboardService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Stream<AdminDashboardModel> dashboardStream() {
    return _db.collection('drivers').snapshots().asyncMap((driversSnap) async {
      final usersSnap = await _db.collection('users').get();
      final routesSnap = await _db.collection('route').get();
      final supportReportsSnap = await _db.collection('supportReports').get();

      final pendingDrivers = driversSnap.docs.where((doc) {
        final data = doc.data();
        final status = (data['approvalStatus'] ?? '').toString().toLowerCase();
        return data['isApproved'] != true && status != 'rejected';
      }).toList();

      final approvals = pendingDrivers.map((doc) {
        final data = doc.data();
        final firstName = (data['firstName'] ?? '').toString().trim();
        final lastName = (data['lastName'] ?? '').toString().trim();
        final fullName = '$firstName $lastName'.trim();
        final userId = (data['userId'] ?? data['uid'] ?? doc.id).toString();
        final name = (data['fullName'] ?? data['name'] ?? fullName)
            .toString()
            .trim();
        final vehicleType = (data['vehicleType'] ?? 'Vehicle').toString();
        final phone = (data['phoneNumber'] ?? data['phone'] ?? '').toString();

        return AdminApprovalItem(
          id: doc.id,
          userId: userId,
          type: 'Driver',
          name: name.isEmpty ? 'Unknown driver' : name,
          details: phone.isEmpty ? vehicleType : '$vehicleType - $phone',
          status: 'Pending',
        );
      }).toList();

      final notificationsSnap = await _db
          .collection('notifications')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();

      final activities = notificationsSnap.docs.map((doc) {
        final data = doc.data();

        return AdminActivityItem(
          title: (data['title'] ?? 'System activity').toString(),
          subtitle: (data['body'] ?? data['message'] ?? '').toString(),
          timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
        );
      }).toList();

      final reports = _reportsFromSnapshot(supportReportsSnap, limit: 10);

      var activeTrips = 0;

      for (final routeDoc in routesSnap.docs) {
        final data = routeDoc.data();
        final slots = data['scheduleSlots'];

        if (slots is List) {
          for (final slot in slots) {
            if (slot is Map) {
              final status = slot['status']?.toString().toLowerCase() ?? '';

              if (status == 'ongoing' ||
                  status == 'ontrip' ||
                  status == 'active' ||
                  status == 'started') {
                activeTrips++;
              }
            }
          }
        }
      }

      return AdminDashboardModel(
        totalUsers: usersSnap.docs.length,
        totalDrivers: driversSnap.docs.length,
        pendingDrivers: pendingDrivers.length,
        totalRoutes: routesSnap.docs.length,
        activeTrips: activeTrips,
        activities: activities,
        approvals: approvals,
        reports: reports.take(10).toList(),
      );
    });
  }

  Stream<List<AdminReportItem>> adminReportsStream() {
    return _db
        .collection('supportReports')
        .snapshots()
        .map((snapshot) => _reportsFromSnapshot(snapshot));
  }

  Stream<List<AdminDriverItem>> adminDriversStream() {
    return _db.collection('drivers').snapshots().asyncMap((driversSnap) async {
      final usersSnap = await _db.collection('users').get();
      final vehiclesSnap = await _db.collection('vehicles').get();
      final routesSnap = await _db.collection('route').get();
      final usersById = {
        for (final doc in usersSnap.docs) doc.id: doc.data(),
      };
      final vehiclesByDriverId = {
        for (final doc in vehiclesSnap.docs)
          _readString(doc.data()['driverId']): doc.data(),
      };
      final vehiclesById = {
        for (final doc in vehiclesSnap.docs) doc.id: doc.data(),
      };
      final routesById = {
        for (final doc in routesSnap.docs) doc.id: doc.data(),
      };
      for (final doc in routesSnap.docs) {
        final routeId = _readString(doc.data()['routeId']);
        if (routeId.isNotEmpty) {
          routesById[routeId] = doc.data();
        }
      }

      final drivers = driversSnap.docs.map((doc) {
        final driverData = doc.data();
        final userId = _readString(
          driverData['userId'] ?? driverData['uid'] ?? doc.id,
        );
        final userData = usersById[userId] ?? const <String, dynamic>{};
        final firstName = _readString(
          userData['firstName'] ?? driverData['firstName'],
        );
        final lastName = _readString(
          userData['lastName'] ?? driverData['lastName'],
        );
        final fullName = _readString(
          userData['fullName'] ??
              userData['name'] ??
              driverData['fullName'] ??
              driverData['name'] ??
              '$firstName $lastName',
        );
        final isApproved = driverData['isApproved'] == true ||
            userData['driverIsApproved'] == true;
        final approvalStatus = _readString(
          driverData['approvalStatus'] ?? userData['driverApprovalStatus'],
        );
        final vehicleId = _readString(driverData['vehicleId']);
        final vehicleData = vehiclesByDriverId[doc.id] ??
            vehiclesByDriverId[userId] ??
            vehiclesById[vehicleId] ??
            const <String, dynamic>{};
        final routeId = _readString(driverData['routeId']);
        final routeData = routesById[routeId] ?? const <String, dynamic>{};

        return AdminDriverItem(
          driverId: doc.id,
          userId: userId,
          fullName: fullName.isEmpty ? 'Unknown driver' : fullName,
          email: _readString(userData['email'] ?? driverData['email']),
          phone: _readString(
            userData['phone'] ??
                userData['phoneNumber'] ??
                driverData['phone'] ??
                driverData['phoneNumber'],
          ),
          status: _readString(driverData['status']).isEmpty
              ? 'offline'
              : _readString(driverData['status']),
          approvalStatus: approvalStatus.isEmpty
              ? (isApproved ? 'approved' : 'pending')
              : approvalStatus,
          isApproved: isApproved,
          isOnline: driverData['isOnline'] == true,
          routeId: routeId,
          routeLabel: _routeLabel(routeData, routeId),
          vehicleId: vehicleId.isEmpty ? _readString(vehicleData['vehicleId']) : vehicleId,
          vehicleType: _readString(
            vehicleData['vehicleType'] ??
                vehicleData['type'] ??
                driverData['vehicleType'] ??
                driverData['type'],
          ),
          plateNumber: _readString(
            vehicleData['plateNumber'] ?? driverData['plateNumber'],
          ),
          licenseNumber: _readString(
            vehicleData['licenseNumber'] ?? driverData['licenseNumber'],
          ),
          createdAt: _readDate(driverData['createdAt'] ?? userData['createdAt']),
          updatedAt: _readDate(driverData['updatedAt'] ?? userData['updatedAt']),
        );
      }).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));

      return drivers;
    });
  }

  Stream<List<AdminPassengerItem>> adminPassengersStream() {
    return _db.collection('passengers').snapshots().asyncMap((
      passengersSnap,
    ) async {
      final usersSnap = await _db.collection('users').get();
      final usersById = {
        for (final doc in usersSnap.docs) doc.id: doc.data(),
      };

      final passengers = passengersSnap.docs.map((doc) {
        final passengerData = doc.data();
        final userId = _readString(
          passengerData['userId'] ?? passengerData['passengerId'] ?? doc.id,
        );
        final userData = usersById[userId] ?? const <String, dynamic>{};
        final firstName = _readString(
          userData['firstName'] ?? passengerData['firstName'],
        );
        final lastName = _readString(
          userData['lastName'] ?? passengerData['lastName'],
        );
        final fullName = _readString(
          userData['fullName'] ??
              userData['name'] ??
              passengerData['fullName'] ??
              passengerData['name'] ??
              '$firstName $lastName',
        );

        return AdminPassengerItem(
          passengerId: doc.id,
          userId: userId,
          fullName: fullName.isEmpty ? 'Unknown passenger' : fullName,
          email: _readString(userData['email'] ?? passengerData['email']),
          phone: _readString(
            userData['phone'] ??
                userData['phoneNumber'] ??
                passengerData['phone'] ??
                passengerData['phoneNumber'],
          ),
          isVerified:
              userData['isVerified'] == true || passengerData['isVerified'] == true,
          isOnline:
              userData['isOnline'] == true || passengerData['isOnline'] == true,
          pickupLocationDescription: _readString(
            passengerData['pickupLocationDescription'] ??
                userData['pickupLocationDescription'],
          ),
          latitude: _readDouble(passengerData['latitude'] ?? userData['latitude']),
          longitude:
              _readDouble(passengerData['longitude'] ?? userData['longitude']),
          lastLocationUpdate: _readDate(
            passengerData['lastLocationUpdate'] ?? userData['lastLocationUpdate'],
          ),
          createdAt: _readDate(passengerData['createdAt'] ?? userData['createdAt']),
          updatedAt: _readDate(passengerData['updatedAt'] ?? userData['updatedAt']),
        );
      }).toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));

      final existingPassengerIds = passengers
          .map((passenger) => passenger.userId)
          .where((id) => id.isNotEmpty)
          .toSet();

      for (final userDoc in usersSnap.docs) {
        final userData = userDoc.data();
        final role = _readString(userData['role']).toLowerCase();

        if (role != 'passenger' || existingPassengerIds.contains(userDoc.id)) {
          continue;
        }

        final firstName = _readString(userData['firstName']);
        final lastName = _readString(userData['lastName']);
        final fullName = _readString(
          userData['fullName'] ?? userData['name'] ?? '$firstName $lastName',
        );

        passengers.add(
          AdminPassengerItem(
            passengerId: userDoc.id,
            userId: userDoc.id,
            fullName: fullName.isEmpty ? 'Unknown passenger' : fullName,
            email: _readString(userData['email']),
            phone: _readString(userData['phone'] ?? userData['phoneNumber']),
            isVerified: userData['isVerified'] == true,
            isOnline: userData['isOnline'] == true,
            pickupLocationDescription: _readString(
              userData['pickupLocationDescription'],
            ),
            latitude: _readDouble(userData['latitude']),
            longitude: _readDouble(userData['longitude']),
            lastLocationUpdate: _readDate(userData['lastLocationUpdate']),
            createdAt: _readDate(userData['createdAt']),
            updatedAt: _readDate(userData['updatedAt']),
          ),
        );
      }

      passengers.sort((a, b) => a.fullName.compareTo(b.fullName));

      return passengers;
    });
  }

  Stream<List<AdminTripItem>> adminTripsStream() {
    return _db.collection('route').snapshots().map((routesSnap) {
      final trips = <AdminTripItem>[];

      for (final routeDoc in routesSnap.docs) {
        final routeData = routeDoc.data();
        final routeId = _readString(routeData['routeId']).isEmpty
            ? routeDoc.id
            : _readString(routeData['routeId']);
        final routeLabel = _routeLabel(routeData, routeId);
        final slots = routeData['scheduleSlots'];

        if (slots is! List) continue;

        for (var index = 0; index < slots.length; index++) {
          final rawSlot = slots[index];
          if (rawSlot is! Map) continue;

          final slot = Map<String, dynamic>.from(
            rawSlot.map((key, value) => MapEntry(key.toString(), value)),
          );
          final passengerBookings = _passengerBookings(slot['passengersIds']);

          trips.add(
            AdminTripItem(
              routeId: routeId,
              routeLabel: routeLabel.isEmpty ? 'Unnamed route' : routeLabel,
              slotId: _readString(slot['slotId']).isEmpty
                  ? '${routeDoc.id}-$index'
                  : _readString(slot['slotId']),
              departureAt: _readDate(slot['departureAt']),
              arrivalAt: _readDate(slot['arrivalAt']),
              status: _readString(slot['status']).isEmpty
                  ? 'scheduled'
                  : _readString(slot['status']),
              vehicleType: _readString(slot['vehicleType']).isEmpty
                  ? 'Vehicle'
                  : _readString(slot['vehicleType']),
              driverId: _readString(slot['driverId']),
              capacity: _readInt(slot['capacity']),
              passengerCount: passengerBookings,
              price: _readNullableDouble(slot['price']),
            ),
          );
        }
      }

      trips.sort((a, b) {
        final aDate = a.departureAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.departureAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aDate.compareTo(bDate);
      });

      return trips;
    });
  }

  Future<void> approveDriver(AdminApprovalItem item) async {
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();

    batch.set(_db.collection('drivers').doc(item.id), {
      'isApproved': true,
      'approvalStatus': 'approved',
      'approvedAt': now,
      'rejectedAt': FieldValue.delete(),
      'rejectionReason': FieldValue.delete(),
      'updatedAt': now,
    }, SetOptions(merge: true));

    final userId = item.userId.trim();
    if (userId.isNotEmpty) {
      batch.set(_db.collection('users').doc(userId), {
        'driverIsApproved': true,
        'driverApprovalStatus': 'approved',
        'driverApprovedAt': now,
        'driverRejectedAt': FieldValue.delete(),
        'driverRejectionReason': FieldValue.delete(),
        'updatedAt': now,
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<void> rejectDriver(AdminApprovalItem item) async {
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();

    batch.set(_db.collection('drivers').doc(item.id), {
      'isApproved': false,
      'approvalStatus': 'rejected',
      'rejectedAt': now,
      'approvedAt': FieldValue.delete(),
      'updatedAt': now,
    }, SetOptions(merge: true));

    final userId = item.userId.trim();
    if (userId.isNotEmpty) {
      batch.set(_db.collection('users').doc(userId), {
        'driverIsApproved': false,
        'driverApprovalStatus': 'rejected',
        'driverRejectedAt': now,
        'driverApprovedAt': FieldValue.delete(),
        'updatedAt': now,
      }, SetOptions(merge: true));
    }

    await batch.commit();
  }

  String _readString(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);

    return null;
  }

  double? _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);

    return null;
  }

  double? _readNullableDouble(dynamic value) {
    if (value == null) return null;
    return _readDouble(value);
  }

  int _readInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;

    return 0;
  }

  int _passengerBookings(dynamic value) {
    if (value is! List) return 0;
    return value.length;
  }

  String _routeLabel(Map<String, dynamic> routeData, String fallbackRouteId) {
    final start = _readString(
      routeData['startPoint'] ?? routeData['start'] ?? routeData['from'],
    );
    final end = _readString(
      routeData['endPoint'] ?? routeData['end'] ?? routeData['to'],
    );

    if (start.isNotEmpty && end.isNotEmpty) return '$start to $end';
    if (start.isNotEmpty) return start;
    if (end.isNotEmpty) return end;

    return '';
  }

  List<AdminReportItem> _reportsFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    int? limit,
  }) {
    final reports = snapshot.docs.where((doc) {
      final data = doc.data();
      final status = _readString(data['status']).toLowerCase();

      // Route managers send reports to admin by setting this status.
      // The sentToAdminAt fallback keeps older sent reports visible too.
      return status == 'sent_to_admin' || data['sentToAdminAt'] != null;
    }).map((doc) {
      final data = doc.data();
      final reportId = _readString(data['reportId']);
      final senderName = _readString(data['senderName']);
      final senderRole = _readString(data['senderRole']);
      final routeLabel = _readString(data['routeLabel']);
      final message = _readString(data['message']);
      final status = _readString(data['status']);

      return AdminReportItem(
        id: reportId.isEmpty ? doc.id : reportId,
        senderName: senderName.isEmpty ? 'Unknown sender' : senderName,
        senderRole: senderRole.isEmpty ? 'Route manager' : senderRole,
        routeId: _readString(data['routeId']),
        routeLabel: routeLabel.isEmpty ? 'No route selected' : routeLabel,
        message: message.isEmpty ? 'No report message' : message,
        status: status.isEmpty ? 'sent_to_admin' : status,
        createdAt: _readDate(data['createdAt']),
        sentToAdminAt: _readDate(data['sentToAdminAt']),
      );
    }).toList()
      ..sort((a, b) {
        final aDate = a.sentToAdminAt ??
            a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.sentToAdminAt ??
            b.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);

        return bDate.compareTo(aDate);
      });

    if (limit == null) return reports;

    return reports.take(limit).toList();
  }
}
