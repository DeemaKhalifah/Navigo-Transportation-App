import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../theme/app_theme.dart';
import '../../services/passenger_trip_repository.dart';
import '../passenger/passenger_home_screen.dart';
import '../driver/driver_home_screen.dart';
import '../../models/driver_status.dart';
import '../../models/vehicle.dart';
import '../../services/vehicle_seat_count.dart';
import 'signup_approval.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final String? fullName;
  final String? role;
  final Map<String, dynamic>? driverData;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.fullName,
    this.role,
    this.driverData,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final PassengerTripRepository _passengerTripRepository =
      PassengerTripRepository();

  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;

  Future<void> _capturePassengerLoginLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await _passengerTripRepository.syncPassengerDocumentLocation(
        LatLng(position.latitude, position.longitude),
      );
    } catch (e) {
      debugPrint('Passenger login location: $e');
    }
  }

  @override
  void dispose() {
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _handleDriverFlow({
    required String uid,
    required String firstName,
    required String lastName,
  }) async {
    final driverInfo = widget.driverData ?? {};
    final fs = FirebaseFirestore.instance;

    String vehicleId = (driverInfo['vehicleId'] as String?)?.trim() ?? '';
    final String plate = (driverInfo['plateNumber'] as String?)?.trim() ?? '';
    final String vType =
        (driverInfo['vehicleType'] as String?)?.trim() ?? 'Unknown';
    final String license =
        (driverInfo['licenseNumber'] as String?)?.trim() ?? '';
    final String routeId =
        (driverInfo['routeId'] as String?)?.trim() ??
        (driverInfo['route'] as String?)?.trim() ??
        '';
    final String driverStatus =
        (driverInfo['status'] as String?)?.trim().isNotEmpty == true
        ? (driverInfo['status'] as String).trim()
        : DriverStatus.offline;
    final bool isApproved = driverInfo['isApproved'] == true;

    if (vehicleId.isEmpty) {
      final vehicleRef = fs.collection('vehicles').doc();
      vehicleId = vehicleRef.id;

      final vehicle = Vehicle(
        vehicleId: vehicleId,
        type: vType,
        plateNumber: plate,
        seatCount: defaultSeatCountForVehicleType(vType),
        licenseNumber: license,
      );

      final batch = fs.batch();

      batch.set(vehicleRef, {...vehicle.toMap(), 'driverId': uid});

      batch.set(fs.collection('drivers').doc(uid), {
        'userId': uid,
        'firstName': firstName,
        'lastName': lastName,
        'phone': widget.phoneNumber,
        'image': null,
        'role': 'driver',
        'isVerified': true,
        'isOnline': false,
        'vehicleId': vehicleId,
        'routeId': routeId,
        'status': driverStatus,
        'isApproved': isApproved,
        'latitude': null,
        'longitude': null,
        'location': null,
        'lastLocationUpdate': null,
      });

      await batch.commit();
    } else {
      await fs.collection('drivers').doc(uid).set({
        'userId': uid,
        'firstName': firstName,
        'lastName': lastName,
        'phone': widget.phoneNumber,
        'image': null,
        'role': 'driver',
        'isVerified': true,
        'isOnline': false,
        'vehicleId': vehicleId,
        'routeId': routeId,
        'status': driverStatus,
        'isApproved': isApproved,
        'latitude': null,
        'longitude': null,
        'location': null,
        'lastLocationUpdate': null,
      }, SetOptions(merge: true));
    }

    final driverDoc = await fs.collection('drivers').doc(uid).get();
    final bool approved = driverDoc.data()?['isApproved'] == true;

    if (!mounted) return;

    if (approved) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SignupApprovalScreen()),
      );
    }
  }

  Future<void> _onContinue() async {
    final otp = _otpControllers.map((e) => e.text).join().trim();

    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid 6-digit OTP")),
      );
      return;
    }

    if (widget.verificationId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Verification ID is missing.")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: otp,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final user = userCredential.user;
      if (user == null) {
        throw Exception('User not found after verification.');
      }

      final uid = user.uid;

      String firstName = '';
      String lastName = '';

      if (widget.fullName != null && widget.fullName!.trim().isNotEmpty) {
        final names = widget.fullName!.trim().split(RegExp(r'\s+'));
        firstName = names.isNotEmpty ? names.first : '';
        lastName = names.length > 1 ? names.sublist(1).join(' ') : '';
      }

      final Map<String, dynamic> userData = {
        'userId': uid,
        'phone': widget.phoneNumber,
        'image': null,
        'isVerified': true,
        'isOnline': false,
      };

      if (firstName.isNotEmpty) {
        userData['firstName'] = firstName;
      }

      if (lastName.isNotEmpty) {
        userData['lastName'] = lastName;
      }

      if (widget.role != null && widget.role!.trim().isNotEmpty) {
        userData['role'] = widget.role!.trim();
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(userData, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'latitude': FieldValue.delete(),
        'longitude': FieldValue.delete(),
        'location': FieldValue.delete(),
        'lastLocationUpdate': FieldValue.delete(),
      });

      if (widget.role == 'passenger') {
        await FirebaseFirestore.instance.collection('passengers').doc(uid).set({
          'passengerId': uid,
          'fullName': [firstName, lastName]
              .where((part) => part.trim().isNotEmpty)
              .join(' '),
          'phoneNumber': widget.phoneNumber,
          'latitude': null,
          'longitude': null,
          'lastLocationUpdate': null,
        }, SetOptions(merge: true));

        await _capturePassengerLoginLocation();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PassengerHomeScreen()),
        );
        return;
      }

      if (widget.role == 'driver') {
        await _handleDriverFlow(
          uid: uid,
          firstName: firstName,
          lastName: lastName,
        );
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final role = (userDoc.data()?['role'] ?? '').toString();

      if (!mounted) return;

      if (role == 'passenger') {
        await _capturePassengerLoginLocation();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PassengerHomeScreen()),
        );
      } else if (role == 'driver') {
        final driverDoc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(uid)
            .get();

        final bool isApproved = driverDoc.data()?['isApproved'] == true;

        if (!mounted) return;

        if (isApproved) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SignupApprovalScreen()),
          );
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("User role not found")));
      }
    } on FirebaseAuthException catch (e) {
      String message = e.message ?? 'Verification failed';

      if (e.code == 'invalid-verification-code') {
        message = 'The OTP code is incorrect.';
      } else if (e.code == 'session-expired') {
        message = 'The OTP code has expired. Please request a new one.';
      } else if (e.code == 'invalid-verification-id') {
        message = 'Verification session is invalid. Please try again.';
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      debugPrint('OTP verification error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _resendCode() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Resend not implemented yet")));
  }

  Widget _buildOtpTextField(int index) {
    return SizedBox(
      height: 56,
      child: TextField(
        controller: _otpControllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        maxLength: 1,
        style: NavigoTextStyles.fieldText.copyWith(fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          counterText: "",
          contentPadding: EdgeInsets.zero,
          filled: true,
          fillColor: NavigoColors.inputFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: NavigoColors.primaryOrange.withOpacity(0.3),
              width: 1.2,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: NavigoColors.primaryOrange,
              width: 2,
            ),
          ),
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            _focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            _focusNodes[index - 1].requestFocus();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundAlt,
      body: SafeArea(
        child: Column(
          children: [
            NavigoDecorations.topBar1(onBack: () => Navigator.pop(context)),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 450),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 32,
                        horizontal: 24,
                      ),
                      decoration: NavigoDecorations.kCardDecoration,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "Verify phone number",
                            style: NavigoTextStyles.titleLarge,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Enter the 6-digit code sent to ${widget.phoneNumber}",
                            textAlign: TextAlign.center,
                            style: NavigoTextStyles.bodySmall,
                          ),
                          const SizedBox(height: 28),
                          Row(
                            children: List.generate(6, (index) {
                              return Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: _buildOtpTextField(index),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Didn't receive SMS? ",
                                style: NavigoTextStyles.bodySmall,
                              ),
                              GestureDetector(
                                onTap: _resendCode,
                                child: const Text(
                                  "Resend Code",
                                  style: NavigoTextStyles.buttonOrangeLink,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: NavigoSizes.buttonHeight,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _onContinue,
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
                                  : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: const [
                                        Text(
                                          "Continue",
                                          style: NavigoTextStyles.button,
                                        ),
                                        SizedBox(width: 10),
                                        Icon(Icons.arrow_forward),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            "note: OTP expires in 2 minutes.",
                            style: NavigoTextStyles.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: const Text(
                              "Change phone number",
                              style: NavigoTextStyles.actionLink,
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
