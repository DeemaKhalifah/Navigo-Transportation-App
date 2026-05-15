import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../navigation/app_navigator.dart';
import '../screens/driver/driver_requests_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/passenger/passenger_home_screen.dart';
import '../screens/route_manager/reports.dart';

class PushNotificationService {
  PushNotificationService({
    FirebaseMessaging? messaging,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const String _androidChannelId = 'navigo_default';
  static const String _androidChannelName = 'Navigo notifications';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    await _initLocalNotifications();
    await _saveTokenIfPossible();

    _messaging.onTokenRefresh.listen((token) async {
      await _saveTokenIfPossible(tokenOverride: token);
    });

    _auth.authStateChanges().listen((_) async {
      await _saveTokenIfPossible();
    });

    FirebaseMessaging.onMessage.listen((message) async {
      await _showLocalForRemoteMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleNotificationTap(initial);
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload ?? '';
        final data = _payloadData(payload);
        final type = (data['type'] ?? payload).toString();

        if (type == 'trip_started') {
          _openTripStartedDestination();
        } else if (type == 'driver_request') {
          _openDriverRequests();
        } else if (type == 'support_report') {
          _openRouteManagerReports();
        } else {
          _openNotifications(
            initialNotificationId: data['notificationId']?.toString(),
            initialTitle: data['title']?.toString(),
            initialBody: data['body']?.toString(),
          );
        }
      },
    );

    if (kIsWeb || !Platform.isAndroid) return;
    const channel = AndroidNotificationChannel(
      _androidChannelId,
      _androidChannelName,
      importance: Importance.high,
      description: 'Trip and app notifications',
    );
    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(channel);
  }

  Future<void> _saveTokenIfPossible({String? tokenOverride}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.trim().isEmpty) return;

    final token = tokenOverride ?? await _messaging.getToken();
    if (token == null || token.trim().isEmpty) return;

    final platform = kIsWeb
        ? 'web'
        : Platform.isAndroid
        ? 'android'
        : Platform.isIOS
        ? 'ios'
        : Platform.operatingSystem;

    await _db
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(token)
        .set({
          'token': token,
          'platform': platform,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

    await _db.collection('users').doc(uid).set({
      'fcm': token,
      'fcmUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _showLocalForRemoteMessage(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;

    const androidDetails = AndroidNotificationDetails(
      _androidChannelId,
      _androidChannelName,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _local.show(
      n.hashCode,
      n.title ?? 'Navigo',
      n.body ?? '',
      details,
      payload: jsonEncode({
        'type': (message.data['type'] ?? '').toString(),
        'notificationId': (message.data['notificationId'] ?? '').toString(),
        'title': n.title ?? 'Navigo',
        'body': n.body ?? '',
      }),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final type = (message.data['type'] ?? '').toString().trim();
    if (type == 'trip_started') {
      _openTripStartedDestination();
      return;
    }
    if (type == 'driver_request') {
      _openDriverRequests();
      return;
    }
    if (type == 'support_report') {
      _openRouteManagerReports();
      return;
    }
    _openNotifications(
      initialNotificationId: (message.data['notificationId'] ?? '').toString(),
      initialTitle: message.notification?.title,
      initialBody: message.notification?.body,
    );
  }

  Map<String, dynamic> _payloadData(String payload) {
    if (payload.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return {'type': payload};
    }
    return {'type': payload};
  }

  void _openTripStartedDestination() {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => const PassengerHomeScreen()));
  }

  void _openNotifications({
    String? initialNotificationId,
    String? initialTitle,
    String? initialBody,
  }) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          initialNotificationId: initialNotificationId,
          initialTitle: initialTitle,
          initialBody: initialBody,
        ),
      ),
    );
  }

  void _openDriverRequests() {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => const DriverRequestsScreen()));
  }

  void _openRouteManagerReports() {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(builder: (_) => const Reports()));
  }
}
