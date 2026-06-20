import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/localization_x.dart';
import 'phone_auth_helpers.dart';

class AppFormValidators {
  const AppFormValidators._();

  static String? fullName(BuildContext context, String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return context.texts.t('validation FullName Required');
    if (text.split(RegExp(r'\s+')).length < 2) {
      return context.texts.t('validation FullName Invalid');
    }
    return null;
  }

  static String? email(BuildContext context, String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return context.texts.t('validation Email Required');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
      return context.texts.t('validation Email Invalid');
    }
    return null;
  }

  static String? password(BuildContext context, String? value) {
    final text = value ?? '';
    if (text.trim().isEmpty) {
      return context.texts.t('validation Password Required');
    }
    return null;
  }

  static String? palestinianPhone(BuildContext context, String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return context.texts.t('validation Phone Required');

    // Palestinian phone numbers in this app must be entered in international
    // form so Firebase receives a stable E.164-style value.
    if (!text.startsWith('+970') && !text.startsWith('+972')) {
      return context.texts.t('validation Phone Prefix');
    }

    // After the country code, allow digits only and require the 9 local digits
    // used by Palestinian mobile numbers.
    if (!RegExp(r'^\+(970|972)\d{9}$').hasMatch(text)) {
      return context.texts.t('validation Phone Invalid');
    }

    return null;
  }

  static String? localPhoneNumber(
    BuildContext context, {
    required String countryCode,
    required String localPhoneNumber,
  }) {
    return PhoneAuthHelpers.validateLocalPhoneNumber(
      countryCode: countryCode,
      localPhoneNumber: localPhoneNumber,
    );
  }

  static String? carPlate(BuildContext context, String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return context.texts.t('validation Plate Required');
    if (!RegExp(r'^\d-\d{4}$').hasMatch(text)) {
      return context.texts.t('validation Plate Invalid');
    }
    return null;
  }

  static String? requiredSelection(BuildContext context, Object? value) {
    if (value == null) return context.texts.t('validation Selection Required');
    if (value is String && value.trim().isEmpty) {
      return context.texts.t('validation Selection Required');
    }
    return null;
  }
}

class PalestinianPhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = StringBuffer();

    // Keep only one leading plus sign and digits. This blocks letters and
    // symbols while still letting the user type +970 or +972 naturally.
    for (var i = 0; i < newValue.text.length; i++) {
      final char = newValue.text[i];
      if (i == 0 && char == '+') {
        cleaned.write(char);
      } else if (RegExp(r'\d').hasMatch(char)) {
        cleaned.write(char);
      }
    }

    var text = cleaned.toString();
    if (text.length > 13) text = text.substring(0, 13);

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class CarPlateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limited = digits.length > 5 ? digits.substring(0, 5) : digits;

    // Plate format is always one digit, a dash, then four digits. The dash is
    // inserted immediately after the first digit so users cannot enter letters,
    // extra symbols, or longer plate numbers.
    final text = limited.isEmpty
        ? ''
        : limited.length == 1
        ? '${limited[0]}-'
        : '${limited[0]}-${limited.substring(1)}';

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
