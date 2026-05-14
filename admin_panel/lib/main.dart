import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'controllers/app_controller_scope.dart';
import 'controllers/language_controller.dart';
import 'firebase_options.dart';
import 'localization/admin_texts.dart';
import 'localization/localization_x.dart';
import 'screens/admin_login_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final languageController = LanguageController();
  await languageController.loadSavedLanguage();

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

  runApp(
    MyApp(startupError: startupError, languageController: languageController),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.startupError, required this.languageController});

  final Object? startupError;
  final LanguageController languageController;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void dispose() {
    widget.languageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppControllerScope(
      languageController: widget.languageController,
      child: AnimatedBuilder(
        animation: widget.languageController,
        builder: (context, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: appTheme,
          locale: widget.languageController.locale,
          supportedLocales: AdminTexts.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            return Directionality(
              textDirection: widget.languageController.isArabic
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: widget.startupError == null
              ? const AdminLoginScreen()
              : StartupErrorScreen(error: widget.startupError!),
        ),
      ),
    );
  }
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final texts = context.texts;

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
              Text(
                texts.t('adminPanelCouldNotStart'),
                style: NavigoTextStyles.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(error.toString(), style: NavigoTextStyles.bodyMedium),
              const SizedBox(height: 18),
              Text(
                texts.t('checkFirebaseConfiguration'),
                style: NavigoTextStyles.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
