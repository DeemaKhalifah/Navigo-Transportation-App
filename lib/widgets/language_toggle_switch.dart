import 'package:flutter/material.dart';

import '../controllers/app_controller_scope.dart';
import '../theme/app_theme.dart';

class LanguageToggleSwitch extends StatelessWidget {
  const LanguageToggleSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppControllerScope.of(context);
    final languageController = scope.languageController;

    return AnimatedBuilder(
      animation: languageController,
      builder: (context, _) {
        final isArabic = languageController.isArabic;

        return Directionality(
          textDirection: TextDirection.ltr,
          child: Container(
            width: 142,
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: NavigoColors.inputFill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: NavigoColors.primaryOrange),
            ),
            child: Stack(
              children: [
                AnimatedAlign(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: isArabic
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 67,
                    decoration: BoxDecoration(
                      color: NavigoColors.primaryOrange,
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _LanguageChoice(
                        label: 'English',
                        selected: !isArabic,
                        onTap: () => languageController.toggleLanguage(false),
                      ),
                    ),
                    Expanded(
                      child: _LanguageChoice(
                        label: 'العربية',
                        selected: isArabic,
                        onTap: () => languageController.toggleLanguage(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: Center(
        child: Text(
          label,
          style: NavigoTextStyles.chip.copyWith(
            color: selected
                ? NavigoColors.textLight
                : NavigoColors.primaryOrange,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
