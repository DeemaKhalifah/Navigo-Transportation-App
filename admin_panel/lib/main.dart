import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/admin_login_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  Object? startupError;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } on FirebaseException catch (e) {
    // Hot restart or web reloads can occasionally leave the default app alive.
    // In that case the admin panel can continue using the existing Firebase app.
    if (e.code != 'duplicate-app') {
      startupError = e;
    }
  } catch (e) {
    startupError = e;
  }

  runApp(MyApp(startupError: startupError));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.startupError});

  final Object? startupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: appTheme,
      home: startupError == null
          ? const AdminLoginScreen()
          : StartupErrorScreen(error: startupError!),
    );
  }
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: Center(
        child: Container(
          width: 520,
          padding: const EdgeInsets.all(28),
          decoration: NavigoDecorations.kCardDecoration.copyWith(
            color: NavigoColors.surfaceWhite,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: NavigoColors.accentRed,
              ),
              const SizedBox(height: 16),
              const Text(
                'Admin panel could not start',
                style: NavigoTextStyles.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                error.toString(),
                style: NavigoTextStyles.bodyMedium,
              ),
              const SizedBox(height: 18),
              const Text(
                'Check Firebase configuration for the platform you are running.',
                style: NavigoTextStyles.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
