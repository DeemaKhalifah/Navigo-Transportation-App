import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/local_storage_service.dart';
import '../services/user_api_service.dart';

/// Manages passenger profile editing state and operations.
/// All data operations delegate to [UserApiService] → backend API.
class ProfileController extends ChangeNotifier {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final UserApiService _userApi = UserApiService();

  File? image;
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

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }
}
