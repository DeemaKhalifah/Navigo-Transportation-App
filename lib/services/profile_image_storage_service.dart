import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ProfileImageUploadException implements Exception {
  const ProfileImageUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProfileImageStorageService {
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  ProfileImageStorageService({FirebaseStorage? storage, FirebaseAuth? auth})
    : _storage = storage ?? FirebaseStorage.instance,
      _auth = auth ?? FirebaseAuth.instance;

  Future<String> uploadProfileImage({required File file}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const ProfileImageUploadException(
        'Please sign in before uploading a profile image.',
      );
    }

    try {
      await user.getIdToken(true);
      final path = 'profile_images/${user.uid}/profile.jpg';
      final storageRef = _storage.ref().child(path);
      await storageRef.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return path;
    } on FirebaseException catch (error) {
      final code = error.code.toLowerCase();
      if (error.code == 'unauthorized') {
        throw ProfileImageUploadException(
          'Profile image upload was denied by Firebase Storage rules '
          '(${error.code}). Publish the profile_images/{uid}/profile.jpg rule.',
        );
      }
      if (code == 'unauthenticated') {
        throw const ProfileImageUploadException(
          'Your login session expired. Please log in again.',
        );
      }
      if (code == 'canceled') {
        throw const ProfileImageUploadException('Image upload was cancelled.');
      }
      if (code == 'bucket-not-found' || code == 'project-not-found') {
        throw ProfileImageUploadException(
          'Firebase Storage is not configured correctly (${error.code}).',
        );
      }
      if (code == 'quota-exceeded') {
        throw const ProfileImageUploadException(
          'Firebase Storage quota was exceeded.',
        );
      }
      throw ProfileImageUploadException(
        'Could not upload the profile image (${error.code}): '
        '${error.message ?? 'Unknown Firebase Storage error'}',
      );
    }
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
