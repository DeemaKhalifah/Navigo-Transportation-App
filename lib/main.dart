import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'controllers/app_controller_scope.dart';
import 'controllers/auth_controller.dart';
import 'firebase_options.dart';
import 'screens/welcome_flow/welcome.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase "in the background" (runApp immediately),
  // but DO NOT build any Firebase-dependent screens until it completes.
  final firebaseInit = Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  )
      .then((_) => debugPrint('Firebase initialized successfully'))
      .catchError((e) => debugPrint('Firebase initialization failed: $e'));

  runApp(
    MyApp(
      firebaseInit: firebaseInit,
    ),
  );
}

class MyApp extends StatefulWidget {
  final Future<void> firebaseInit;

  const MyApp({
    super.key,
    required this.firebaseInit,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: widget.firebaseInit,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.error != null) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }

        // IMPORTANT: create Firebase-dependent controllers only AFTER init.
        final authController = AuthController();

        return AppControllerScope(
          authController: authController,
          child: MaterialApp(
            theme: appTheme,
            debugShowCheckedModeBanner: false,
            home: const SplashScreen(),
          ),
        );
      },
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
      MaterialPageRoute(builder: (context) => const OnboardingScreen()),
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
                Image.asset("assets/images/logo.png", width: 220),
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
                Text("Smart Transportation Platform",
                    style: NavigoTextStyles.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}