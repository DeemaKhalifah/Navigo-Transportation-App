import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/local_storage_service.dart';
import '../services/profile_image_storage_service.dart';
import '../services/user_api_service.dart';

/// Manages passenger profile editing state and operations.
/// All data operations delegate to [UserApiService] → backend API.
class ProfileController extends ChangeNotifier {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final UserApiService _userApi = UserApiService();
  final ProfileImageStorageService _profileImageStorageService =
      ProfileImageStorageService();

  File? image;
  String? imageId;
  String? _resolvedImageUrl;
  bool isEditing = false;
  bool isSaving = false;
  bool isLoading = false;

  User? get currentUser => FirebaseAuth.instance.currentUser;

  void init() {
    if (currentUser != null) {
      loadUserData();
    }
  }

  Future<void> loadUserData() async {
    if (currentUser == null) return;
    isLoading = true;
    notifyListeners();

    try {
      final data = await _userApi.getProfile();
      if (data != null) {
        nameController.text =
            "${data['firstName'] ?? ''} ${data['lastName'] ?? ''}".trim();
        phoneController.text = data['phone'] ?? '';
        imageId = data['image']?.toString();
        _resolvedImageUrl = await _profileImageStorageService.getImageUrl(imageId);
      }
    } catch (e) {
      debugPrint("Error loading user data: $e");
    }

    isLoading = false;
    notifyListeners();
  }

  void toggleEdit() {
    isEditing = !isEditing;
    notifyListeners();
  }

  Future<void> pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked != null) {
      image = File(picked.path);
      notifyListeners();
    }
  }

  Future<String?> saveProfile() async {
    if (currentUser == null) return 'No user';

    isSaving = true;
    isEditing = false;
    notifyListeners();

    try {
      final names = nameController.text.trim().split(" ");
      final firstName = names.isNotEmpty ? names[0] : "";
      final lastName = names.length > 1 ? names.sublist(1).join(" ") : "";

      final success = await _userApi.updateProfile(
        firstName: firstName,
        lastName: lastName,
        phone: phoneController.text.trim(),
      );

      if (success && image != null) {
        final uploadedImageId = await _profileImageStorageService
            .uploadProfileImage(uid: currentUser!.uid, file: image!);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser!.uid)
            .set({
              'image': uploadedImageId,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
        imageId = uploadedImageId;
        _resolvedImageUrl = await _profileImageStorageService.getImageUrl(imageId);
      }

      isSaving = false;
      notifyListeners();
      return success ? null : 'Failed to update profile';
    } catch (e) {
      isSaving = false;
      notifyListeners();
      return "Failed to update profile: $e";
    }
  }

  Future<void> logout() async {
    await LocalStorageService.clearSelectedLine();
    await FirebaseAuth.instance.signOut();
  }

  ImageProvider get profileImageProvider {
    if (image != null) return FileImage(image!);
    if (_resolvedImageUrl != null && _resolvedImageUrl!.isNotEmpty) {
      return NetworkImage(_resolvedImageUrl!);
    }
    return const AssetImage("assets/images/logo.png");
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }
}
