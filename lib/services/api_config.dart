/// Central configuration for the backend API connection.
class ApiConfig {
  /// Set to `true` to route requests through the Node.js backend.
  /// Set to `false` to keep using direct Firestore access (default).
  static const bool useBackend = false;

  /// Base URL for the backend API.
  /// Android emulator uses 10.0.2.2 to reach host machine's localhost.
  /// iOS simulator and web can use localhost directly.
  static const String baseUrl = 'http://10.0.2.2:3000/api';

  /// Timeout for HTTP requests in seconds.
  static const int timeoutSeconds = 30;

  /// Common headers for all API requests.
  static Map<String, String> get defaultHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
}
