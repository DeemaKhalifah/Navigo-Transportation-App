import 'package:flutter/widgets.dart';

import 'auth_controller.dart';
import 'language_controller.dart';

/// Simple DI/scope for app-level controllers (MVC).
///
/// Screens (views) should read controllers from context instead of importing
/// globals from `main.dart`.
class AppControllerScope extends InheritedNotifier<LanguageController> {
  final AuthController authController;
  final LanguageController languageController;

  const AppControllerScope({
    super.key,
    required this.authController,
    required this.languageController,
    required super.child,
  }) : super(notifier: languageController);

  static AppControllerScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppControllerScope>();
    assert(scope != null, 'AppControllerScope not found in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(covariant AppControllerScope oldWidget) {
    // The language controller instance usually stays the same while its locale
    // changes. InheritedNotifier makes dependents rebuild on notifyListeners(),
    // and this keeps auth/controller replacement behavior intact too.
    return authController != oldWidget.authController ||
        languageController != oldWidget.languageController ||
        super.updateShouldNotify(oldWidget);
  }
}
