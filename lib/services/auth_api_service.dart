import 'api_client.dart';

/// API service for authentication endpoints.
/// Communicates with the Node.js backend for login, registration, and profile.
class AuthApiService {
  final ApiClient _client = ApiClient();

  /// Login with current Firebase token. Returns user data with role.
  Future<Map<String, dynamic>?> loginWithToken() async {
    try {
      final response = await _client.post('/auth/login');
      if (response['success'] == true) {
        return response['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Register a new passenger.
  Future<Map<String, dynamic>?> registerPassenger({
    required String fullName,
    required String phone,
  }) async {
    try {
      final response = await _client.post('/auth/register/passenger', body: {
        'fullName': fullName,
        'phone': phone,
      });
      if (response['success'] == true) {
        return response['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Register a new driver with vehicle data.
  Future<Map<String, dynamic>?> registerDriver({
    required String fullName,
    required String phone,
    required Map<String, dynamic> driverData,
  }) async {
    try {
      final response = await _client.post('/auth/register/driver', body: {
        'fullName': fullName,
        'phone': phone,
        ...driverData,
      });
      if (response['success'] == true) {
        return response['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get the current user's profile from the backend.
  Future<Map<String, dynamic>?> getProfile() async {
    try {
      final response = await _client.get('/auth/profile');
      if (response['success'] == true) {
        return response['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
