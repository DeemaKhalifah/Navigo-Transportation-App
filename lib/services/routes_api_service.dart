import 'api_client.dart';

/// API service for route-related endpoints.
class RoutesApiService {
  final ApiClient _client = ApiClient();

  /// Fetch all routes.
  Future<List<Map<String, dynamic>>> fetchRoutes() async {
    try {
      final response = await _client.get('/routes');
      if (response['success'] == true && response['data'] is List) {
        return List<Map<String, dynamic>>.from(
          (response['data'] as List).map((e) => Map<String, dynamic>.from(e)),
        );
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Fetch a single route by ID.
  Future<Map<String, dynamic>?> fetchRouteById(String routeId) async {
    try {
      final response = await _client.get('/routes/$routeId');
      if (response['success'] == true) {
        return response['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Fetch available drivers for a given line.
  Future<List<Map<String, dynamic>>> fetchDriversForLine(String line) async {
    try {
      final response = await _client.get('/routes/drivers', queryParams: {
        'line': line,
      });
      if (response['success'] == true && response['data'] is List) {
        return List<Map<String, dynamic>>.from(
          (response['data'] as List).map((e) => Map<String, dynamic>.from(e)),
        );
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
