import 'package:flutter/widgets.dart';

import 'language_controller.dart';

class AppControllerScope extends InheritedNotifier<LanguageController> {
  const AppControllerScope({
    super.key,
    required this.languageController,
    required super.child,
  }) : super(notifier: languageController);

  final LanguageController languageController;

  static AppControllerScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppControllerScope>();
    assert(
      scope != null,
      'AppControllerScope was not found in the widget tree',
    );
    return scope!;
  }

  @override
  bool updateShouldNotify(AppControllerScope oldWidget) =>
      oldWidget.languageController != languageController ||
      super.updateShouldNotify(oldWidget);
}
