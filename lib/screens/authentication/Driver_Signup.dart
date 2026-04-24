import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/app_theme.dart';
import 'otp_verification_screen.dart';

class DriverSignupScreen extends StatefulWidget {
  const DriverSignupScreen({super.key});

  @override
  State<DriverSignupScreen> createState() => _DriverSignupScreenState();
}

class _DriverSignupScreenState extends State<DriverSignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _carNumberController = TextEditingController();
  final TextEditingController _licenseController = TextEditingController();

  String? _selectedRouteId;
  String? _selectedCarType;

  static const List<String> _carTypes = ['Bus', 'Mini Bus', 'Van'];

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
      final snap =
          await FirebaseFirestore.instance.collection('route').limit(50).get();
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
    _phoneController.dispose();
    _carNumberController.dispose();
    _licenseController.dispose();
    super.dispose();
  }

  String _formatPhoneNumber(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'\s+'), '');

    if (cleaned.startsWith('+970') || cleaned.startsWith('+972')) {
      return cleaned;
    }

    if (cleaned.startsWith('0')) {
      return '+970${cleaned.substring(1)}';
    }

    if (cleaned.startsWith('5')) {
      return '+970$cleaned';
    }

    return cleaned;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRouteId == null || _selectedRouteId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a route')),
      );
      return;
    }
    if (_selectedCarType == null || _selectedCarType!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select vehicle type')),
      );
      return;
    }

    final name = _nameController.text.trim();
    final formattedPhone = _formatPhoneNumber(_phoneController.text.trim());

    setState(() => _isLoading = true);

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
          const SnackBar(
            content: Text(
              "This phone number is already used. Please use another number.",
            ),
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
            SnackBar(content: Text("Error: ${e.message}")),
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
                role: "driver",
                driverData: {
                  'routeId': _selectedRouteId,
                  'plateNumber': _carNumberController.text.trim(),
                  'vehicleType': _selectedCarType,
                  'licenseNumber': _licenseController.text.trim(),
                },
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;
          setState(() => _isLoading = false);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Could not verify phone number: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            NavigoDecorations.topBar(onBack: () => Navigator.pop(context)),
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
                            const Text(
                              'Driver details',
                              style: NavigoTextStyles.titleLarge,
                            ),
                            const SizedBox(height: 20),
                            _label('Full name'),
                            _inputField(
                              controller: _nameController,
                              hint: 'e.g., Ahmad Saleh',
                              prefixIcon: Icons.person_outline,
                            ),
                            const SizedBox(height: 16),
                            _label('Phone number'),
                            _inputField(
                              controller: _phoneController,
                              hint: '+97059 000 0000',
                              prefixIcon: Icons.phone_outlined,
                              keyboard: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            _label('Route (from Firestore)'),
                            if (_routesLoading)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            else if (_routesError != null)
                              Text(
                                'Could not load routes: $_routesError',
                                style: NavigoTextStyles.bodySmall,
                              )
                            else if (_routeItems.isEmpty)
                              const Text(
                                'No routes found. Add documents under collection `route` first.',
                                style: NavigoTextStyles.bodySmall,
                              )
                            else
                              _dropdownField(
                                value: _selectedRouteId,
                                hint: 'Select route',
                                items: _routeItems,
                                onChanged: (val) =>
                                    setState(() => _selectedRouteId = val),
                              ),
                            const SizedBox(height: 16),
                            _label('Car number (plate)'),
                            _inputField(
                              controller: _carNumberController,
                              hint: 'e.g., 7-1234',
                              prefixIcon: Icons.confirmation_number_outlined,
                            ),
                            const SizedBox(height: 16),
                            _label('Driving license number (optional)'),
                            _inputField(
                              controller: _licenseController,
                              hint: 'License #',
                              prefixIcon: Icons.badge_outlined,
                              validator: (_) => null,
                            ),
                            const SizedBox(height: 16),
                            _label('Car type'),
                            _dropdownField(
                              value: _selectedCarType,
                              hint: 'Select car type',
                              items: _carTypes
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedCarType = val),
                            ),
                            const SizedBox(height: 25),
                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton(
                                onPressed: _isLoading ||
                                        _routesLoading ||
                                        _routeItems.isEmpty
                                    ? null
                                    : _submit,
                                style: NavigoDecorations.kPrimaryButtonLargeStyle,
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: NavigoColors.textLight,
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            'Continue to verify phone',
                                            style: NavigoTextStyles.button,
                                          ),
                                          SizedBox(width: 10),
                                          Icon(Icons.arrow_forward),
                                        ],
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Center(
                              child: Text(
                                'Your account may require approval.',
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
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.black, fontSize: 16),
      validator: validator ??
          (value) => value == null || value.isEmpty ? 'Required' : null,
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
      validator: (v) => v == null ? 'Required' : null,
      decoration: NavigoDecorations.kInputDecoration,
      icon: const Icon(Icons.keyboard_arrow_down),
    );
  }
}
