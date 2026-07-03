import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controllers/app_controller_scope.dart';
import 'controllers/auth_controller.dart';
import 'controllers/language_controller.dart';
import 'firebase_options.dart';
import 'localization/app_texts.dart';
import 'navigation/app_navigator.dart';
import 'screens/authentication/phone_number_screen.dart';
import 'screens/authentication/signup_approval.dart';
import 'screens/driver/driver_home_screen.dart';
import 'screens/passenger/passenger_home_screen.dart';
import 'screens/route_manager/route_schedule.dart';
import 'screens/welcome_flow/welcome.dart';
import 'services/auth_session_service.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseAuth.instance.setSettings(
      appVerificationDisabledForTesting: true,
    );
  }
  debugPrint(
    'FCM background: ${message.messageId} type=${message.data['type']}',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    debugPrintStack(stackTrace: details.stack);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('PlatformDispatcher error: $error');
    debugPrintStack(stackTrace: stack);
    return true;
  };

  final languageController = LanguageController();
  await languageController.loadSavedLanguage();

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

  languageController.startAuthLanguageSync();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(MyApp(languageController: languageController));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.languageController});

  final LanguageController languageController;

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
      languageController: widget.languageController,
      child: AnimatedBuilder(
        animation: widget.languageController,
        builder: (context, _) => MaterialApp(
          navigatorKey: appNavigatorKey,
          theme: appTheme,
          debugShowCheckedModeBanner: false,
          locale: widget.languageController.locale,
          supportedLocales: AppTexts.supportedLocales,
          // Rebuilt by AnimatedBuilder whenever LanguageController notifies,
          // so locale and Directionality switch immediately on the active page.
          builder: (context, child) {
            // Keep the current route under the new text direction immediately;
            // this prevents the onboarding screen from needing a second tap.
            return Directionality(
              textDirection: widget.languageController.isArabic
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
          },
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const SplashScreen(),
        ),
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
  final AuthSessionService _authSessionService = AuthSessionService();

  @override
  void initState() {
    super.initState();
    _startApp();
  }

  Future<void> _startApp() async {
    AppSessionDestination destination = AppSessionDestination.phoneLogin;

    try {
      destination = await _authSessionService.resolveStartupDestination();
    } catch (_) {
      destination = AppSessionDestination.phoneLogin;
    }

    if (!mounted) return;

    final Widget targetScreen = switch (destination) {
      AppSessionDestination.welcome => const OnboardingScreen(),
      AppSessionDestination.passengerHome => const PassengerHomeScreen(),
      AppSessionDestination.driverHome => const DriverHomeScreen(),
      AppSessionDestination.driverApproval => const SignupApprovalScreen(),
      AppSessionDestination.routeManagerHome => const RouteSchedule(),
      AppSessionDestination.phoneLogin => const PhoneNumberScreen(),
    };

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => targetScreen),
      (route) => false,
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
            colors: [NavigoColors.primaryAmber, NavigoColors.backgroundLight],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset("assets/images/Logowithoutbg.png", width: 220),
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
                const SizedBox(height: 20),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: NavigoColors.primaryOrange,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
