import 'api_client.dart';

/// API service for user profile and settings endpoints.
class UserApiService {
  final ApiClient _client = ApiClient();

  /// Get the current user's profile.
  Future<Map<String, dynamic>?> getProfile() async {
    try {
      final response = await _client.get('/users/profile');
      if (response['success'] == true) {
        return response['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Update the current user's profile.
  Future<bool> updateProfile({
    required String firstName,
    required String lastName,
    required String phone,
  }) async {
    try {
      final response = await _client.put('/users/profile', body: {
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
      });
      return response['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Save user language preference to the backend.
  Future<bool> updateLanguagePreference(String languageCode) async {
    try {
      final response = await _client.put('/users/settings/language', body: {
        'language': languageCode,
      });
      return response['success'] == true;
    } catch (e) {
      return false;
    }
  }
}
