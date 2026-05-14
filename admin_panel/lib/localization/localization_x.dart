import 'package:flutter/widgets.dart';

import '../controllers/app_controller_scope.dart';
import 'admin_texts.dart';

extension LocalizationX on BuildContext {
  AdminTexts get texts {
    final locale = AppControllerScope.of(this).languageController.locale;
    return AdminTexts(locale);
  }
}
