import 'package:flutter/widgets.dart';

import '../controllers/app_controller_scope.dart';
import 'app_texts.dart';

extension LocalizationX on BuildContext {
  AppTexts get texts {
    final locale = AppControllerScope.of(this).languageController.locale;
    return AppTexts(locale);
  }
}
