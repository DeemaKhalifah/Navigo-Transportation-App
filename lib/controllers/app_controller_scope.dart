import 'package:flutter/widgets.dart';

import 'auth_controller.dart';

/// Simple DI/scope for app-level controllers (MVC).
///
/// Screens (views) should read controllers from context instead of importing
/// globals from `main.dart`.
class AppControllerScope extends InheritedWidget {
  final AuthController authController;

  const AppControllerScope({
    super.key,
    required this.authController,
    required super.child,
  });

  static AppControllerScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppControllerScope>();
    assert(scope != null, 'AppControllerScope not found in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(covariant AppControllerScope oldWidget) {
    return authController != oldWidget.authController;
  }
}

