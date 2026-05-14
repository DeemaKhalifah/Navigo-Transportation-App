import 'package:flutter/material.dart';

import '../controllers/app_controller_scope.dart';
import '../localization/admin_texts.dart';
import '../theme/app_theme.dart';

class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final languageController = AppControllerScope.of(
      context,
    ).languageController;

    return AnimatedBuilder(
      animation: languageController,
      builder: (context, _) {
        final locale = languageController.locale;
        final texts = AdminTexts(locale);

        return SegmentedButton<String>(
          key: ValueKey(locale.languageCode),
          segments: [
            ButtonSegment<String>(value: 'en', label: Text(texts.t('english'))),
            ButtonSegment<String>(value: 'ar', label: Text(texts.t('arabic'))),
          ],
          selected: {locale.languageCode},
          showSelectedIcon: false,
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? Colors.white
                  : NavigoColors.textDark;
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.selected)
                  ? NavigoColors.primaryOrange
                  : NavigoColors.surfaceWhite;
            }),
          ),
          onSelectionChanged: (selection) {
            if (selection.isEmpty) return;
            languageController.setLanguage(selection.first);
          },
        );
      },
    );
  }
}
