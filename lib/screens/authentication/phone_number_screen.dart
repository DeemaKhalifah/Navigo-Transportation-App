import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import '../../localization/localization_x.dart';
import '../../services/phone_login_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/phone_auth_helpers.dart';
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
      final phone = savedPhone.trim();
      if (phone.startsWith('+972') || phone.startsWith('+970')) {
        _phonePrefix = phone.startsWith('+972') ? '+972' : '+970';
        _phoneDigitsController.text = phone.substring(_phonePrefix.length);
      }
      setState(() => _rememberMe = true);
    } else {
      setState(() => _rememberMe = false);
    }
  }

  void _showPhoneError(FirebaseAuthException error) {
    AppMessage.showError(
      context,
      PhoneAuthHelpers.userMessageForFirebaseAuthException(error),
    );
  }

  Future<void> _sendOtp() async {
    final localPhoneNumber = _phoneDigitsController.text.trim();
    final validationError = PhoneAuthHelpers.validateLocalPhoneNumber(
      countryCode: _phonePrefix,
      localPhoneNumber: localPhoneNumber,
    );

    if (validationError != null) {
      AppMessage.showError(context, validationError);
      return;
    }

    final fullPhoneNumber = PhoneAuthHelpers.buildFullPhoneNumber(
      countryCode: _phonePrefix,
      localPhoneNumber: localPhoneNumber,
    );

    print('FULL PHONE NUMBER = $fullPhoneNumber');
    debugPrint('OTP selected country code: $_phonePrefix');
    debugPrint('OTP local phone number: $localPhoneNumber');
    PhoneAuthHelpers.logPhoneAuthConfigurationReminder();

    if (_rememberMe) {
      await _phoneLoginStorageService.saveRememberedPhoneNumber(
        fullPhoneNumber,
      );
    } else {
      await _phoneLoginStorageService.clearRememberedPhoneNumber();
    }

    if (!mounted) return;
    setState(() => _isSending = true);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('OTP verificationCompleted for $fullPhoneNumber');
          try {
            await FirebaseAuth.instance.signInWithCredential(credential);
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => OtpVerificationScreen(
                  phoneNumber: fullPhoneNumber,
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
            PhoneAuthHelpers.logFirebaseAuthException(
              'verificationCompleted signInWithCredential failed',
              e,
            );
            if (!mounted) return;
            _showPhoneError(e);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          PhoneAuthHelpers.logFirebaseAuthException(
            'verifyPhoneNumber verificationFailed',
            e,
          );
          if (!mounted) return;
          setState(() => _isSending = false);
          _showPhoneError(e);
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;

          debugPrint('OTP codeSent verificationId: $verificationId');
          debugPrint('OTP codeSent resendToken: $resendToken');
          setState(() => _isSending = false);
          _resendToken = resendToken;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(
                phoneNumber: fullPhoneNumber,
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
          debugPrint(
            'OTP codeAutoRetrievalTimeout verificationId: $verificationId',
          );
          if (!mounted) return;
          setState(() => _isSending = false);
        },
      );
    } on FirebaseAuthException catch (e) {
      PhoneAuthHelpers.logFirebaseAuthException('verifyPhoneNumber threw', e);
      if (!mounted) return;
      setState(() => _isSending = false);
      _showPhoneError(e);
    } catch (e) {
      debugPrint('verifyPhoneNumber unexpected error: $e');
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
                                      initialValue: _phonePrefix,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: '+970',
                                          child: Text(
                                            '+970',
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                        DropdownMenuItem(
                                          value: '+972',
                                          child: Text(
                                            '+972',
                                            style: TextStyle(
                                              color: Colors.grey,
                                            ),
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
                                                  _phoneDigitsController
                                                      .clear(),
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
