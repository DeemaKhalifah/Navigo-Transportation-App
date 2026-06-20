import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../utils/form_validation.dart';
import '../../utils/phone_auth_helpers.dart';
import '../../widgets/app_message.dart';
import 'otp_verification_screen.dart';

class DriverSignupScreen extends StatefulWidget {
  const DriverSignupScreen({super.key});

  @override
  State<DriverSignupScreen> createState() => _DriverSignupScreenState();
}

class _DriverSignupScreenState extends State<DriverSignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneDigitsController = TextEditingController();
  final TextEditingController _carNumberController = TextEditingController();
  final TextEditingController _licenseController = TextEditingController();

  String _phonePrefix = '+970';
  bool _agreeToTerms = false;
  String? _selectedRouteId;
  String? _selectedVehicleClass;

  static const List<Map<String, dynamic>> _vehicleOptions = [
    {
      'label': 'Bus - 45 seats',
      'vehicleType': 'bus',
      'capacity': 45,
      'vehicleClass': 'bus-45',
    },
    {
      'label': 'Bus - 14 seats',
      'vehicleType': 'bus',
      'capacity': 14,
      'vehicleClass': 'bus-14',
    },
    {
      'label': 'Microbus - 7 seats',
      'vehicleType': 'microbus',
      'capacity': 7,
      'vehicleClass': 'microbus-7',
    },
  ];

  Map<String, dynamic>? get _selectedVehicleOption {
    if (_selectedVehicleClass == null) return null;

    return _vehicleOptions.firstWhere(
      (e) => e['vehicleClass'] == _selectedVehicleClass,
    );
  }

  bool _isLoading = false;
  bool _routesLoading = true;
  String? _routesError;
  List<DropdownMenuItem<String>> _routeItems = [];

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _routesLoading = true;
      _routesError = null;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('route')
          .limit(50)
          .get();

      final items = <DropdownMenuItem<String>>[];

      for (final d in snap.docs) {
        final m = d.data();
        final a = m['startPoint']?.toString() ?? '';
        final b = m['endPoint']?.toString() ?? '';
        final label = a.isNotEmpty || b.isNotEmpty ? '$a → $b' : d.id;

        items.add(
          DropdownMenuItem<String>(
            value: d.id,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _routeItems = items;
        _routesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _routesError = e.toString();
        _routesLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneDigitsController.dispose();
    _carNumberController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  String get _fullPhoneNumber => PhoneAuthHelpers.buildFullPhoneNumber(
    countryCode: _phonePrefix,
    localPhoneNumber: _phoneDigitsController.text,
  );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_agreeToTerms) {
      AppMessage.showError(context, context.texts.t('pleaseAgreeToTerms'));
      return;
    }

    if (_selectedRouteId == null || _selectedRouteId!.isEmpty) {
      AppMessage.showError(context, context.texts.t('selectRoute'));
      return;
    }

    if (_selectedVehicleOption == null) {
      AppMessage.showError(context, context.texts.t('selectVehicleType'));
      return;
    }

    final selectedVehicle = _selectedVehicleOption!;

    final name = _nameController.text.trim();
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
    debugPrint('Driver signup selected country code: $_phonePrefix');
    debugPrint('Driver signup local phone number: $localPhoneNumber');
    PhoneAuthHelpers.logPhoneAuthConfigurationReminder();

    setState(() => _isLoading = true);

    try {
      final exists = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: fullPhoneNumber)
          .limit(1)
          .get();

      if (exists.docs.isNotEmpty) {
        if (!mounted) return;

        setState(() => _isLoading = false);

        AppMessage.showError(context, context.texts.t('phoneAlreadyUsed'));
        return;
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('Driver signup verificationCompleted');
          if (!mounted) return;
          setState(() => _isLoading = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(
                phoneNumber: fullPhoneNumber,
                verificationId: '',
                fullName: name,
                role: 'driver',
                driverData: {
                  'routeId': _selectedRouteId,
                  'plateNumber': _carNumberController.text.trim(),
                  'vehicleType': selectedVehicle['vehicleType'],
                  'capacity': selectedVehicle['capacity'],
                  'vehicleClass': selectedVehicle['vehicleClass'],
                  'licenseNumber': _licenseController.text.trim(),
                },
                autoCredential: credential,
              ),
            ),
          );
        },
        verificationFailed: (FirebaseAuthException e) {
          PhoneAuthHelpers.logFirebaseAuthException(
            'Driver signup verificationFailed',
            e,
          );
          if (!mounted) return;

          setState(() => _isLoading = false);

          AppMessage.showError(
            context,
            PhoneAuthHelpers.userMessageForFirebaseAuthException(e),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('Driver signup codeSent verificationId: $verificationId');
          debugPrint('Driver signup codeSent resendToken: $resendToken');
          if (!mounted) return;

          setState(() => _isLoading = false);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OtpVerificationScreen(
                phoneNumber: fullPhoneNumber,
                verificationId: verificationId,
                resendToken: resendToken,
                fullName: name,
                role: 'driver',
                driverData: {
                  'routeId': _selectedRouteId,
                  'plateNumber': _carNumberController.text.trim(),
                  'vehicleType': selectedVehicle['vehicleType'],
                  'capacity': selectedVehicle['capacity'],
                  'vehicleClass': selectedVehicle['vehicleClass'],
                  'licenseNumber': _licenseController.text.trim(),
                },
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint(
            'Driver signup codeAutoRetrievalTimeout verificationId: '
            '$verificationId',
          );
          if (!mounted) return;
          setState(() => _isLoading = false);
        },
      );
    } on FirebaseAuthException catch (e) {
      PhoneAuthHelpers.logFirebaseAuthException(
        'Driver signup verifyPhoneNumber threw',
        e,
      );
      if (!mounted) return;

      setState(() => _isLoading = false);

      AppMessage.showError(
        context,
        PhoneAuthHelpers.userMessageForFirebaseAuthException(e),
      );
    } catch (e) {
      debugPrint('Driver signup phone verification error: $e');
      if (!mounted) return;

      setState(() => _isLoading = false);

      AppMessage.showError(
        context,
        '${context.texts.t('couldNotVerifyPhone')}: $e',
      );
    }
  }

  String _vehicleLabel(Map<String, dynamic> option) {
    return option['label'] as String;
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
                              context.texts.t('driverDetails'),
                              style: NavigoTextStyles.titleLarge,
                            ),
                            const SizedBox(height: 20),

                            _label(context.texts.t('fullName')),
                            _inputField(
                              controller: _nameController,
                              hint: context.texts.t('exampleFullName'),
                              prefixIcon: Icons.person_outline,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r"[a-zA-Z\u0600-\u06FF\s'-]"),
                                ),
                              ],
                              validator: (v) =>
                                  AppFormValidators.fullName(context, v),
                            ),
                            const SizedBox(height: 16),

                            _label(context.texts.t('phoneNumber')),
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
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 16,
                                    ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(9),
                                    ],
                                    validator: (_) =>
                                        AppFormValidators.localPhoneNumber(
                                          context,
                                          countryCode: _phonePrefix,
                                          localPhoneNumber:
                                              _phoneDigitsController.text,
                                        ),
                                    decoration: NavigoDecorations
                                        .kInputDecoration
                                        .copyWith(
                                          hintText: '590000000',
                                          prefixIcon: const Icon(
                                            Icons.phone_outlined,
                                            color: Colors.green,
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

                            _label(context.texts.t('routeFromFirestore')),
                            if (_routesLoading)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (_routesError != null)
                              Text(
                                '${context.texts.t('couldNotLoadRoutes')}: $_routesError',
                                style: NavigoTextStyles.bodySmall,
                              )
                            else if (_routeItems.isEmpty)
                              Text(
                                context.texts.t('noRoutesFound'),
                                style: NavigoTextStyles.bodySmall,
                              )
                            else
                              _dropdownField(
                                value: _selectedRouteId,
                                hint: context.texts.t('selectRoute'),
                                items: _routeItems,
                                onChanged: (val) =>
                                    setState(() => _selectedRouteId = val),
                              ),
                            const SizedBox(height: 16),

                            _label(context.texts.t('carNumberPlate')),
                            _inputField(
                              controller: _carNumberController,
                              hint: context.texts.t('examplePlateNumber'),
                              prefixIcon: Icons.confirmation_number_outlined,
                              keyboard: TextInputType.number,
                              inputFormatters: [CarPlateInputFormatter()],
                              validator: (v) =>
                                  AppFormValidators.carPlate(context, v),
                            ),
                            const SizedBox(height: 16),

                            _label(context.texts.t('drivingLicenseOptional')),
                            _inputField(
                              controller: _licenseController,
                              hint: context.texts.t('licenseNumberHint'),
                              prefixIcon: Icons.badge_outlined,
                              validator: (_) => null,
                            ),
                            const SizedBox(height: 16),

                            _label(context.texts.t('carType')),
                            _dropdownField(
                              value: _selectedVehicleClass,
                              hint: context.texts.t('selectCarType'),
                              items: _vehicleOptions
                                  .map(
                                    (e) => DropdownMenuItem<String>(
                                      value: e['vehicleClass'] as String,
                                      child: Text(_vehicleLabel(e)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedVehicleClass = val),
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

                            const SizedBox(height: 25),

                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton(
                                onPressed:
                                    _isLoading ||
                                        _routesLoading ||
                                        _routeItems.isEmpty ||
                                        !_agreeToTerms
                                    ? null
                                    : _submit,
                                style:
                                    NavigoDecorations.kPrimaryButtonLargeStyle,
                                child: _isLoading
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

                            const SizedBox(height: 10),

                            Center(
                              child: Text(
                                context.texts.t('accountMayRequireApproval'),
                                style: NavigoTextStyles.bodySmall,
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

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: NavigoTextStyles.label),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    TextInputType keyboard = TextInputType.text,
    IconData? prefixIcon,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.black, fontSize: 16),
      inputFormatters: inputFormatters,
      validator:
          validator ??
          (value) => value == null || value.isEmpty
              ? context.texts.t('required')
              : null,
      decoration: NavigoDecorations.kInputDecoration.copyWith(
        hintText: hint,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, color: Colors.green)
            : null,
        suffixIcon: prefixIcon != null
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => controller.clear(),
              )
            : null,
      ),
    );
  }

  Widget _dropdownField({
    required String? value,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      style: const TextStyle(color: Colors.black, fontSize: 16),
      hint: Text(hint, style: const TextStyle(color: Colors.grey)),
      items: items,
      onChanged: onChanged,
      validator: (v) => AppFormValidators.requiredSelection(context, v),
      decoration: NavigoDecorations.kInputDecoration,
      icon: const Icon(Icons.keyboard_arrow_down),
    );
  }
}
