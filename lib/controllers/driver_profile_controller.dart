import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_status.dart';
import '../services/driver_queue_repository.dart';
import '../services/local_storage_service.dart';
import '../services/profile_image_storage_service.dart';

class DriverProfileController extends ChangeNotifier {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final DriverQueueRepository _queueRepo = DriverQueueRepository();
  final ProfileImageStorageService _profileImageStorageService =
      ProfileImageStorageService();

  File? image;
  String? imageUrl;
  String? _resolvedImageUrl;

  bool isEditing = false;
  bool isLoading = true;
  bool isSaving = false;
  bool statusBusy = false;

  String driverStatus = DriverStatus.offline;
  String? assignedRouteId;

  User? currentUser;
  DocumentReference<Map<String, dynamic>>? userDocRef;
  DocumentReference<Map<String, dynamic>>? driverDocRef;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverDocSub;
  bool _isDisposed = false;
  static const Duration _firestoreTimeout = Duration(seconds: 20);

  void _notifyListeners() {
    if (_isDisposed) return;
    notifyListeners();
  }

  Future<void> init() async {
    currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      isLoading = false;
      _notifyListeners();
      return;
    }

    userDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser!.uid);

    // Drivers can be stored either as `drivers/{uid}` or as an auto-id document
    // with `userId == uid`. Resolve the correct driver doc reference once.
    driverDocRef = FirebaseFirestore.instance
        .collection('drivers')
        .doc(currentUser!.uid);

    try {
      final directSnap = await driverDocRef!.get().timeout(_firestoreTimeout);
      if (_isDisposed) return;
      if (!directSnap.exists) {
        final q = await FirebaseFirestore.instance
            .collection('drivers')
            .where('userId', isEqualTo: currentUser!.uid)
            .limit(1)
            .get()
            .timeout(_firestoreTimeout);
        if (_isDisposed) return;
        if (q.docs.isNotEmpty) {
          driverDocRef = q.docs.first.reference;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Driver profile doc resolve error: $e');
    }

    _driverDocSub = driverDocRef!.snapshots().listen((snap) {
      if (_isDisposed) return;
      if (!snap.exists) return;

      final data = snap.data() ?? {};

      driverStatus = DriverStatus.normalize(
        data['status']?.toString() ?? DriverStatus.offline,
      );
      unawaited(LocalStorageService.saveDriverStatus(driverStatus));

      assignedRouteId = data['routeId']?.toString();

      _notifyListeners();
    });

    await loadUserData();
  }

  String _fullNameFromData(Map<String, dynamic> data) {
    final direct =
        (data['fullName'] ??
                data['name'] ??
                data['displayName'] ??
                data['driverName'] ??
                '')
            .toString()
            .trim();
    if (direct.isNotEmpty) return direct;

    final firstName = (data['firstName'] ?? '').toString().trim();
    final lastName = (data['lastName'] ?? '').toString().trim();
    return '$firstName $lastName'.trim();
  }

  String _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return '';
  }

  Future<void> loadUserData() async {
    if (currentUser == null || userDocRef == null || driverDocRef == null) {
      isLoading = false;
      _notifyListeners();
      return;
    }

    final sw = Stopwatch()..start();
    try {
      final savedName = await LocalStorageService.getDriverDisplayName();
      if (_isDisposed) return;
      if (savedName != null && nameController.text.trim().isEmpty) {
        nameController.text = savedName;
      }

      final userSnapFuture = userDocRef!.get().timeout(_firestoreTimeout);
      final driverSnapFuture = driverDocRef!.get().timeout(_firestoreTimeout);

      final userSnap = await userSnapFuture;
      final driverSnap = await driverSnapFuture;
      if (_isDisposed) return;
      final userData = userSnap.data() ?? {};
      final driverData = driverSnap.data() ?? {};

      final resolvedName = _firstNonEmpty([
        _fullNameFromData(userData),
        _fullNameFromData(driverData),
        savedName,
        currentUser?.displayName,
      ]);
      if (resolvedName.isNotEmpty) {
        nameController.text = resolvedName;
        unawaited(LocalStorageService.saveDriverDisplayName(resolvedName));
      }

      final resolvedPhone = _firstNonEmpty([
        userData['phone'],
        userData['phoneNumber'],
        driverData['phone'],
        driverData['phoneNumber'],
        currentUser?.phoneNumber,
      ]);
      if (resolvedPhone.isNotEmpty) {
        phoneController.text = resolvedPhone;
      }

      imageUrl = _firstNonEmpty([
        userData['image'],
        userData['imageUrl'],
        driverData['image'],
        driverData['imageUrl'],
      ]);
      _resolvedImageUrl = await _profileImageStorageService.getImageUrl(
        imageUrl,
      );
      if (_isDisposed) return;

      if (driverSnap.exists) {
        driverStatus = DriverStatus.normalize(
          driverData['status']?.toString() ?? DriverStatus.offline,
        );
        unawaited(LocalStorageService.saveDriverStatus(driverStatus));

        assignedRouteId = driverData['routeId']?.toString();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error loading driver profile: $e');
    } finally {
      sw.stop();
      if (kDebugMode) {
        debugPrint('[PERF] driver profile load: ${sw.elapsedMilliseconds} ms');
      }
      if (_isDisposed) return;
      isLoading = false;
      _notifyListeners();
    }
  }

  void toggleEdit() {
    if (_isDisposed) return;
    isEditing = !isEditing;
    _notifyListeners();
  }

  Future<void> pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 75);
    if (_isDisposed) return;

    if (picked != null) {
      image = File(picked.path);
      _notifyListeners();
    }
  }

  Future<String?> _uploadProfileImageId() async {
    if (currentUser == null) return null;
    if (image == null) return imageUrl;
    return _profileImageStorageService.uploadProfileImage(file: image!);
  }

  Future<String?> saveProfile() async {
    if (currentUser == null || userDocRef == null || driverDocRef == null) {
      return 'No logged in user';
    }

    isSaving = true;
    _notifyListeners();

    try {
      final fullName = nameController.text.trim();
      final names = fullName.isEmpty
          ? <String>[]
          : fullName.split(RegExp(r'\s+'));

      final firstName = names.isNotEmpty ? names.first : '';
      final lastName = names.length > 1 ? names.sublist(1).join(' ') : '';

      final uploadedImageId = await _uploadProfileImageId();

      await Future.wait([
        userDocRef!
            .set({
              'firstName': firstName,
              'lastName': lastName,
              'phone': phoneController.text.trim(),
              'image': uploadedImageId,
              'role': 'driver',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(_firestoreTimeout),
        driverDocRef!
            .set({
              'firstName': firstName,
              'lastName': lastName,
              'phone': phoneController.text.trim(),
              'image': uploadedImageId,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(_firestoreTimeout),
      ]);

      imageUrl = uploadedImageId;
      _resolvedImageUrl = await _profileImageStorageService.getImageUrl(
        imageUrl,
      );
      if (_isDisposed) return null;
      isEditing = false;
      await LocalStorageService.saveDriverDisplayName(fullName);

      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Save driver profile error: $e');
      return 'Failed to update profile: $e';
    } finally {
      if (!_isDisposed) {
        isSaving = false;
        _notifyListeners();
      }
    }
  }

  bool get onLiveTrip => driverStatus == DriverStatus.onTrip;

  bool get assignedTrip => driverStatus == DriverStatus.assigned;

  bool get blocksAvailabilityToggle => onLiveTrip || assignedTrip;

  String get statusLabel {
    switch (driverStatus) {
      case DriverStatus.available:
        return 'Available';
      case DriverStatus.assigned:
        return 'Assigned (start trip when ready)';
      case DriverStatus.onTrip:
        return 'On trip';
      default:
        return 'Offline';
    }
  }

  Future<String?> goOnline() async {
    if (currentUser == null || blocksAvailabilityToggle) return null;
    if (driverDocRef == null) return 'Driver profile not found';

    final routeId = assignedRouteId?.trim();

    if (routeId == null || routeId.isEmpty) {
      return 'No route assigned. Update your driver profile in Firestore.';
    }

    statusBusy = true;
    _notifyListeners();

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser!.uid);

    try {
      await Future.wait([
        driverDocRef!
            .set({
              'status': DriverStatus.available,
              'isOnline': true,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(_firestoreTimeout),
        userRef
            .set({
              'isOnline': true,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(_firestoreTimeout),
      ]);

      // Queue stores `drivers/{docId}` ids (not auth uid), because drivers may
      // be saved under an auto-id document with `userId == uid`.
      await _queueRepo.onDriverStatusUpdated(
        routeId: routeId,
        driverId: driverDocRef!.id,
        status: DriverStatus.available,
      );

      driverStatus = DriverStatus.available;
      await LocalStorageService.saveDriverStatus(DriverStatus.available);
      return null;
    } catch (e) {
      try {
        await Future.wait([
          driverDocRef!
              .set({
                'status': DriverStatus.offline,
                'isOnline': false,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true))
              .timeout(_firestoreTimeout),
          userRef
              .set({
                'isOnline': false,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true))
              .timeout(_firestoreTimeout),
        ]);
      } catch (rollbackError) {
        if (kDebugMode) {
          debugPrint('Go online rollback error: $rollbackError');
        }
      }

      if (kDebugMode) debugPrint('Go online error: $e');
      return 'Could not go online: $e';
    } finally {
      if (!_isDisposed) {
        statusBusy = false;
        _notifyListeners();
      }
    }
  }

  Future<String?> goOffline() async {
    if (currentUser == null || blocksAvailabilityToggle) return null;
    if (driverDocRef == null) return 'Driver profile not found';

    final routeId = assignedRouteId?.trim();

    statusBusy = true;
    _notifyListeners();

    try {
      await Future.wait([
        driverDocRef!
            .set({
              'status': DriverStatus.offline,
              'isOnline': false,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(_firestoreTimeout),
        FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .set({
              'isOnline': false,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(_firestoreTimeout),
      ]);

      if (routeId != null && routeId.isNotEmpty) {
        await _queueRepo.onDriverStatusUpdated(
          routeId: routeId,
          driverId: driverDocRef!.id,
          status: DriverStatus.offline,
        );
      }

      driverStatus = DriverStatus.offline;
      await LocalStorageService.saveDriverStatus(DriverStatus.offline);
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Go offline error: $e');
      return 'Could not go offline: $e';
    } finally {
      if (!_isDisposed) {
        statusBusy = false;
        _notifyListeners();
      }
    }
  }

  Future<void> logout() async {
    final uid = currentUser?.uid;

    if (uid != null) {
      try {
        final ref =
            driverDocRef ??
            FirebaseFirestore.instance.collection('drivers').doc(uid);
        final driverSnap = await ref.get().timeout(_firestoreTimeout);

        final routeId = driverSnap.data()?['routeId']?.toString();

        if (routeId != null && routeId.isNotEmpty) {
          await _queueRepo.onDriverStatusUpdated(
            routeId: routeId,
            driverId: ref.id,
            status: DriverStatus.offline,
          );
        }

        await Future.wait([
          ref
              .set({
                'status': DriverStatus.offline,
                'isOnline': false,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true))
              .timeout(_firestoreTimeout),
          FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set({
                'isOnline': false,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true))
              .timeout(_firestoreTimeout),
        ]);

        await LocalStorageService.saveDriverStatus(DriverStatus.offline);
      } catch (e) {
        if (kDebugMode) debugPrint('Logout driver cleanup error: $e');
      }
    }

    await FirebaseAuth.instance.signOut();
  }

  ImageProvider get profileImageProvider {
    if (image != null) return FileImage(image!);

    if (_resolvedImageUrl != null && _resolvedImageUrl!.isNotEmpty) {
      return NetworkImage(_resolvedImageUrl!);
    }

    return const AssetImage('assets/images/logo.png');
  }

  @override
  void dispose() {
    _isDisposed = true;
    _driverDocSub?.cancel();
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }
}
