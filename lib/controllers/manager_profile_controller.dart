import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/profile_image_storage_service.dart';
import '../services/user_api_service.dart';

class ManagerProfileController extends ChangeNotifier {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final UserApiService _userApi = UserApiService();
  final ProfileImageStorageService _profileImageStorageService =
      ProfileImageStorageService();

  File? image;
  String? imageId;
  String? _resolvedImageUrl;

  bool isEditing = false;
  bool isLoading = true;
  bool isSaving = false;

  String? errorMessage;
  bool _disposed = false;

  User? get currentUser => FirebaseAuth.instance.currentUser;

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> init() async {
    if (_disposed) return;
    await loadProfile();
  }

  Future<void> loadProfile() async {
    if (_disposed) return;

    isLoading = true;
    errorMessage = null;
    _safeNotify();

    try {
      final user = currentUser;

      if (user == null) {
        errorMessage = 'No logged in user';
        return;
      }

      emailController.text = user.email ?? '';

      final data = await _userApi.getProfile();

      if (_disposed) return;

      if (data != null) {
        final firstName = (data['firstName'] ?? '').toString().trim();
        final lastName = (data['lastName'] ?? '').toString().trim();
        final fullName = '$firstName $lastName'.trim();

        nameController.text = fullName.isNotEmpty ? fullName : 'Route Manager';
        emailController.text = (data['email'] ?? user.email ?? '')
            .toString()
            .trim();
        imageId = data['image']?.toString();
        _resolvedImageUrl = await _profileImageStorageService.getImageUrl(
          imageId,
        );
      }
    } catch (e) {
      if (_disposed) return;
      errorMessage = 'Failed to load profile';
      debugPrint('Manager profile error: $e');
    } finally {
      if (!_disposed) {
        isLoading = false;
        _safeNotify();
      }
    }
  }

  void toggleEdit() {
    if (_disposed) return;
    isEditing = !isEditing;
    _safeNotify();
  }

  Future<void> pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 75);

      if (_disposed) return;

      if (picked != null) {
        image = File(picked.path);
        _safeNotify();
      }
    } catch (e) {
      debugPrint('Pick image error: $e');
    }
  }

  Future<String?> saveProfile() async {
    final user = currentUser;
    if (user == null) return 'No logged in user';

    if (_disposed) return 'Screen closed';

    isSaving = true;
    _safeNotify();

    try {
      final fullName = nameController.text.trim();
      final parts = fullName.isEmpty
          ? <String>[]
          : fullName.split(RegExp(r'\s+'));

      final firstName = parts.isNotEmpty ? parts.first : '';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      final success = await _userApi.updateProfile(
        firstName: firstName,
        lastName: lastName,
        phone: '',
      );

      if (_disposed) return null;

      if (!success) return 'Failed to update profile';

      String? uploadedImageId = imageId;
      if (image != null) {
        uploadedImageId = await _profileImageStorageService.uploadProfileImage(
          file: image!,
        );

        if (_disposed) return null;

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'image': uploadedImageId,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (_disposed) return null;

        imageId = uploadedImageId;
        _resolvedImageUrl = await _profileImageStorageService.getImageUrl(
          imageId,
        );
      }

      isEditing = false;
      return null;
    } catch (e) {
      return 'Failed to update profile: $e';
    } finally {
      if (!_disposed) {
        isSaving = false;
        _safeNotify();
      }
    }
  }

  Future<String?> changePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.email == null) {
      return 'No logged in user found';
    }

    final oldPass = currentPassword.trim();
    final newPass = newPassword.trim();
    final confirmPass = confirmPassword.trim();

    if (oldPass.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
      return 'Please fill in all fields';
    }

    if (newPass.length < 6) {
      return 'New password must be at least 6 characters';
    }

    if (newPass != confirmPass) {
      return 'New passwords do not match';
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: oldPass,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPass);

      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return 'Current password is incorrect';
      }

      if (e.code == 'weak-password') {
        return 'New password is too weak';
      }

      if (e.code == 'requires-recent-login') {
        return 'Please login again then change password.';
      }

      return e.message ?? 'Failed to change password';
    } catch (e) {
      return 'Failed to change password: $e';
    }
  }

  Future<void> logout() async {
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
    _disposed = true;
    nameController.dispose();
    emailController.dispose();
    super.dispose();
  }
}
