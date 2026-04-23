import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/user_api_service.dart';

class ManagerProfileController extends ChangeNotifier {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  final ImagePicker _picker = ImagePicker();
  final UserApiService _userApi = UserApiService();

  File? image;

  bool isEditing = false;
  bool isLoading = true;
  bool isSaving = false;

  String? errorMessage;

  User? get currentUser => FirebaseAuth.instance.currentUser;

  Future<void> init() async {
    await loadProfile();
  }

  Future<void> loadProfile() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final user = currentUser;

      if (user == null) {
        errorMessage = 'No logged in user';
        return;
      }

      emailController.text = user.email ?? '';

      final data = await _userApi.getProfile();

      if (data != null) {
        final firstName = (data['firstName'] ?? '').toString().trim();
        final lastName = (data['lastName'] ?? '').toString().trim();
        final fullName = '$firstName $lastName'.trim();

        nameController.text = fullName.isNotEmpty ? fullName : 'Route Manager';
        emailController.text = (data['email'] ?? user.email ?? '')
            .toString()
            .trim();
      }
    } catch (e) {
      errorMessage = 'Failed to load profile';
      debugPrint('Manager profile error: $e');
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

  Future<String?> saveProfile() async {
    final user = currentUser;
    if (user == null) return 'No logged in user';

    isSaving = true;
    notifyListeners();

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

      if (!success) return 'Failed to update profile';

      isEditing = false;
      return null;
    } catch (e) {
      return 'Failed to update profile: $e';
    } finally {
      isSaving = false;
      notifyListeners();
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
    return const AssetImage('assets/images/logo.png');
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    super.dispose();
  }
}
