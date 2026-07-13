import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;

import '../models/trip_driver_request.dart';

class TripDriverRequestService {
  TripDriverRequestService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    http.Client? client,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _client = client ?? http.Client();

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final http.Client _client;

  static const String _collection = 'tripDriverRequests';
  static const String _functionsRegion = String.fromEnvironment(
    'FIREBASE_FUNCTIONS_REGION',
    defaultValue: 'us-central1',
  );
  static const Duration _functionTimeout = Duration(seconds: 20);

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

    final response = await _callTrustedRequestFunction(
      endpoint: 'createTripDriverRequest',
      body: {
        'driverId': safeDriver,
        'routeId': safeRoute,
        'scheduleId': safeSlot,
        'seatsRequested': seatsRequested,
        'lineLabel': lineLabel.trim(),
        'startPoint': startPoint.trim(),
        'endPoint': endPoint.trim(),
        'pickupDescription': pickupDescription.trim(),
      },
    );

    final requestId = (response['requestId'] ?? '').toString().trim();
    if (requestId.isEmpty) {
      throw Exception(
        'The trusted request operation did not return a request ID.',
      );
    }
    return requestId;
  }

  Future<Map<String, dynamic>> _callTrustedRequestFunction({
    required String endpoint,
    required Map<String, dynamic> body,
  }) async {
    final projectId = Firebase.app().options.projectId;
    if (projectId.isEmpty) {
      throw Exception('Firebase project ID is missing.');
    }

    final token = await _auth.currentUser?.getIdToken();
    if (token == null || token.trim().isEmpty) {
      throw Exception('You must be signed in.');
    }

    final uri = Uri.https(
      '$_functionsRegion-$projectId.cloudfunctions.net',
      '/$endpoint',
    );

    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_functionTimeout);

      final decoded = _decodeResponse(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }

      final message = (decoded['error'] ?? '').toString().trim();
      throw Exception(
        message.isEmpty ? 'trustedOperationFailed' : message,
      );
    } on TimeoutException {
      throw Exception('requestTimedOutRetry');
    } finally {
      sw.stop();
      if (kDebugMode) {
        debugPrint('[PERF] $endpoint: ${sw.elapsedMilliseconds} ms');
      }
    }
  }

  Map<String, dynamic> _decodeResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (e) {
      if (kDebugMode) debugPrint('Trusted request response decode error: $e');
    }
    return const {};
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

    await _callTrustedRequestFunction(
      endpoint: 'acceptTripDriverRequest',
      body: {'requestId': safeReqId},
    );
  }

  Future<void> declineRequest(String requestId) async {
    final uid = _uid;
    if (uid == null) return;

    await _callTrustedRequestFunction(
      endpoint: 'declineTripDriverRequest',
      body: {'requestId': requestId.trim()},
    );
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
