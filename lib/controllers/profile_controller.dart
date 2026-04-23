import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/local_storage_service.dart';

/// Manages profile editing state, data loading, saving, logout, and image picking.
/// Shared between passenger and driver profile screens.
class ProfileController extends ChangeNotifier {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  File? image;
  bool isEditing = false;
  bool isSaving = false;

  User? currentUser;
  DocumentReference? userDocRef;

  void init() {
    currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      userDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid);
      loadUserData();
    }
  }

  Future<void> loadUserData() async {
    if (userDocRef == null) return;
    try {
      DocumentSnapshot snapshot = await userDocRef!.get();
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        nameController.text =
            "${data['firstName'] ?? ''} ${data['lastName'] ?? ''}".trim();
        phoneController.text = data['phone'] ?? '';
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error loading user data: $e");
    }
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
    if (currentUser == null || userDocRef == null) return 'No user';

    isSaving = true;
    isEditing = false;
    notifyListeners();

    try {
      final names = nameController.text.trim().split(" ");
      final firstName = names.isNotEmpty ? names[0] : "";
      final lastName = names.length > 1 ? names.sublist(1).join(" ") : "";

      await userDocRef!.update({
        "firstName": firstName,
        "lastName": lastName,
        "phone": phoneController.text.trim(),
      });

      isSaving = false;
      notifyListeners();
      return null; // success
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
