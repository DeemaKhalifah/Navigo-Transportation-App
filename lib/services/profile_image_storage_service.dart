import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

class ProfileImageStorageService {
  final FirebaseStorage _storage;

  ProfileImageStorageService({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  Future<String> uploadProfileImage({
    required String uid,
    required File file,
  }) async {
    final imageId = 'profile_images/$uid.jpg';
    final storageRef = _storage.ref().child(imageId);
    await storageRef.putFile(file);
    return imageId;
  }

  Future<String?> getImageUrl(String? imageValue) async {
    final value = imageValue?.trim() ?? '';
    if (value.isEmpty) return null;

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    return _storage.ref().child(value).getDownloadURL();
  }
}
