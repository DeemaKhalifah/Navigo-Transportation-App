import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/driver_status.dart';
import '../services/driver_queue_repository.dart';
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

  Future<void> init() async {
    currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      isLoading = false;
      notifyListeners();
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

    final directSnap = await driverDocRef!.get();
    if (!directSnap.exists) {
      final q = await FirebaseFirestore.instance
          .collection('drivers')
          .where('userId', isEqualTo: currentUser!.uid)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        driverDocRef = q.docs.first.reference;
      }
    }

    _driverDocSub = driverDocRef!.snapshots().listen((snap) {
      if (!snap.exists) return;

      final data = snap.data() ?? {};

      driverStatus = DriverStatus.normalize(
        data['status']?.toString() ?? DriverStatus.offline,
      );

      assignedRouteId = data['routeId']?.toString();

      notifyListeners();
    });

    await loadUserData();
  }

  Future<void> loadUserData() async {
    if (currentUser == null || userDocRef == null || driverDocRef == null) {
      isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final userSnap = await userDocRef!.get();

      if (userSnap.exists) {
        final data = userSnap.data() ?? {};

        final firstName = (data['firstName'] ?? '').toString();
        final lastName = (data['lastName'] ?? '').toString();

        nameController.text = '$firstName $lastName'.trim();
        phoneController.text = (data['phone'] ?? '').toString();
        imageUrl = data['image']?.toString();
        _resolvedImageUrl = await _profileImageStorageService.getImageUrl(
          imageUrl,
        );
      }

      final driverSnap = await driverDocRef!.get();

      if (driverSnap.exists) {
        final data = driverSnap.data() ?? {};

        driverStatus = DriverStatus.normalize(
          data['status']?.toString() ?? DriverStatus.offline,
        );

        assignedRouteId = data['routeId']?.toString();
      }
    } catch (e) {
      debugPrint('Error loading driver profile: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void toggleEdit() {
    isEditing = !isEditing;
    notifyListeners();
  }

  Future<void> pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 75);

    if (picked != null) {
      image = File(picked.path);
      notifyListeners();
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
    notifyListeners();

    try {
      final fullName = nameController.text.trim();
      final names = fullName.isEmpty
          ? <String>[]
          : fullName.split(RegExp(r'\s+'));

      final firstName = names.isNotEmpty ? names.first : '';
      final lastName = names.length > 1 ? names.sublist(1).join(' ') : '';

      final uploadedImageId = await _uploadProfileImageId();

      await userDocRef!.set({
        'firstName': firstName,
        'lastName': lastName,
        'phone': phoneController.text.trim(),
        'image': uploadedImageId,
        'role': 'driver',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await driverDocRef!.set({
        'firstName': firstName,
        'lastName': lastName,
        'phone': phoneController.text.trim(),
        'image': uploadedImageId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      imageUrl = uploadedImageId;
      _resolvedImageUrl = await _profileImageStorageService.getImageUrl(
        imageUrl,
      );
      isEditing = false;

      return null;
    } catch (e) {
      debugPrint('Save driver profile error: $e');
      return 'Failed to update profile: $e';
    } finally {
      isSaving = false;
      notifyListeners();
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
    notifyListeners();

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser!.uid);

    try {
      await driverDocRef!.set({
        'status': DriverStatus.available,
        'isOnline': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await userRef.set({
        'isOnline': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Queue stores `drivers/{docId}` ids (not auth uid), because drivers may
      // be saved under an auto-id document with `userId == uid`.
      await _queueRepo.onDriverStatusUpdated(
        routeId: routeId,
        driverId: driverDocRef!.id,
        status: DriverStatus.available,
      );

      driverStatus = DriverStatus.available;
      return null;
    } catch (e) {
      try {
        await driverDocRef!.set({
          'status': DriverStatus.offline,
          'isOnline': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await userRef.set({
          'isOnline': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}

      debugPrint('Go online error: $e');
      return 'Could not go online: $e';
    } finally {
      statusBusy = false;
      notifyListeners();
    }
  }

  Future<String?> goOffline() async {
    if (currentUser == null || blocksAvailabilityToggle) return null;
    if (driverDocRef == null) return 'Driver profile not found';

    final routeId = assignedRouteId?.trim();

    statusBusy = true;
    notifyListeners();

    try {
      await driverDocRef!.set({
        'status': DriverStatus.offline,
        'isOnline': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .set({
            'isOnline': false,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (routeId != null && routeId.isNotEmpty) {
        await _queueRepo.onDriverStatusUpdated(
          routeId: routeId,
          driverId: driverDocRef!.id,
          status: DriverStatus.offline,
        );
      }

      driverStatus = DriverStatus.offline;
      return null;
    } catch (e) {
      debugPrint('Go offline error: $e');
      return 'Could not go offline: $e';
    } finally {
      statusBusy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    final uid = currentUser?.uid;

    if (uid != null) {
      try {
        final ref =
            driverDocRef ??
            FirebaseFirestore.instance.collection('drivers').doc(uid);
        final driverSnap = await ref.get();

        final routeId = driverSnap.data()?['routeId']?.toString();

        if (routeId != null && routeId.isNotEmpty) {
          await _queueRepo.onDriverStatusUpdated(
            routeId: routeId,
            driverId: ref.id,
            status: DriverStatus.offline,
          );
        }

        await ref.set({
          'status': DriverStatus.offline,
          'isOnline': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'isOnline': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Logout driver cleanup error: $e');
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
    _driverDocSub?.cancel();
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }
}
