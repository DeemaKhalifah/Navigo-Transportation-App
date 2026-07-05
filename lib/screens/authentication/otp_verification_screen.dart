import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/services.dart';

import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../services/passenger_trip_repository.dart';
import '../../services/local_storage_service.dart';
import '../passenger/passenger_home_screen.dart';
import '../driver/driver_home_screen.dart';
import '../../models/driver_status.dart';
import '../../services/vehicle_seat_count.dart';
import '../../utils/phone_auth_helpers.dart';
import '../../widgets/app_message.dart';
import 'signup_approval.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String verificationId;
  final int? resendToken;
  final String? fullName;
  final String? role;
  final Map<String, dynamic>? driverData;
  final PhoneAuthCredential? autoCredential;
  final bool isDemoTestMode;

  const OtpVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.verificationId,
    this.resendToken,
    this.fullName,
    this.role,
    this.driverData,
    this.autoCredential,
    this.isDemoTestMode = false,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final PassengerTripRepository _passengerTripRepository =
      PassengerTripRepository();

  late String _verificationId;
  int? _resendToken;
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  late bool _isDemoTestMode;
  bool _navigatedAway = false;

  @override
  void initState() {
    super.initState();
    _verificationId = widget.verificationId;
    _resendToken = widget.resendToken;
    _isDemoTestMode = widget.isDemoTestMode;

    debugPrint('OTP screen phone: ${widget.phoneNumber}');
    debugPrint('OTP screen initial verificationId: $_verificationId');
    debugPrint('OTP screen platform: $defaultTargetPlatform');
    debugPrint('OTP screen demo/test mode: $_isDemoTestMode');

    final auto = widget.autoCredential;
    if (auto != null && !_isDemoTestMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _signInAndContinue(autoVerifiedCredential: auto);
      });
    }
  }

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

  String _stringValue(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  String _normalizeRole(String? role) {
    final value = (role ?? '').trim().toLowerCase();
    if (value == 'route_manager' ||
        value == 'route_manger' ||
        value == 'route manager' ||
        value == 'routemanager' ||
        value == 'manager') {
      return 'route_manager';
    }
    return value;
  }

  int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_stringValue(value));
  }

  ({String firstName, String lastName}) _namePartsFromWidget() {
    final fullName = widget.fullName?.trim() ?? '';
    if (fullName.isEmpty) return (firstName: '', lastName: '');

    final names = fullName.split(RegExp(r'\s+'));
    return (
      firstName: names.isNotEmpty ? names.first : '',
      lastName: names.length > 1 ? names.sublist(1).join(' ') : '',
    );
  }

  String _demoEmailForPhone(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    return 'ios-demo-$digits@navigo.test';
  }

  String get _demoPassword => 'NavigoIosDemo123!';

  Future<User> _signInDemoFirebaseUser(String phoneNumber) async {
    final auth = FirebaseAuth.instance;
    final currentUser = auth.currentUser;

    if (currentUser != null) {
      await auth.signOut();
    }

    final email = _demoEmailForPhone(phoneNumber);
    debugPrint('Demo/test OTP signing in with demo email: $email');

    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: email,
        password: _demoPassword,
      );
      final user = credential.user;
      if (user == null) {
        throw Exception('Demo Firebase user was not returned after sign in.');
      }
      return user;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found' &&
          e.code != 'invalid-credential' &&
          e.code != 'INVALID_LOGIN_CREDENTIALS') {
        rethrow;
      }
    }

    final created = await auth.createUserWithEmailAndPassword(
      email: email,
      password: _demoPassword,
    );
    final user = created.user;
    if (user == null) {
      throw Exception('Demo Firebase user was not returned after creation.');
    }
    return user;
  }

  void _showOtpError(String message) {
    if (!mounted) return;

    try {
      AppMessage.showError(context, message);
    } catch (e) {
      debugPrint('OTP show error failed: $e');
    }
  }

  void _showOtpInfo(String message) {
    if (!mounted) return;

    try {
      AppMessage.showInfo(context, message);
    } catch (e) {
      debugPrint('OTP show info failed: $e');
    }
  }

  void _pushReplacement(Widget screen) {
    if (!mounted) return;

    debugPrint('Navigating to screen');
    _navigatedAway = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
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

    String vehicleId = _stringValue(driverInfo['vehicleId']);
    final String plate = _stringValue(driverInfo['plateNumber']);

    final rawVehicleType = _stringValue(driverInfo['vehicleType']);
    final String vehicleType = rawVehicleType.isNotEmpty
        ? rawVehicleType
        : 'bus';

    final int capacity =
        _intValue(driverInfo['capacity']) ??
        defaultSeatCountForVehicleType(vehicleType);

    final rawVehicleClass = _stringValue(driverInfo['vehicleClass']);
    final String vehicleClass = rawVehicleClass.isNotEmpty
        ? rawVehicleClass
        : vehicleType == 'microbus'
        ? 'microbus-7'
        : 'bus-$capacity';

    final String license = _stringValue(driverInfo['licenseNumber']);

    final String routeId = _stringValue(driverInfo['routeId']).isNotEmpty
        ? _stringValue(driverInfo['routeId'])
        : _stringValue(driverInfo['route']);

    final rawDriverStatus = _stringValue(driverInfo['status']);
    final String driverStatus = rawDriverStatus.isNotEmpty
        ? rawDriverStatus
        : DriverStatus.offline;

    final bool isApproved = driverInfo['isApproved'] == true;

    debugPrint('Saving user to Firestore');
    if (vehicleId.isEmpty) {
      final vehicleRef = fs.collection('vehicles').doc();
      vehicleId = vehicleRef.id;

      final batch = fs.batch();

      batch.set(vehicleRef, {
        'vehicleId': vehicleId,
        'type': vehicleType,
        'vehicleType': vehicleType,
        'vehicleClass': vehicleClass,
        'plateNumber': plate,
        'seatCount': capacity,
        'capacity': capacity,
        'licenseNumber': license,
        'driverId': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

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
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
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
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    debugPrint('Firestore save success');

    final driverDoc = await fs.collection('drivers').doc(uid).get();
    final bool approved = driverDoc.data()?['isApproved'] == true;
    await LocalStorageService.saveDriverDisplayName(
      '$firstName $lastName'.trim(),
    );
    await LocalStorageService.saveDriverStatus(
      DriverStatus.normalize(driverDoc.data()?['status']?.toString()),
    );

    if (!mounted) return;

    if (approved) {
      _pushReplacement(const DriverHomeScreen());
    } else {
      _pushReplacement(const SignupApprovalScreen());
    }
  }

  Future<void> _signInAndContinue({
    required PhoneAuthCredential autoVerifiedCredential,
    String? otp,
  }) async {
    if (!mounted) return;

    final texts = context.texts;
    final phoneNumber = widget.phoneNumber.trim();
    final requestedRole = _normalizeRole(widget.role);
    setState(() => _isLoading = true);

    try {
      debugPrint('OTP verification started');
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        autoVerifiedCredential,
      );
      debugPrint('OTP verification success');

      final user = userCredential.user;
      if (user == null) {
        throw Exception(texts.t('userNotFoundVerification'));
      }

      if (phoneNumber.isEmpty) {
        throw Exception('Phone number is missing.');
      }

      final uid = user.uid;
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final existingUser = await userRef.get();
      final existingImage =
          existingUser.data()?['image']?.toString().trim() ?? '';

      String firstName = '';
      String lastName = '';

      final fullName = widget.fullName?.trim() ?? '';
      if (fullName.isNotEmpty) {
        final names = fullName.split(RegExp(r'\s+'));
        firstName = names.isNotEmpty ? names.first : '';
        lastName = names.length > 1 ? names.sublist(1).join(' ') : '';
      }

      final Map<String, dynamic> userData = {
        'userId': uid,
        'phone': phoneNumber,
        'image': existingImage,
        'isVerified': true,
        'isOnline': false,
      };

      if (firstName.isNotEmpty) {
        userData['firstName'] = firstName;
      }

      if (lastName.isNotEmpty) {
        userData['lastName'] = lastName;
      }

      if (requestedRole.isNotEmpty) {
        userData['role'] = requestedRole;
      }

      debugPrint('Saving user to Firestore');
      await userRef.set(userData, SetOptions(merge: true));

      await userRef.update({
        'latitude': FieldValue.delete(),
        'longitude': FieldValue.delete(),
        'location': FieldValue.delete(),
        'lastLocationUpdate': FieldValue.delete(),
      });
      debugPrint('Firestore save success');

      if (requestedRole == 'passenger') {
        debugPrint('Saving user to Firestore');
        await FirebaseFirestore.instance.collection('passengers').doc(uid).set({
          'passengerId': uid,
          'fullName': [
            firstName,
            lastName,
          ].where((part) => part.trim().isNotEmpty).join(' '),
          'phoneNumber': phoneNumber,
          'latitude': null,
          'longitude': null,
          'lastLocationUpdate': null,
        }, SetOptions(merge: true));
        debugPrint('Firestore save success');

        await _capturePassengerLoginLocation();

        if (!mounted) return;
        _pushReplacement(const PassengerHomeScreen());
        return;
      }

      if (requestedRole == 'driver') {
        await _handleDriverFlow(
          uid: uid,
          firstName: firstName,
          lastName: lastName,
        );
        return;
      }

      debugPrint('Reading user role');
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final role = _normalizeRole(userDoc.data()?['role']?.toString());

      if (!mounted) return;

      if (role == 'passenger') {
        await _capturePassengerLoginLocation();
        if (!mounted) return;
        _pushReplacement(const PassengerHomeScreen());
      } else if (role == 'driver') {
        final driverDoc = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(uid)
            .get();

        final bool isApproved = driverDoc.data()?['isApproved'] == true;
        await LocalStorageService.saveDriverStatus(
          DriverStatus.normalize(driverDoc.data()?['status']?.toString()),
        );

        if (!mounted) return;

        if (isApproved) {
          _pushReplacement(const DriverHomeScreen());
        } else {
          _pushReplacement(const SignupApprovalScreen());
        }
      } else {
        AppMessage.showError(context, texts.t('userRoleNotFound'));
      }
    } on FirebaseAuthException catch (e) {
      PhoneAuthHelpers.logFirebaseAuthException('OTP sign-in exception', e);
      debugPrint('OTP flow error: $e');
      final message = PhoneAuthHelpers.userMessageForFirebaseAuthException(
        e,
        fallback: texts.t('verificationFailed'),
      );

      if (!mounted) return;
      AppMessage.showError(context, message);
    } catch (e) {
      debugPrint('OTP flow error: $e');
      if (!mounted) return;
      AppMessage.showError(context, '${texts.t('errorLabel')}: $e');
    } finally {
      if (mounted && !_navigatedAway) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _continueAfterDemoTestVerification() async {
    if (!mounted) return;

    final phoneNumber = widget.phoneNumber.trim();
    debugPrint('Demo/test OTP continue platform: $defaultTargetPlatform');
    debugPrint('Demo/test OTP continue phone: $phoneNumber');

    setState(() => _isLoading = true);

    try {
      debugPrint('OTP verification started');
      final demoUser = await _signInDemoFirebaseUser(phoneNumber);
      debugPrint('OTP verification success');
      final sessionUid = demoUser.uid;
      debugPrint('Demo/test OTP session uid: $sessionUid');

      if (phoneNumber.isEmpty) {
        throw Exception('Phone number is missing.');
      }

      final users = FirebaseFirestore.instance.collection('users');
      var userQuery = await users
          .where('phone', isEqualTo: phoneNumber)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        userQuery = await users
            .where('phoneNumber', isEqualTo: phoneNumber)
            .limit(1)
            .get();
      }

      final existingUserDoc = userQuery.docs.isEmpty
          ? null
          : userQuery.docs.first;
      final existingUserData = existingUserDoc?.data() ?? {};
      final existingUid = existingUserDoc == null
          ? ''
          : (_stringValue(existingUserData['userId']).isNotEmpty
                ? _stringValue(existingUserData['userId'])
                : existingUserDoc.id);

      debugPrint('Reading user role');
      final widgetRole = _normalizeRole(widget.role);
      final role = widgetRole.isNotEmpty
          ? widgetRole
          : _normalizeRole(existingUserData['role']?.toString());

      if (role.isEmpty) {
        debugPrint('OTP flow error: User role not found');
        if (!mounted) return;
        _showOtpError(context.texts.t('userRoleNotFound'));
        return;
      }

      final nameParts = _namePartsFromWidget();
      final firstName = nameParts.firstName.isNotEmpty
          ? nameParts.firstName
          : _stringValue(existingUserData['firstName']);
      final lastName = nameParts.lastName.isNotEmpty
          ? nameParts.lastName
          : _stringValue(existingUserData['lastName']);

      final userData = <String, dynamic>{
        'userId': sessionUid,
        'phone': phoneNumber,
        'isVerified': true,
        'isOnline': false,
        'role': role,
      };

      if (firstName.isNotEmpty) {
        userData['firstName'] = firstName;
      }

      if (lastName.isNotEmpty) {
        userData['lastName'] = lastName;
      }

      debugPrint('Saving user to Firestore');
      await users.doc(sessionUid).set(userData, SetOptions(merge: true));
      debugPrint('Firestore save success');

      if (role == 'passenger') {
        debugPrint('Saving user to Firestore');
        await FirebaseFirestore.instance
            .collection('passengers')
            .doc(sessionUid)
            .set({
              'passengerId': sessionUid,
              'fullName': [
                firstName,
                lastName,
              ].where((part) => part.trim().isNotEmpty).join(' '),
              'phoneNumber': phoneNumber,
              'latitude': null,
              'longitude': null,
              'lastLocationUpdate': null,
            }, SetOptions(merge: true));
        debugPrint('Firestore save success');

        if (!mounted) return;
        _pushReplacement(const PassengerHomeScreen());
        return;
      }

      if (role == 'driver') {
        if (widgetRole == 'driver' && widget.driverData != null) {
          await _handleDriverFlow(
            uid: sessionUid,
            firstName: firstName,
            lastName: lastName,
          );
          return;
        }

        final drivers = FirebaseFirestore.instance.collection('drivers');
        DocumentSnapshot<Map<String, dynamic>>? driverDoc;

        if (existingUid.isNotEmpty) {
          final byExistingUid = await drivers.doc(existingUid).get();
          if (byExistingUid.exists) driverDoc = byExistingUid;
        }

        if (driverDoc == null && existingUid.isNotEmpty) {
          final driverQuery = await drivers
              .where('userId', isEqualTo: existingUid)
              .limit(1)
              .get();
          if (driverQuery.docs.isNotEmpty) {
            driverDoc = driverQuery.docs.first;
          }
        }

        if (driverDoc == null) {
          final byPhone = await drivers
              .where('phone', isEqualTo: phoneNumber)
              .limit(1)
              .get();
          if (byPhone.docs.isNotEmpty) {
            driverDoc = byPhone.docs.first;
          }
        }

        final driverData = driverDoc?.data() ?? {};
        debugPrint('Saving user to Firestore');
        await drivers.doc(sessionUid).set({
          ...driverData,
          'userId': sessionUid,
          'firstName': firstName,
          'lastName': lastName,
          'phone': phoneNumber,
          'role': 'driver',
          'isVerified': true,
          'isOnline': driverData['isOnline'] == true,
          'status': DriverStatus.normalize(driverData['status']?.toString()),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('Firestore save success');

        final displayName = '$firstName $lastName'.trim();
        if (displayName.isNotEmpty) {
          await LocalStorageService.saveDriverDisplayName(displayName);
        }
        await LocalStorageService.saveDriverStatus(
          DriverStatus.normalize(driverData['status']?.toString()),
        );

        if (!mounted) return;

        final isApproved = driverData['isApproved'] == true;
        _pushReplacement(
          isApproved ? const DriverHomeScreen() : const SignupApprovalScreen(),
        );
        return;
      }

      throw Exception('Demo user role was not found.');
    } on FirebaseAuthException catch (e) {
      PhoneAuthHelpers.logFirebaseAuthException(
        'Demo/test OTP demo Firebase session failed',
        e,
      );
      debugPrint('OTP flow error: $e');
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      _showOtpError(
        'Could not start the iOS demo session. Enable Email/Password sign-in in Firebase Authentication, then try again.',
      );
    } catch (e) {
      debugPrint('OTP flow error: $e');
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      _showOtpError('${context.texts.t('errorLabel')}: $e');
    } finally {
      if (mounted && !_navigatedAway) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _continueDemoTestOtp(String otp) async {
    if (!mounted) return;

    final phoneNumber = widget.phoneNumber.trim();
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final expectedOtp = firebaseTestOtpCodes[phoneNumber];

    debugPrint('Demo/test OTP platform: $defaultTargetPlatform');
    debugPrint('Demo/test OTP entered phone number: $phoneNumber');
    debugPrint('Demo/test OTP is Firebase test number: ${expectedOtp != null}');

    if (!isIos) {
      debugPrint('Demo/test OTP failed: platform is not iOS');
      _showOtpError('Demo OTP mode is only available on iOS.');
      return;
    }

    if (expectedOtp == null) {
      debugPrint('Demo/test OTP failed: phone missing from test map');
      _showOtpError(
        'This phone number is not configured as a Firebase test number.',
      );
      return;
    }

    if (otp != expectedOtp) {
      debugPrint('Demo/test OTP failed: code did not match');
      _showOtpError(context.texts.t('otpIncorrect'));
      return;
    }

    debugPrint('Demo/test OTP matched');
    await _continueAfterDemoTestVerification();
  }

  Future<void> _onContinue() async {
    final texts = context.texts;
    final otp = _otpControllers.map((e) => e.text).join().trim();

    if (otp.length != 6) {
      AppMessage.showError(context, texts.t('validSixDigitOtp'));
      return;
    }

    if (_isDemoTestMode) {
      try {
        await _continueDemoTestOtp(otp);
      } catch (e) {
        debugPrint('OTP flow error: $e');
        if (!mounted) return;
        AppMessage.showError(context, '${texts.t('errorLabel')}: $e');
      }
      return;
    }

    if (_verificationId.trim().isEmpty) {
      AppMessage.showError(context, texts.t('verificationIdMissing'));
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otp,
      );
      await _signInAndContinue(autoVerifiedCredential: credential, otp: otp);
    } on FirebaseAuthException catch (e) {
      PhoneAuthHelpers.logFirebaseAuthException('OTP continue exception', e);
      debugPrint('OTP flow error: $e');
      final message = PhoneAuthHelpers.userMessageForFirebaseAuthException(
        e,
        fallback: texts.t('verificationFailed'),
      );

      if (!mounted) return;
      AppMessage.showError(context, message);
    } catch (e) {
      debugPrint('OTP flow error: $e');
      if (!mounted) return;
      AppMessage.showError(context, '${texts.t('errorLabel')}: $e');
    } finally {
      if (mounted && !_navigatedAway) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendCode() async {
    if (_isLoading) return;

    if (_isDemoTestMode) {
      debugPrint('Demo/test OTP resend skipped');
      if (!mounted) return;
      _showOtpInfo(
        'Use the fixed OTP code configured for this Firebase test number.',
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final validationError = PhoneAuthHelpers.validateFullPhoneNumber(
        widget.phoneNumber,
      );
      if (validationError != null) {
        AppMessage.showError(context, validationError);
        setState(() => _isLoading = false);
        return;
      }

      debugPrint('OTP resend phoneNumber: ${widget.phoneNumber}');
      PhoneAuthHelpers.logPhoneAuthConfigurationReminder();

      final isIos = defaultTargetPlatform == TargetPlatform.iOS;
      final isFirebaseTestNumber = firebaseTestOtpCodes.containsKey(
        widget.phoneNumber.trim(),
      );
      debugPrint('OTP resend platform: $defaultTargetPlatform');
      debugPrint('OTP resend is Firebase test number: $isFirebaseTestNumber');

      if (isIos) {
        if (!mounted) return;
        setState(() => _isLoading = false);

        if (!isFirebaseTestNumber) {
          debugPrint(
            'OTP resend verifyPhoneNumber skipped: iOS non-test number',
          );
          AppMessage.showError(
            context,
            PhoneAuthHelpers.iosSideloadedOtpMessage,
          );
          return;
        }

        debugPrint(
          'OTP resend verifyPhoneNumber skipped: iOS Firebase test number',
        );
        setState(() {
          _isDemoTestMode = true;
          _verificationId = 'ios-demo-test';
          _resendToken = null;
        });
        AppMessage.showInfo(
          context,
          'Use the fixed OTP code configured for this Firebase test number.',
        );
        return;
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        forceResendingToken: _resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('OTP resend verificationCompleted');
          await _signInAndContinue(autoVerifiedCredential: credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('OTP ERROR CODE: ${e.code}');
          debugPrint('OTP ERROR MESSAGE: ${e.message}');
          debugPrint('OTP ERROR PLUGIN: ${e.plugin}');
          PhoneAuthHelpers.logFirebaseAuthException(
            'OTP resend verificationFailed',
            e,
          );
          if (!mounted) return;
          AppMessage.showError(
            context,
            PhoneAuthHelpers.userMessageForFirebaseAuthException(
              e,
              fallback: 'Failed to resend code. Please try again.',
            ),
          );
          setState(() => _isLoading = false);
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('OTP resend codeSent verificationId: $verificationId');
          debugPrint('OTP resend codeSent resendToken: $resendToken');
          if (!mounted) return;

          if (verificationId.trim().isEmpty) {
            setState(() => _isLoading = false);
            AppMessage.showError(
              context,
              context.texts.t('verificationIdMissing'),
            );
            return;
          }

          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _isLoading = false;
          });
          AppMessage.showInfo(context, context.texts.t('codeResent'));
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('OTP resend timeout verificationId: $verificationId');
          if (!mounted) return;
          setState(() => _isLoading = false);
        },
      );
    } on FirebaseAuthException catch (e) {
      PhoneAuthHelpers.logFirebaseAuthException('OTP resend threw', e);
      if (!mounted) return;
      AppMessage.showError(
        context,
        PhoneAuthHelpers.userMessageForFirebaseAuthException(
          e,
          fallback: 'Failed to resend code. Please try again.',
        ),
      );
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('OTP resend error: $e');
      if (!mounted) return;
      AppMessage.showError(context, '${context.texts.t('errorLabel')}: $e');
      setState(() => _isLoading = false);
    }
  }

  Widget _buildOtpTextField(int index) {
    return SizedBox(
      height: 56,
      child: TextField(
        controller: _otpControllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        maxLength: 1,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(1),
        ],
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
              color: NavigoColors.primaryOrange.withValues(alpha: 0.3),
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
                          Text(
                            context.texts.t('verifyPhoneNumber'),
                            style: NavigoTextStyles.titleLarge,
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${context.texts.t('enterSixDigitCodeSentTo')} ',
                                textAlign: TextAlign.center,
                                style: NavigoTextStyles.bodySmall,
                              ),
                              Directionality(
                                textDirection: TextDirection.ltr,
                                child: Text(
                                  widget.phoneNumber,
                                  textAlign: TextAlign.center,
                                  style: NavigoTextStyles.bodySmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Row(
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
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${context.texts.t('didntReceiveSms')} ',
                                style: NavigoTextStyles.bodySmall,
                              ),
                              GestureDetector(
                                onTap: _resendCode,
                                child: Text(
                                  context.texts.t('resendCode'),
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
                                      children: [
                                        Text(
                                          context.texts.t('continue'),
                                          style: NavigoTextStyles.button,
                                        ),
                                        const SizedBox(width: 10),
                                        const Icon(Icons.arrow_forward),
                                      ],
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.texts.t('otpExpiresNote'),
                            style: NavigoTextStyles.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Text(
                              context.texts.t('changePhoneNumber'),
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
