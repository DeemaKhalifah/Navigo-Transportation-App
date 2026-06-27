import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PhoneAuthHelpers {
  const PhoneAuthHelpers._();

  static const Map<String, int> localPhoneLengthsByCountryCode = {
    '+970': 9,
    '+972': 9,
  };

  static String buildFullPhoneNumber({
    required String countryCode,
    required String localPhoneNumber,
  }) {
    return '${countryCode.trim()}${localPhoneNumber.trim()}';
  }

  static String? validateLocalPhoneNumber({
    required String countryCode,
    required String localPhoneNumber,
  }) {
    final digits = localPhoneNumber.trim();
    final expectedLength = localPhoneLengthsByCountryCode[countryCode];

    if (digits.isEmpty) {
      return 'Please enter your phone number.';
    }

    if (!RegExp(r'^\d+$').hasMatch(digits)) {
      return 'Phone number can contain digits only.';
    }

    if (expectedLength == null) {
      return 'Please select a supported country code.';
    }

    if (digits.length != expectedLength) {
      return 'Phone number must be $expectedLength digits for $countryCode.';
    }

    return null;
  }

  static String? validateFullPhoneNumber(String fullPhoneNumber) {
    final phone = fullPhoneNumber.trim();
    String? countryCode;
    for (final code in localPhoneLengthsByCountryCode.keys) {
      if (phone.startsWith(code)) {
        countryCode = code;
        break;
      }
    }

    if (countryCode == null) {
      return 'Please select a supported country code.';
    }

    final localNumber = phone.substring(countryCode.length);
    return validateLocalPhoneNumber(
      countryCode: countryCode,
      localPhoneNumber: localNumber,
    );
  }

  static String userMessageForFirebaseAuthException(
    FirebaseAuthException error, {
    String fallback = 'Failed to send OTP. Please try again.',
  }) {
    final baseMessage = switch (error.code) {
      'invalid-phone-number' =>
        'The phone number is invalid. Check the country code and local number.',
      'too-many-requests' =>
        'Too many requests were made from this device. Please try again later.',
      'quota-exceeded' =>
        'SMS quota has been exceeded. Please try again later.',
      'network-request-failed' =>
        'Network error. Check your internet connection and try again.',
      'session-expired' =>
        'The verification session expired. Please request a new code.',
      'internal-error' =>
        'Firebase had an internal error. Please try again in a moment.',
      'app-not-authorized' =>
        'This app is not authorized for Firebase Phone Authentication.',
      'captcha-check-failed' =>
        'Security verification failed. Please try again.',
      'missing-phone-number' =>
        'Please enter your phone number before requesting a code.',
      'invalid-verification-code' =>
        'The OTP code is incorrect. Please check it and try again.',
      'invalid-verification-id' =>
        'The verification session is invalid. Please request a new code.',
      'unknown' =>
        'Firebase returned an unknown error. Please try again.',
      _ => error.message?.trim().isNotEmpty == true
          ? error.message!
          : fallback,
    };

    if (kDebugMode) {
      return '$baseMessage\nFirebase error code: ${error.code}';
    }

    return baseMessage;
  }

  static void logFirebaseAuthException(
    String label,
    FirebaseAuthException error,
  ) {
    debugPrint('$label platform: $defaultTargetPlatform');
    debugPrint('$label code: ${error.code}');
    debugPrint('$label message: ${error.message}');
    if (error.email != null) debugPrint('$label email: ${error.email}');
    if (error.phoneNumber != null) {
      debugPrint('$label phoneNumber: ${error.phoneNumber}');
    }
    if (error.tenantId != null) debugPrint('$label tenantId: ${error.tenantId}');
  }

  static void logPhoneAuthConfigurationReminder() {
    debugPrint(
      'Firebase Phone Auth reminder: Android needs SHA-1/SHA-256 in Firebase; '
      'iOS needs matching Bundle ID, APNs key/cert or reCAPTCHA fallback, and '
      'the reversed client ID URL scheme in Info.plist.',
    );
  }
}
