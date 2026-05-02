import 'package:flutter/material.dart';

import '../controllers/app_controller_scope.dart';
import '../localization/localization_x.dart';

class LanguageToggleSwitch extends StatelessWidget {
  const LanguageToggleSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppControllerScope.of(context);
    final languageController = scope.languageController;
    final texts = context.texts;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(texts.t('english')),
        Switch(
          value: languageController.isArabic,
          onChanged: (value) => languageController.toggleLanguage(value),
        ),
        Text(texts.t('arabic')),
      ],
    );
  }
}
