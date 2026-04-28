import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/support_report.dart';
import '../services/local_storage_service.dart';
import '../services/passenger_trip_repository.dart';
import '../services/route_manager_route_id.dart' as rm_route;

class SupportReportService {
  SupportReportService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  static const String _notificationsCollection = 'notifications';

  Future<void> createSupportReport({
    required String message,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be logged in.');
    }

    final uid = user.uid;

    final userSnap = await _db.collection('users').doc(uid).get();
    final userData = userSnap.data() ?? {};

    final firstName = (userData['firstName'] ?? '').toString();
    final lastName = (userData['lastName'] ?? '').toString();
    final role = (userData['role'] ?? '').toString();

    final senderName = '$firstName $lastName'.trim().isEmpty
        ? 'Unknown user'
        : '$firstName $lastName'.trim();

    String routeId = '';
    String routeLabel = '';

    if (role == 'passenger') {
      final selectedLine = await LocalStorageService.getSelectedLine();

      if (selectedLine == null || selectedLine.trim().isEmpty) {
        throw Exception('Please choose a route first from the home screen.');
      }

      final repo = PassengerTripRepository();
      final route = await repo.getRouteForLine(selectedLine);

      if (route == null) {
        throw Exception('Selected route was not found.');
      }

      routeId = route.routeId;
      routeLabel = PassengerTripRepository.buildLineLabel(route);
    } else if (role == 'driver') {
      final driverSnap = await _db.collection('drivers').doc(uid).get();
      final driverData = driverSnap.data() ?? {};

      routeId = (driverData['routeId'] ?? '').toString();

      if (routeId.isEmpty) {
        throw Exception('No route is assigned to this driver.');
      }

      final routeSnap = await _db.collection('route').doc(routeId).get();
      final routeData = routeSnap.data() ?? {};

      final startPoint = (routeData['startPoint'] ?? '').toString();
      final endPoint = (routeData['endPoint'] ?? '').toString();

      routeLabel = '$startPoint <-----> $endPoint';
    } else {
      throw Exception('Only passengers and drivers can send support reports.');
    }

    final ref = _db.collection('supportReports').doc();

    final report = SupportReport(
      reportId: ref.id,
      senderId: uid,
      senderName: senderName,
      senderRole: role,
      routeId: routeId,
      routeLabel: routeLabel,
      message: message.trim(),
      status: SupportReport.pending,
    );

    await ref.set(report.toMap());
    await _notifyRouteManagersAboutReport(
      routeId: routeId,
      senderName: senderName,
      routeLabel: routeLabel,
      reportId: ref.id,
    );
  }

  Stream<List<SupportReport>> watchReportsForCurrentRouteManager() {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      return Stream.value([]);
    }

    // Resolve routeId with fallback (route_manager/{uid} then users/{uid}).
    // We intentionally DO NOT filter by `status` in Firestore, because older
    // documents may not have a `status` field; the model defaults it to pending.
    return Stream.fromFuture(rm_route.resolveManagedRouteId()).asyncExpand(
      (routeId) {
        if (routeId == null || routeId.trim().isEmpty) {
          return Stream.value(<SupportReport>[]);
        }

        return _db
            .collection('supportReports')
            .where('routeId', isEqualTo: routeId.trim())
            .snapshots()
            .map((snap) {
          final reports = snap.docs.map(SupportReport.fromDoc).toList();

          // Keep only pending reports (or missing/blank status which maps to pending).
          final pending = reports
              .where((r) =>
                  (r.status.trim().isEmpty ? SupportReport.pending : r.status) ==
                  SupportReport.pending)
              .toList();

          pending.sort((a, b) {
            final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });

          return pending;
        });
      },
    );
  }

  Future<void> sendReportsToAdmin(List<SupportReport> reports) async {
    if (reports.isEmpty) {
      throw Exception('No reports selected.');
    }

    final batch = _db.batch();

    for (final report in reports) {
      final supportRef = _db.collection('supportReports').doc(report.reportId);
      final adminRef = _db.collection('adminReports').doc(report.reportId);

      batch.set(adminRef, {
        ...report.toMap(),
        'originalReportId': report.reportId,
        'status': SupportReport.sentToAdmin,
        'sentToAdminAt': FieldValue.serverTimestamp(),
      });

      batch.update(supportRef, {
        'status': SupportReport.sentToAdmin,
        'sentToAdminAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Future<void> markReportReadByManager(String reportId) async {
    if (reportId.trim().isEmpty) return;
    await _db.collection('supportReports').doc(reportId).set(
      {
        'isRead': true,
        'managerReadAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Stream<int> watchUnreadCountForCurrentRouteManager() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(0);

    return Stream.fromFuture(rm_route.resolveManagedRouteId()).asyncExpand((
      routeId,
    ) {
      final safeRouteId = (routeId ?? '').trim();
      if (safeRouteId.isEmpty) return Stream.value(0);

      return _db
          .collection('supportReports')
          .where('routeId', isEqualTo: safeRouteId)
          .snapshots()
          .map((snap) {
            var count = 0;
            for (final doc in snap.docs) {
              final isRead = doc.data()['isRead'] == true;
              if (!isRead) count++;
            }
            return count;
          });
    });
  }

  Future<void> _notifyRouteManagersAboutReport({
    required String routeId,
    required String senderName,
    required String routeLabel,
    required String reportId,
  }) async {
    final safeRouteId = routeId.trim();
    if (safeRouteId.isEmpty) return;

    final managerQuery = await _db
        .collection('route_manager')
        .where('routeId', isEqualTo: safeRouteId)
        .get();

    final managerIds = managerQuery.docs
        .map((doc) => doc.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (managerIds.isEmpty) return;

    final batch = _db.batch();
    for (final managerId in managerIds) {
      final notificationRef = _db.collection(_notificationsCollection).doc();
      batch.set(notificationRef, {
        'notificationId': notificationRef.id,
        'userId': managerId,
        'title': 'New Support Report',
        'message':
            '$senderName sent a new report${routeLabel.trim().isEmpty ? '' : ' for $routeLabel'}.',
        'body':
            '$senderName sent a new report${routeLabel.trim().isEmpty ? '' : ' for $routeLabel'}.',
        'type': 'support_report',
        'routeId': safeRouteId,
        'reportId': reportId,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}