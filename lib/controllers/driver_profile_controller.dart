import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/driver_status.dart';
import '../services/driver_queue_repository.dart';

class DriverProfileController extends ChangeNotifier {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final DriverQueueRepository _queueRepo = DriverQueueRepository();

  File? image;
  String? imageUrl;

  bool isEditing = false;
  bool isLoading = true;
  bool isSaving = false;
  bool statusBusy = false;

  String driverStatus = DriverStatus.offline;
  String? assignedRouteId;

  User? currentUser;
  DocumentReference<Map<String, dynamic>>? userDocRef;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _driverDocSub;

  void init() {
    currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      isLoading = false;
      notifyListeners();
      return;
    }

    userDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser!.uid);

    _driverDocSub = FirebaseFirestore.instance
        .collection('drivers')
        .doc(currentUser!.uid)
        .snapshots()
        .listen((snap) {
          if (!snap.exists) return;

          final data = snap.data() ?? {};

          driverStatus = DriverStatus.normalize(
            data['status']?.toString() ?? DriverStatus.offline,
          );

          assignedRouteId = data['routeId']?.toString();

          notifyListeners();
        });

    loadUserData();
  }

  Future<void> loadUserData() async {
    if (currentUser == null || userDocRef == null) {
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
      }

      final driverSnap = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(currentUser!.uid)
          .get();

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

  Future<String?> _uploadProfileImage() async {
    if (image == null || currentUser == null) return imageUrl;

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('profile_images')
        .child('${currentUser!.uid}.jpg');

    await storageRef.putFile(image!);
    return storageRef.getDownloadURL();
  }

  Future<String?> saveProfile() async {
    if (currentUser == null || userDocRef == null) {
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

      final uploadedImageUrl = await _uploadProfileImage();

      await userDocRef!.set({
        'firstName': firstName,
        'lastName': lastName,
        'phone': phoneController.text.trim(),
        'image': uploadedImageUrl,
        'role': 'driver',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(currentUser!.uid)
          .set({
            'firstName': firstName,
            'lastName': lastName,
            'phone': phoneController.text.trim(),
            'image': uploadedImageUrl,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      imageUrl = uploadedImageUrl;
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

    final routeId = assignedRouteId?.trim();

    if (routeId == null || routeId.isEmpty) {
      return 'No route assigned. Update your driver profile in Firestore.';
    }

    statusBusy = true;
    notifyListeners();

    final driverRef = FirebaseFirestore.instance
        .collection('drivers')
        .doc(currentUser!.uid);

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser!.uid);

    try {
      await driverRef.set({
        'status': DriverStatus.available,
        'isOnline': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await userRef.set({
        'isOnline': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _queueRepo.joinQueue(routeId, currentUser!.uid);

      driverStatus = DriverStatus.available;
      return null;
    } catch (e) {
      try {
        await driverRef.set({
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

    final routeId = assignedRouteId?.trim();

    statusBusy = true;
    notifyListeners();

    try {
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(currentUser!.uid)
          .set({
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
        await _queueRepo.leaveQueue(routeId, currentUser!.uid);
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
        final driverSnap = await FirebaseFirestore.instance
            .collection('drivers')
            .doc(uid)
            .get();

        final routeId = driverSnap.data()?['routeId']?.toString();

        if (routeId != null && routeId.isNotEmpty) {
          await _queueRepo.leaveQueue(routeId, uid);
        }

        await FirebaseFirestore.instance.collection('drivers').doc(uid).set({
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

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return NetworkImage(imageUrl!);
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
