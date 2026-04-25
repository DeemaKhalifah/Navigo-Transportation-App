import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'controllers/app_controller_scope.dart';
import 'controllers/auth_controller.dart';
import 'firebase_options.dart';
import 'navigation/app_navigator.dart';
import 'screens/welcome_flow/welcome.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  debugPrint('FCM background: ${message.messageId} type=${message.data['type']}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      Firebase.app();
    }

    debugPrint('Firebase initialized successfully');
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      debugPrint('Firebase already initialized');
    } else {
      rethrow;
    }
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthController _authController;
  late final PushNotificationService _pushNotificationService;

  bool _pushInitialized = false;

  @override
  void initState() {
    super.initState();

    _authController = AuthController();
    _pushNotificationService = PushNotificationService();

    _initPushNotifications();
  }

  Future<void> _initPushNotifications() async {
    if (_pushInitialized) return;

    _pushInitialized = true;

    try {
      await _pushNotificationService.init();
      debugPrint('Push notifications initialized successfully');
    } catch (e) {
      debugPrint('Push notifications initialization failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppControllerScope(
      authController: _authController,
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        theme: appTheme,
        debugShowCheckedModeBanner: false,
        home: const SplashScreen(),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    startApp();
  }

  Future<void> startApp() async {
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const OnboardingScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              NavigoColors.primaryAmber,
              NavigoColors.backgroundLight,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  "assets/images/logo.png",
                  width: 220,
                ),
                const SizedBox(height: 20),
                const Text(
                  "Navigo وصلني",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: NavigoColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Smart Transportation Platform",
                  style: NavigoTextStyles.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}