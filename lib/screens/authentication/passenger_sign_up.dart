import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../utils/form_validation.dart';
import '../../widgets/app_message.dart';
import 'otp_verification_screen.dart';

class PassengerSignupScreen extends StatefulWidget {
  const PassengerSignupScreen({super.key});

  @override
  State<PassengerSignupScreen> createState() => _PassengerSignupScreenState();
}

class _PassengerSignupScreenState extends State<PassengerSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneDigitsController = TextEditingController();
  String _phonePrefix = '+970';
  bool _agreeToTerms = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneDigitsController.dispose();
    super.dispose();
  }

  void _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    if (!_agreeToTerms) {
      AppMessage.showError(context, context.texts.t('pleaseAgreeToTerms'));
      return;
    }

    setState(() => _isLoading = true);
    final name = _nameController.text.trim();
    final formattedPhone = '$_phonePrefix${_phoneDigitsController.text.trim()}';

    try {
      final exists = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: formattedPhone)
          .limit(1)
          .get();
      if (exists.docs.isNotEmpty) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        AppMessage.showError(context, context.texts.t('phoneAlreadyUsed'));
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppMessage.showError(
        context,
        '${context.texts.t('couldNotVerifyPhone')}: $e',
      );
      return;
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: formattedPhone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        await FirebaseAuth.instance.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        AppMessage.showError(
          context,
          '${context.texts.t('errorLabel')}: ${e.message ?? e.code}',
        );
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
              phoneNumber: formattedPhone,
              verificationId: verificationId,
              fullName: name,
              role: "passenger",
            ),
          ),
        );
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        if (!mounted) return;
        setState(() => _isLoading = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            /// Top Bar
            NavigoDecorations.topBar1(onBack: () => Navigator.pop(context)),

            /// Centered Body
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 450),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: NavigoDecorations.kCardDecoration,
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              context.texts.t('passengerDetails'),
                              style: NavigoTextStyles.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              context.texts.t('passengerSignupSubtitle'),
                              style: NavigoTextStyles.bodyMedium,
                            ),
                            const SizedBox(height: 20),

                            Text(
                              context.texts.t('fullName'),
                              style: NavigoTextStyles.label,
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _nameController,
                              keyboardType: TextInputType.name,
                              style: NavigoTextStyles.fieldText,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r"[a-zA-Z\u0600-\u06FF\s'-]"),
                                ),
                              ],
                              validator: (v) =>
                                  AppFormValidators.fullName(context, v),
                              decoration: NavigoDecorations.kInputDecoration
                                  .copyWith(
                                    hintText: context.texts.t(
                                      'exampleFullName',
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                      color: NavigoColors.accentGreen,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () => _nameController.clear(),
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 16),

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
                                    style: const TextStyle(color: Colors.grey),
                                    items: const [
                                      DropdownMenuItem(
                                        value: '+970',
                                        child: Text(
                                          '+970',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: '+972',
                                        child: Text(
                                          '+972',
                                          style: TextStyle(color: Colors.grey),
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
                                  child: TextFormField(
                                    controller: _phoneDigitsController,
                                    keyboardType: TextInputType.phone,
                                    style: NavigoTextStyles.fieldText,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(9),
                                    ],
                                    validator: (_) =>
                                        AppFormValidators.palestinianPhone(
                                          context,
                                          '$_phonePrefix${_phoneDigitsController.text.trim()}',
                                        ),
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
                            const SizedBox(height: 16),

                            Row(
                              children: [
                                Checkbox(
                                  value: _agreeToTerms,
                                  onChanged: (value) {
                                    setState(() {
                                      _agreeToTerms = value ?? false;
                                    });
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: NavigoTextStyles.bodyMedium
                                          .copyWith(
                                            color: NavigoColors.textDark,
                                            fontSize: 13,
                                          ),
                                      children: [
                                        TextSpan(
                                          text:
                                              '${context.texts.t('agreeTo')} ',
                                        ),
                                        TextSpan(
                                          text: context.texts.t('terms'),
                                          style: const TextStyle(
                                            color: NavigoColors.primaryOrange,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = () {},
                                        ),
                                        const TextSpan(text: " & "),
                                        TextSpan(
                                          text: context.texts.t('privacy'),
                                          style: const TextStyle(
                                            color: NavigoColors.primaryOrange,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          recognizer: TapGestureRecognizer()
                                            ..onTap = () {},
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            SizedBox(
                              width: double.infinity,
                              height: NavigoSizes.buttonHeightLarge,
                              child: ElevatedButton(
                                style:
                                    NavigoDecorations.kPrimaryButtonLargeStyle,
                                onPressed: (!_agreeToTerms || _isLoading)
                                    ? null
                                    : _submit,
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          color: NavigoColors.textLight,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            context.texts.t(
                                              'continueToVerifyPhone',
                                            ),
                                            style: NavigoTextStyles.button,
                                          ),
                                          const SizedBox(width: 10),
                                          const Icon(Icons.arrow_forward),
                                        ],
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
