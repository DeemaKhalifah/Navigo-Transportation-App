class ApiConfig {
  static const bool useBackend = false;

  static const String baseUrl = 'http://10.0.2.2:3000/api';

  static const int timeoutSeconds = 5;

  static Map<String, String> get defaultHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
}
