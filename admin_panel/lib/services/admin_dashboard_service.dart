import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/admin_dashboard_model.dart';
import 'admin_route_path_service.dart';

class AdminDashboardService {
  AdminDashboardService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    AdminRoutePathService? routePathService,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance,
       _routePathService = routePathService ?? AdminRoutePathService();

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final AdminRoutePathService _routePathService;

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
      final usersById = {for (final doc in usersSnap.docs) doc.id: doc.data()};
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
        final isApproved =
            driverData['isApproved'] == true ||
            userData['driverIsApproved'] == true;
        final approvalStatus = _readString(
          driverData['approvalStatus'] ?? userData['driverApprovalStatus'],
        );
        final vehicleId = _readString(driverData['vehicleId']);
        final vehicleData =
            vehiclesByDriverId[doc.id] ??
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
          vehicleId: vehicleId.isEmpty
              ? _readString(vehicleData['vehicleId'])
              : vehicleId,
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
          createdAt: _readDate(
            driverData['createdAt'] ?? userData['createdAt'],
          ),
          updatedAt: _readDate(
            driverData['updatedAt'] ?? userData['updatedAt'],
          ),
        );
      }).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));

      return drivers;
    });
  }

  Stream<List<AdminPassengerItem>> adminPassengersStream() {
    return _db.collection('passengers').snapshots().asyncMap((
      passengersSnap,
    ) async {
      final usersSnap = await _db.collection('users').get();
      final usersById = {for (final doc in usersSnap.docs) doc.id: doc.data()};

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
              userData['isVerified'] == true ||
              passengerData['isVerified'] == true,
          isOnline:
              userData['isOnline'] == true || passengerData['isOnline'] == true,
          pickupLocationDescription: _readString(
            passengerData['pickupLocationDescription'] ??
                userData['pickupLocationDescription'],
          ),
          latitude: _readDouble(
            passengerData['latitude'] ?? userData['latitude'],
          ),
          longitude: _readDouble(
            passengerData['longitude'] ?? userData['longitude'],
          ),
          lastLocationUpdate: _readDate(
            passengerData['lastLocationUpdate'] ??
                userData['lastLocationUpdate'],
          ),
          createdAt: _readDate(
            passengerData['createdAt'] ?? userData['createdAt'],
          ),
          updatedAt: _readDate(
            passengerData['updatedAt'] ?? userData['updatedAt'],
          ),
        );
      }).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));

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

  Stream<List<AdminRouteItem>> adminRoutesStream() {
    return _db.collection('route').snapshots().map((routesSnap) {
      final routes =
          routesSnap.docs.map((doc) {
            final data = doc.data();
            final routeId = _readString(data['routeId']).isEmpty
                ? doc.id
                : _readString(data['routeId']);
            final slots = data['scheduleSlots'];
            final driverQueue = data['driverQueueIds'];
            final startLocation = data['startLocation'];
            final endLocation = data['endLocation'];

            return AdminRouteItem(
              documentId: doc.id,
              routeId: routeId,
              startPoint: _readString(
                data['startPoint'] ?? data['start'] ?? data['from'],
              ),
              endPoint: _readString(
                data['endPoint'] ?? data['end'] ?? data['to'],
              ),
              startLatitude: startLocation is Map
                  ? _readDouble(
                      startLocation['lat'] ?? startLocation['latitude'],
                    )
                  : null,
              startLongitude: startLocation is Map
                  ? _readDouble(
                      startLocation['lng'] ?? startLocation['longitude'],
                    )
                  : null,
              endLatitude: endLocation is Map
                  ? _readDouble(endLocation['lat'] ?? endLocation['latitude'])
                  : null,
              endLongitude: endLocation is Map
                  ? _readDouble(endLocation['lng'] ?? endLocation['longitude'])
                  : null,
              price: _readDouble(data['price']) ?? 0,
              vehicleTypes: _readStringList(data['vehicleTypes']),
              scheduleSlotCount: slots is List ? slots.length : 0,
              driverQueueCount: driverQueue is List ? driverQueue.length : 0,
              createdAt: _readDate(data['createdAt']),
              updatedAt: _readDate(data['updatedAt']),
            );
          }).toList()..sort((a, b) {
            final byStart = a.startPoint.compareTo(b.startPoint);
            if (byStart != 0) return byStart;
            return a.endPoint.compareTo(b.endPoint);
          });

      return routes;
    });
  }

  Future<void> createRoute({
    required String startPoint,
    required String endPoint,
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
    required double price,
    required List<String> vehicleTypes,
  }) async {
    final routePath = await _routePathService.fetchRoutePathByCoordinates(
      startLatitude: startLatitude,
      startLongitude: startLongitude,
      endLatitude: endLatitude,
      endLongitude: endLongitude,
    );
    if (routePath.encodedPolyline.trim().isEmpty) {
      throw Exception('Could not generate route polyline');
    }

    final routeRef = _db.collection('route').doc();
    final now = FieldValue.serverTimestamp();
    debugPrint(
      '[AdminRouteCreate] Firestore saved polyline value length=${routePath.encodedPolyline.length}',
    );

    await routeRef.set({
      'routeId': routeRef.id,
      'startPoint': startPoint.trim(),
      'endPoint': endPoint.trim(),
      'startLocation': {'lat': startLatitude, 'lng': startLongitude},
      'endLocation': {'lat': endLatitude, 'lng': endLongitude},
      'polyline': routePath.encodedPolyline,
      'routePolyline': routePath.encodedPolyline,
      'distanceMeters': routePath.distanceMeters,
      'distanceText': routePath.distanceText,
      'etaMinutes': routePath.etaMinutes,
      'etaText': routePath.etaText,
      'polylineProvider': routePath.provider,
      'routePathProvider': routePath.provider,
      'price': price,
      'vehicleTypes': vehicleTypes
          .map((type) => type.trim())
          .where((type) => type.isNotEmpty)
          .toList(),
      'scheduleSlots': <Map<String, dynamic>>[],
      'driverQueueIds': <String>[],
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> updateRoute({
    required String documentId,
    required String startPoint,
    required String endPoint,
    required double startLatitude,
    required double startLongitude,
    required double endLatitude,
    required double endLongitude,
    required double price,
    required List<String> vehicleTypes,
  }) async {
    final cleanDocumentId = documentId.trim();
    if (cleanDocumentId.isEmpty) {
      throw StateError('Route document ID is missing');
    }

    final routePath = await _routePathService.fetchRoutePathByCoordinates(
      startLatitude: startLatitude,
      startLongitude: startLongitude,
      endLatitude: endLatitude,
      endLongitude: endLongitude,
    );
    if (routePath.encodedPolyline.trim().isEmpty) {
      throw Exception('Could not generate route polyline');
    }

    await _db.collection('route').doc(cleanDocumentId).update({
      'startPoint': startPoint.trim(),
      'endPoint': endPoint.trim(),
      'startLocation': {'lat': startLatitude, 'lng': startLongitude},
      'endLocation': {'lat': endLatitude, 'lng': endLongitude},
      'polyline': routePath.encodedPolyline,
      'routePolyline': routePath.encodedPolyline,
      'distanceMeters': routePath.distanceMeters,
      'distanceText': routePath.distanceText,
      'etaMinutes': routePath.etaMinutes,
      'etaText': routePath.etaText,
      'polylineProvider': routePath.provider,
      'routePathProvider': routePath.provider,
      'price': price,
      'vehicleTypes': vehicleTypes
          .map((type) => type.trim())
          .where((type) => type.isNotEmpty)
          .toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createRouteManager({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String password,
    required String routeId,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'createRouteManager',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call<Map<String, dynamic>>({
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'email': email.trim().toLowerCase(),
        'phone': phone.trim(),
        'password': password.trim(),
        'routeId': routeId.trim(),
      });
      final data = result.data;
      if (data['success'] != true) {
        throw StateError(
          (data['message'] ?? 'Could not create route manager').toString(),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'Could not create route manager');
    } catch (_) {
      rethrow;
    }
  }

  Future<void> updateRouteManager({
    required String managerId,
    required String userId,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required String routeId,
  }) async {
    final cleanUserId = userId.trim().isEmpty
        ? managerId.trim()
        : userId.trim();
    if (cleanUserId.isEmpty) {
      throw StateError('Route manager user ID is missing');
    }

    final normalizedEmail = email.trim().toLowerCase();
    final cleanFirstName = firstName.trim();
    final cleanLastName = lastName.trim();
    final cleanPhone = phone.trim();
    final cleanRouteId = routeId.trim();
    final fullName = '$cleanFirstName $cleanLastName'.trim();
    final now = FieldValue.serverTimestamp();
    final batch = _db.batch();

    await _assertRouteManagerContactAvailable(
      email: normalizedEmail,
      phone: cleanPhone,
      excludeUserId: cleanUserId,
    );

    batch.set(_db.collection('users').doc(cleanUserId), {
      'userId': cleanUserId,
      'uid': cleanUserId,
      'firstName': cleanFirstName,
      'lastName': cleanLastName,
      'fullName': fullName,
      'name': fullName,
      'email': normalizedEmail,
      'phone': cleanPhone,
      'phoneNumber': cleanPhone,
      'role': 'route_manager',
      'routeId': cleanRouteId,
      'updatedAt': now,
    }, SetOptions(merge: true));

    final managerData = {
      'userId': cleanUserId,
      'firstName': cleanFirstName,
      'lastName': cleanLastName,
      'email': normalizedEmail,
      'phone': cleanPhone,
      'role': 'route_manager',
      'routeId': cleanRouteId,
      'isVerified': true,
      'updatedAt': now,
    };

    batch.set(
      _db.collection('route_manger').doc(cleanUserId),
      managerData,
      SetOptions(merge: true),
    );

    if (managerId.trim().isNotEmpty && managerId.trim() != cleanUserId) {
      batch.delete(_db.collection('route_manger').doc(managerId.trim()));
    }

    await batch.commit();
  }

  Stream<List<AdminRouteManagerItem>> adminRouteManagersStream() {
    return _db
        .collection('users')
        .where(
          'role',
          whereIn: ['route_manager', 'routeManager', 'route_manger'],
        )
        .snapshots()
        .asyncMap((usersSnap) async {
          final managersSnap = await _db.collection('route_manger').get();
          final legacyManagersSnap = await _db
              .collection('routeManagers')
              .get();
          final alternateManagersSnap = await _db
              .collection('route_manager')
              .get();
          final routesSnap = await _db.collection('route').get();
          final managersById = {
            for (final doc in managersSnap.docs) doc.id: doc.data(),
          };
          for (final doc in legacyManagersSnap.docs) {
            managersById.putIfAbsent(doc.id, () => doc.data());
          }
          for (final doc in alternateManagersSnap.docs) {
            managersById.putIfAbsent(doc.id, () => doc.data());
          }
          final routesById = {
            for (final doc in routesSnap.docs) doc.id: doc.data(),
          };
          for (final doc in routesSnap.docs) {
            final routeId = _readString(doc.data()['routeId']);
            if (routeId.isNotEmpty) {
              routesById[routeId] = doc.data();
            }
          }

          final managers = usersSnap.docs.map((doc) {
            final userData = doc.data();
            final managerData =
                managersById[doc.id] ?? const <String, dynamic>{};
            final userId = doc.id;
            final firstName = _readString(
              userData['firstName'] ?? managerData['firstName'],
            );
            final lastName = _readString(
              userData['lastName'] ?? managerData['lastName'],
            );
            final fullName = _readString(
              userData['fullName'] ??
                  userData['name'] ??
                  managerData['fullName'] ??
                  managerData['name'] ??
                  '$firstName $lastName',
            );
            final routeId = _readString(
              managerData['routeId'] ?? userData['routeId'],
            );
            final routeData = routesById[routeId] ?? const <String, dynamic>{};

            return AdminRouteManagerItem(
              managerId: userId,
              userId: userId,
              firstName: firstName,
              lastName: lastName,
              fullName: fullName.isEmpty ? 'Unknown route manager' : fullName,
              email: _readString(userData['email'] ?? managerData['email']),
              phone: _readString(
                userData['phone'] ??
                    userData['phoneNumber'] ??
                    managerData['phone'] ??
                    managerData['phoneNumber'],
              ),
              isVerified:
                  userData['isVerified'] == true ||
                  managerData['isVerified'] == true,
              isOnline:
                  userData['isOnline'] == true ||
                  managerData['isOnline'] == true,
              routeId: routeId,
              routeLabel: _routeLabel(routeData, routeId),
              createdAt: _readDate(
                managerData['createdAt'] ?? userData['createdAt'],
              ),
              updatedAt: _readDate(
                managerData['updatedAt'] ?? userData['updatedAt'],
              ),
            );
          }).toList()..sort((a, b) => a.fullName.compareTo(b.fullName));

          return managers;
        });
  }

  Future<void> _assertRouteManagerContactAvailable({
    required String email,
    required String phone,
    String? excludeUserId,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanPhone = phone.trim();
    final excluded = excludeUserId?.trim();

    final emailSnap = await _db
        .collection('users')
        .where('email', isEqualTo: cleanEmail)
        .limit(1)
        .get();

    if (emailSnap.docs.any((doc) => doc.id != excluded)) {
      throw StateError('Email is already in the database');
    }

    final phoneSnap = await _db
        .collection('users')
        .where('phone', isEqualTo: cleanPhone)
        .limit(1)
        .get();

    if (phoneSnap.docs.any((doc) => doc.id != excluded)) {
      throw StateError('Phone number is already in the database');
    }

    final phoneNumberSnap = await _db
        .collection('users')
        .where('phoneNumber', isEqualTo: cleanPhone)
        .limit(1)
        .get();

    if (phoneNumberSnap.docs.any((doc) => doc.id != excluded)) {
      throw StateError('Phone number is already in the database');
    }
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
    try {
      final callable = _functions.httpsCallable(
        'approveDriverAccount',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      await callable.call<Map<String, dynamic>>({
        'driverId': item.id,
        'userId': item.userId.trim(),
      });
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'Could not approve driver');
    }
  }

  Future<void> rejectDriver(AdminApprovalItem item) async {
    try {
      final callable = _functions.httpsCallable(
        'rejectDriverAccount',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      await callable.call<Map<String, dynamic>>({
        'driverId': item.id,
        'userId': item.userId.trim(),
      });
    } on FirebaseFunctionsException catch (e) {
      throw StateError(e.message ?? 'Could not reject driver');
    }
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

  List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];

    return value
        .map((item) => _readString(item))
        .where((item) => item.isNotEmpty)
        .toList();
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
    final reports =
        snapshot.docs
            .where((doc) {
              final data = doc.data();
              final status = _readString(data['status']).toLowerCase();

              // Route managers send reports to admin by setting this status.
              // The sentToAdminAt fallback keeps older sent reports visible too.
              return status == 'sent_to_admin' || data['sentToAdminAt'] != null;
            })
            .map((doc) {
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
                routeLabel: routeLabel.isEmpty
                    ? 'No route selected'
                    : routeLabel,
                message: message.isEmpty ? 'No report message' : message,
                status: status.isEmpty ? 'sent_to_admin' : status,
                createdAt: _readDate(data['createdAt']),
                sentToAdminAt: _readDate(data['sentToAdminAt']),
              );
            })
            .toList()
          ..sort((a, b) {
            final aDate =
                a.sentToAdminAt ??
                a.createdAt ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                b.sentToAdminAt ??
                b.createdAt ??
                DateTime.fromMillisecondsSinceEpoch(0);

            return bDate.compareTo(aDate);
          });

    if (limit == null) return reports;

    return reports.take(limit).toList();
  }
}
