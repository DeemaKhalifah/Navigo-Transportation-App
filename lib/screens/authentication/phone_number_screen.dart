import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../../localization/localization_x.dart';
import '../../services/phone_login_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_message.dart';
import '../../widgets/responsive.dart';
import 'otp_verification_screen.dart';
import 'email_login.dart';

class PhoneNumberScreen extends StatefulWidget {
  final String? fullName;
  final String? role;
  final Map<String, dynamic>? driverData;

  const PhoneNumberScreen({
    super.key,
    this.fullName,
    this.role,
    this.driverData,
  });

  @override
  State<PhoneNumberScreen> createState() => _PhoneNumberScreenState();
}

class _PhoneNumberScreenState extends State<PhoneNumberScreen> {
  final TextEditingController _phoneDigitsController = TextEditingController();
  String _phonePrefix = '+970';
  final PhoneLoginStorageService _phoneLoginStorageService =
      PhoneLoginStorageService();
  bool _isSending = false;
  bool _rememberMe = false;
  int? _resendToken;

  @override
  void initState() {
    super.initState();
    _loadRememberedPhoneNumber();
  }

  Future<void> _loadRememberedPhoneNumber() async {
    final savedPhone = await _phoneLoginStorageService
        .getRememberedPhoneNumber();
    if (!mounted) return;

    if (savedPhone != null && savedPhone.trim().isNotEmpty) {
      final formatted = _formatPhoneForFirebase(savedPhone);
      if (formatted != null && formatted.startsWith('+')) {
        _phonePrefix = formatted.startsWith('+972') ? '+972' : '+970';
        _phoneDigitsController.text = formatted.substring(4);
      }
      setState(() => _rememberMe = true);
    } else {
      setState(() => _rememberMe = false);
    }
  }

  String? _formatPhoneForFirebase(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[\s\-\(\)\[\]\{\}]'), '');

    // Accept already formatted E.164-style values.
    if (cleaned.startsWith('+970') || cleaned.startsWith('+972')) {
      return cleaned;
    }

    // Accept local Palestinian mobile formats:
    // 059xxxxxxxx -> +97059xxxxxxx
    // 59xxxxxxxx  -> +97059xxxxxxx
    if (cleaned.startsWith('059')) {
      return '+970${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('59')) {
      return '+970$cleaned';
    }

    // Fallback: if user used the prefix dropdown + entered digits.
    final digitsOnly = cleaned.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isNotEmpty) {
      if (digitsOnly.startsWith('059') && digitsOnly.length >= 10) {
        return '+970${digitsOnly.substring(1)}';
      }
      if (digitsOnly.startsWith('59') && digitsOnly.length >= 9) {
        return '$_phonePrefix${digitsOnly.substring(0, 9)}';
      }
      if (digitsOnly.length == 9) {
        return '$_phonePrefix$digitsOnly';
      }
    }

    return null;
  }

  String _rawPhoneInput() {
    // "Raw" input in this UI is prefix + digits; still log it to help debugging.
    return '$_phonePrefix${_phoneDigitsController.text}';
  }

  String? _validatePalestinianMobile(String formatted) {
    // +97059xxxxxxx or +97259xxxxxxx (9 digits after country code).
    final ok = RegExp(r'^\+(970|972)59\d{7}$').hasMatch(formatted);
    return ok ? null : 'Invalid phone number. Use +97059xxxxxxx or +97259xxxxxxx';
  }

  void _showPhoneErrorForCode(String code) {
    final message = switch (code) {
      'invalid-phone-number' => 'Invalid phone number.',
      'app-not-authorized' => 'App is not authorized for phone auth.',
      'captcha-check-failed' => 'Captcha check failed. Try again.',
      'too-many-requests' => 'Too many requests. Please try later.',
      _ => 'Failed to send OTP. Please try again.',
    };
    AppMessage.showError(context, message);
  }

  Future<void> _sendOtp() async {
    final rawPhone = _rawPhoneInput();
    final rawDigits = _phoneDigitsController.text;
    final candidate = rawDigits.startsWith('0')
        ? rawDigits
        : '$_phonePrefix$rawDigits';
    final formattedPhone = _formatPhoneForFirebase(candidate) ?? '';

    debugPrint('OTP raw phone: $rawPhone');
    debugPrint('OTP formatted phone: $formattedPhone');

    if (_phoneDigitsController.text.trim().isEmpty) {
      AppMessage.showError(context, context.texts.t('enterPhoneNumberSnack'));
      return;
    }

    final formatError = formattedPhone.isEmpty
        ? 'Invalid phone number.'
        : _validatePalestinianMobile(formattedPhone);
    if (formatError != null) {
      AppMessage.showError(context, formatError);
      return;
    }

    if (_rememberMe) {
      await _phoneLoginStorageService.saveRememberedPhoneNumber(formattedPhone);
    } else {
      await _phoneLoginStorageService.clearRememberedPhoneNumber();
    }

    if (!mounted) return;
    setState(() => _isSending = true);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('OTP verificationCompleted for $formattedPhone');
          try {
            await FirebaseAuth.instance.signInWithCredential(credential);
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => OtpVerificationScreen(
                  phoneNumber: formattedPhone,
                  verificationId: '',
                  resendToken: _resendToken,
                  fullName: widget.fullName,
                  role: widget.role,
                  driverData: widget.driverData,
                  autoCredential: credential,
                ),
              ),
            );
          } on FirebaseAuthException catch (e) {
            debugPrint('verificationCompleted exception code: ${e.code}');
            debugPrint('verificationCompleted exception message: ${e.message}');
            if (!mounted) return;
            _showPhoneErrorForCode(e.code);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('verifyPhoneNumber failed code: ${e.code}');
          debugPrint('verifyPhoneNumber failed message: ${e.message}');
          if (!mounted) return;
          setState(() => _isSending = false);
          _showPhoneErrorForCode(e.code);
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;

          debugPrint('OTP codeSent verificationId: $verificationId');
          setState(() => _isSending = false);
          _resendToken = resendToken;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(
                phoneNumber: formattedPhone,
                verificationId: verificationId,
                resendToken: resendToken,
                fullName: widget.fullName,
                role: widget.role,
                driverData: widget.driverData,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('OTP codeAutoRetrievalTimeout verificationId: $verificationId');
          if (!mounted) return;
          setState(() => _isSending = false);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      AppMessage.showError(
        context,
        '${context.texts.t('failedToSendOtp')}: $e',
      );
    }
  }

  @override
  void dispose() {
    _phoneDigitsController.dispose();
    super.dispose();
  }

  void _goBack() {
    final navigator = Navigator.of(context);

    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    // Phone login can be the root route after logout/startup. Do not pop the
    // root route, because that leaves the app showing a black screen.
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      resizeToAvoidBottomInset: true,
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _goBack();
        },
        child: SafeArea(
          child: Column(
            children: [
              NavigoDecorations.topBar1(onBack: _goBack),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      // Responsive form padding keeps the card usable on small
                      // phones and centered/readable on tablets.
                      padding: EdgeInsets.all(padding),
                      child: ConstrainedBox(
                        constraints: Responsive.contentMaxWidth(context),
                        child: Container(
                          padding: EdgeInsets.all(padding.clamp(16, 24)),
                          decoration: NavigoDecorations.kCardDecoration,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                context.texts.t('enterPhoneNumber'),
                                style: NavigoTextStyles.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                context.texts.t('phoneOtpSubtitle'),
                                style: NavigoTextStyles.bodyMedium,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                context.texts.t('phoneNumber'),
                                style: NavigoTextStyles.label,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 110,
                                    child: DropdownButtonFormField<String>(
                                      value: _phonePrefix,
                                      style:
                                          const TextStyle(color: Colors.grey),
                                      items: const [
                                        DropdownMenuItem(
                                          value: '+970',
                                          child: Text(
                                            '+970',
                                            style:
                                                TextStyle(color: Colors.grey),
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: '+972',
                                          child: Text(
                                            '+972',
                                            style:
                                                TextStyle(color: Colors.grey),
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v == null) return;
                                        setState(() => _phonePrefix = v);
                                      },
                                      decoration: NavigoDecorations
                                          .kInputDecoration
                                          .copyWith(
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 14,
                                                ),
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: _phoneDigitsController,
                                      keyboardType: TextInputType.phone,
                                      style: NavigoTextStyles.fieldText,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(9),
                                      ],
                                      decoration: NavigoDecorations
                                          .kInputDecoration
                                          .copyWith(
                                            hintText: "590000000",
                                            prefixIcon: const Icon(
                                              Icons.phone_outlined,
                                              color: NavigoColors.accentGreen,
                                            ),
                                            suffixIcon: IconButton(
                                              icon: const Icon(Icons.clear),
                                              onPressed: () =>
                                                  _phoneDigitsController.clear(),
                                            ),
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              CheckboxListTile(
                                value: _rememberMe,
                                onChanged: (value) {
                                  setState(() => _rememberMe = value ?? false);
                                },
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(
                                  context.texts.t('rememberMe'),
                                  style: NavigoTextStyles.bodyMedium,
                                ),
                              ),
                              const SizedBox(height: 25),
                              SizedBox(
                                width: double.infinity,
                                height: Responsive.buttonHeight(context),
                                child: ElevatedButton(
                                  style: NavigoDecorations
                                      .kPrimaryButtonLargeStyle,
                                  onPressed: _isSending ? null : _sendOtp,
                                  child: _isSending
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: NavigoColors.textLight,
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              context.texts.t('sendCode'),
                                              style: NavigoTextStyles.button,
                                            ),
                                            const SizedBox(width: 10),
                                            const Icon(Icons.arrow_forward),
                                          ],
                                        ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Center(
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const EmailLoginScreen(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    "${context.texts.t('signIn')} (${context.texts.t('email')})",
                                    style: NavigoTextStyles.actionLink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
