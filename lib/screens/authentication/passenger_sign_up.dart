import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import 'otp_verification_screen.dart';

class PassengerSignupScreen extends StatefulWidget {
  const PassengerSignupScreen({super.key});

  @override
  State<PassengerSignupScreen> createState() => _PassengerSignupScreenState();
}

class _PassengerSignupScreenState extends State<PassengerSignupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _agreeToTerms = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.texts.t('pleaseFillAllFields'))),
      );
      return;
    }

    setState(() => _isLoading = true);
    final formattedPhone = _formatPhoneNumber(phone);

    try {
      final exists = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: formattedPhone)
          .limit(1)
          .get();
      if (exists.docs.isNotEmpty) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.texts.t('phoneAlreadyUsed'))),
        );
        return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${context.texts.t('couldNotVerifyPhone')}: $e'),
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.texts.t('errorLabel')}: ${e.message}'),
          ),
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

  String _formatPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'\s+'), '');

    // ✅ Already international
    if (cleaned.startsWith('+970') || cleaned.startsWith('+972')) {
      return cleaned;
    }

    // ✅ Local Palestinian format
    if (cleaned.startsWith('0')) {
      return '+970${cleaned.substring(1)}';
    }

    // ✅ Starts with 5 (e.g. 59xxxxxxx)
    if (cleaned.startsWith('5')) {
      return '+970$cleaned';
    }

    return cleaned;
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

                          /// Name Field
                          Text(
                            context.texts.t('fullName'),
                            style: NavigoTextStyles.label,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _nameController,
                            keyboardType: TextInputType.name,
                            // ← Forces black text in the name field
                            style: NavigoTextStyles.fieldText,
                            decoration: NavigoDecorations.kInputDecoration
                                .copyWith(
                                  hintText: context.texts.t('exampleFullName'),
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

                          /// Phone Field
                          Text(
                            context.texts.t('phoneNumber'),
                            style: NavigoTextStyles.label,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            // ← Forces black text in the phone field
                            style: NavigoTextStyles.fieldText,
                            decoration: NavigoDecorations.kInputDecoration
                                .copyWith(
                                  hintText: "+97059 000 0000",
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
                          const SizedBox(height: 16),

                          /// Terms Checkbox
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
                                    style: NavigoTextStyles.bodyMedium.copyWith(
                                      color: NavigoColors.textDark,
                                      fontSize: 13,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '${context.texts.t('agreeTo')} ',
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

                          /// Create Account Button
                          SizedBox(
                            width: double.infinity,
                            height: NavigoSizes.buttonHeightLarge,
                            child: ElevatedButton(
                              style: NavigoDecorations.kPrimaryButtonLargeStyle,
                              onPressed: (_agreeToTerms && !_isLoading)
                                  ? _submit
                                  : null,
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
                                          context.texts.t('createAccount'),
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
          ],
        ),
      ),
    );
  }
}
