import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../navigation/app_navigator.dart';
import '../screens/driver/driver_home_screen.dart';
import '../screens/passenger/passenger_home_screen.dart';
import '../screens/route_manager/Reports.dart';

/// Registers FCM tokens in Firestore and wires foreground message handling.
///
/// Server-side sending is done by Cloud Functions (admin SDK).
class PushNotificationService {
  PushNotificationService({
    FirebaseMessaging? messaging,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
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

  String? _lastRoleTopic;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // iOS needs explicit permission. Android usually auto-grants.
    await _messaging.requestPermission();

    // iOS foreground presentation options.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _initLocalNotifications();

    // Save initial token (if signed in).
    await _saveTokenIfPossible();

    // Refresh token updates.
    _messaging.onTokenRefresh.listen((token) async {
      await _saveTokenIfPossible(tokenOverride: token);
    });

    // Keep topic subscriptions in sync with login/logout + role changes.
    _auth.authStateChanges().listen((user) async {
      try {
        final uid = user?.uid;
        if (uid == null || uid.trim().isEmpty) {
          await _unsubscribeFromAllRoleTopics();
          return;
        }

        await _saveTokenIfPossible();
        final role = await _loadUserRole(uid);
        await _syncRoleTopic(role);
      } catch (e) {
        debugPrint('FCM auth sync error: $e');
      }
    });

    // Foreground messages (optional: you can show a local dialog/snackbar later).
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('FCM foreground: ${message.notification?.title} '
          '${message.notification?.body}');

      // Display a local notification while app is open.
      await _showLocalForRemoteMessage(message);
    });

    // When user taps a notification and app opens from background.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationTap(message);
    });

    // When app is launched from terminated by tapping notification.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _handleNotificationTap(initial);
    }
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
        // For local notifications click; remote clicks are handled by FCM callbacks.
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) {
          _handleNotificationTapData({'type': payload});
        }
      },
    );

    if (kIsWeb) return;
    if (!Platform.isAndroid) return;

    const androidChannel = AndroidNotificationChannel(
      _androidChannelId,
      _androidChannelName,
      description: 'Role and trip notifications',
      importance: Importance.high,
    );

    final androidPlugin =
        _local.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);
  }

  Future<void> _saveTokenIfPossible({String? tokenOverride}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    final token = tokenOverride ?? await _messaging.getToken();
    if (token == null || token.trim().isEmpty) return;

    final platform = kIsWeb
        ? 'web'
        : Platform.isAndroid
            ? 'android'
            : Platform.isIOS
                ? 'ios'
                : Platform.operatingSystem;

    // Multiple device support: store tokens as docs.
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
  }

  Future<String> _loadUserRole(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    final data = snap.data() ?? {};
    final role = (data['role'] ?? '').toString().trim().toLowerCase();
    return role;
  }

  static String _roleToTopic(String role) {
    // Keep topics simple and predictable.
    // Allowed topic characters: [a-zA-Z0-9-_.~%]. Use lowercase + underscores.
    if (role == 'route_manger') return 'role_route_manager'; // common typo
    if (role == 'route manager') return 'role_route_manager';
    if (role == 'routemanager') return 'role_route_manager';
    if (role == 'route_manager') return 'role_route_manager';
    if (role == 'driver') return 'role_driver';
    if (role == 'passenger') return 'role_passenger';
    return '';
  }

  Future<void> _syncRoleTopic(String role) async {
    final topic = _roleToTopic(role);
    if (topic.isEmpty) {
      await _unsubscribeFromAllRoleTopics();
      return;
    }

    // Ensure only ONE role topic subscribed at a time.
    if (_lastRoleTopic != null && _lastRoleTopic != topic) {
      await _messaging.unsubscribeFromTopic(_lastRoleTopic!);
    } else {
      // If we don't know last state (fresh install), clean up anyway.
      await _unsubscribeFromAllRoleTopics(except: topic);
    }

    await _messaging.subscribeToTopic(topic);
    _lastRoleTopic = topic;
    debugPrint('FCM subscribed to topic: $topic');
  }

  Future<void> _unsubscribeFromAllRoleTopics({String? except}) async {
    const topics = <String>[
      'role_route_manager',
      'role_driver',
      'role_passenger',
    ];

    for (final t in topics) {
      if (except != null && except == t) continue;
      try {
        await _messaging.unsubscribeFromTopic(t);
      } catch (_) {
        // ignore
      }
    }

    if (except == null) _lastRoleTopic = null;
  }

  Future<void> _showLocalForRemoteMessage(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;

    // Android: show as heads-up when in foreground.
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
      n.body,
      details,
      // Keep payload small; you can extend this to json if needed.
      payload: (message.data['type'] ?? '').toString(),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    _handleNotificationTapData(message.data);
  }

  void _handleNotificationTapData(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().trim();

    // You can extend this mapping gradually as you add screens.
    // For now we route to the most relevant "home" screens per role.
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;

    if (type.startsWith('rm_')) {
      nav.push(MaterialPageRoute(builder: (_) => const Reports()));
      return;
    }

    if (type.startsWith('driver_') ||
        type == 'trip_started' ||
        type == 'trip_cancelled') {
      nav.push(MaterialPageRoute(builder: (_) => const DriverHomeScreen()));
      return;
    }

    if (type.startsWith('passenger_') ||
        type == 'trip_request_accepted' ||
        type == 'trip_request_declined') {
      nav.push(MaterialPageRoute(builder: (_) => const PassengerHomeScreen()));
      return;
    }

    // Default: route managers get reports, otherwise passenger home.
    nav.push(MaterialPageRoute(builder: (_) => const PassengerHomeScreen()));
  }
}

