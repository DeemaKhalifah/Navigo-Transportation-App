import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppMessageType { error, success, info }

class AppMessage {
  const AppMessage._();

  static void showError(BuildContext context, String message) {
    _show(context, message, AppMessageType.error);
  }

  static void showSuccess(BuildContext context, String message) {
    _show(context, message, AppMessageType.success);
  }

  static void showInfo(BuildContext context, String message) {
    _show(context, message, AppMessageType.info);
  }

  static void _show(BuildContext context, String message, AppMessageType type) {
    if (!context.mounted) return;

    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    messenger.hideCurrentSnackBar();

    // A single bottom message style for handled app feedback. Floating margin
    // keeps it above the keyboard and readable on phones, tablets, RTL, and LTR.
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          bottomInset > 0 ? bottomInset + 12 : 16,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: _backgroundColor(type),
        duration: const Duration(seconds: 4),
        content: Text(
          trimmed,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.start,
          style: NavigoTextStyles.bodyMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static Color _backgroundColor(AppMessageType type) {
    return switch (type) {
      AppMessageType.error => NavigoColors.accentRed,
      AppMessageType.success => NavigoColors.accentGreen,
      AppMessageType.info => NavigoColors.textDark,
    };
  }
}
