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
        imageId = data['image']?.toString().trim() ?? '';
        _resolvedImageUrl = await _profileImageStorageService.getImageUrl(
          imageId,
        );
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
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked != null) {
        image = File(picked.path);
        notifyListeners();
      }
    } catch (_) {
      throw const ProfileImageUploadException(
        'Could not select the image. Please try again.',
      );
    }
  }

  Future<String?> saveProfile() async {
    final user = currentUser;
    if (user == null) return 'No user';

    isSaving = true;
    notifyListeners();

    try {
      final fullName = nameController.text.trim();
      final names = fullName.isEmpty
          ? <String>[]
          : fullName.split(RegExp(r'\s+'));
      final firstName = names.isNotEmpty ? names[0] : "";
      final lastName = names.length > 1 ? names.sublist(1).join(" ") : "";
      final phone = phoneController.text.trim();

      String uploadedImageId = imageId?.trim() ?? '';
      if (image != null) {
        uploadedImageId = await _profileImageStorageService.uploadProfileImage(
          file: image!,
        );
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'image': uploadedImageId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      imageId = uploadedImageId;
      _resolvedImageUrl = await _profileImageStorageService.getImageUrl(
        imageId,
      );
      image = null;
      isEditing = false;

      // Preserve the existing API profile update without allowing an optional
      // backend failure to roll back a successful Storage/Firestore save.
      await _userApi.updateProfile(
        firstName: firstName,
        lastName: lastName,
        phone: phone,
      );
      return null;
    } on ProfileImageUploadException catch (error) {
      return error.message;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        return 'Firestore denied the profile update (${error.code}). '
            'Allow the signed-in user to update users/${user.uid}.';
      }
      return 'Could not update the profile (${error.code}): '
          '${error.message ?? 'Unknown Firebase error'}';
    } catch (error) {
      return 'Could not update the profile: $error';
    } finally {
      isSaving = false;
      notifyListeners();
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
