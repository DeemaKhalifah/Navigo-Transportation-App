import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'api_config.dart';

/// Lightweight HTTP client that wraps requests to the Node.js backend.
/// Automatically attaches Firebase ID token for authentication.
class ApiClient {
  final http.Client _client = http.Client();

  /// Get the current user's Firebase ID token for Authorization header.
  Future<Map<String, String>> _authHeaders() async {
    final headers = Map<String, String>.from(ApiConfig.defaultHeaders);
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final token = await user.getIdToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  /// Perform a GET request.
  Future<Map<String, dynamic>> get(String path,
      {Map<String, String>? queryParams}) async {
    final uri =
        Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: queryParams);
    final headers = await _authHeaders();

    final response = await _client
        .get(uri, headers: headers)
        .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

    return _handleResponse(response);
  }

  /// Perform a POST request.
  Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = await _authHeaders();

    final response = await _client
        .post(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
        .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

    return _handleResponse(response);
  }

  /// Perform a PUT request.
  Future<Map<String, dynamic>> put(String path,
      {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = await _authHeaders();

    final response = await _client
        .put(uri, headers: headers, body: body != null ? jsonEncode(body) : null)
        .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

    return _handleResponse(response);
  }

  /// Perform a DELETE request.
  Future<Map<String, dynamic>> delete(String path) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final headers = await _authHeaders();

    final response = await _client
        .delete(uri, headers: headers)
        .timeout(Duration(seconds: ApiConfig.timeoutSeconds));

    return _handleResponse(response);
  }

  /// Parse and validate the response.
  Map<String, dynamic> _handleResponse(http.Response response) {
    final Map<String, dynamic> body;

    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Invalid response format',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw ApiException(
      statusCode: response.statusCode,
      message: body['error']?.toString() ?? 'Request failed',
      code: body['code']?.toString(),
    );
  }

  void dispose() => _client.close();
}

/// Custom exception for API errors.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;

  ApiException({
    required this.statusCode,
    required this.message,
    this.code,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';
}
