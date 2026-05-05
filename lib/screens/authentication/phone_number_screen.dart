import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../localization/localization_x.dart';
import '../../services/phone_login_storage_service.dart';
import '../../theme/app_theme.dart';
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
  final TextEditingController _phoneController = TextEditingController();
  final PhoneLoginStorageService _phoneLoginStorageService =
      PhoneLoginStorageService();
  bool _isSending = false;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedPhoneNumber();
  }

  Future<void> _loadRememberedPhoneNumber() async {
    final savedPhone =
        await _phoneLoginStorageService.getRememberedPhoneNumber();
    if (!mounted) return;

    if (savedPhone != null && savedPhone.trim().isNotEmpty) {
      _phoneController.text = savedPhone;
      setState(() => _rememberMe = true);
    } else {
      setState(() => _rememberMe = false);
    }
  }

  Future<void> _sendOtp() async {
    final phoneNumber = _phoneController.text.trim();

    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.texts.t('enterPhoneNumberSnack'))),
      );
      return;
    }

    if (_rememberMe) {
      await _phoneLoginStorageService.saveRememberedPhoneNumber(phoneNumber);
    } else {
      await _phoneLoginStorageService.clearRememberedPhoneNumber();
    }

    if (!mounted) return;
    setState(() => _isSending = true);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {},
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _isSending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${context.texts.t('errorLabel')}: ${e.message ?? ''}',
              ),
            ),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;

          setState(() => _isSending = false);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(
                phoneNumber: phoneNumber,
                verificationId: verificationId,
                fullName: widget.fullName,
                role: widget.role,
                driverData: widget.driverData,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;
          setState(() => _isSending = false);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.texts.t('failedToSendOtp')}: $e')),
      );
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            NavigoDecorations.topBar1(onBack: () => Navigator.pop(context)),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 450),
                      child: Container(
                        padding: const EdgeInsets.all(20),
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
                            TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              style: NavigoTextStyles.fieldText,
                              decoration: NavigoDecorations.kInputDecoration
                                  .copyWith(
                                    hintText: "e.g. +970590000000",
                                    prefixIcon: const Icon(
                                      Icons.phone_outlined,
                                      color: NavigoColors.accentGreen,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () => _phoneController.clear(),
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() => _rememberMe = value ?? false);
                              },
                              controlAffinity: ListTileControlAffinity.leading,
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
                              height: NavigoSizes.buttonHeightLarge,
                              child: ElevatedButton(
                                style:
                                    NavigoDecorations.kPrimaryButtonLargeStyle,
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
                                      builder: (_) => const EmailLoginScreen(),
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
    );
  }
}
