import 'api_client.dart';

/// API service for trip-related endpoints.
class TripsApiService {
  final ApiClient _client = ApiClient();

  /// Request a trip (passenger → driver).
  Future<Map<String, dynamic>?> requestTrip({
    required String driverId,
    required String routeId,
    required String scheduleId,
    required int seatsRequested,
    required String lineLabel,
    required String startPoint,
    required String endPoint,
    required String pickupDescription,
  }) async {
    try {
      final response = await _client.post('/trips/request', body: {
        'driverId': driverId,
        'routeId': routeId,
        'scheduleId': scheduleId,
        'seatsRequested': seatsRequested,
        'lineLabel': lineLabel,
        'startPoint': startPoint,
        'endPoint': endPoint,
        'pickupDescription': pickupDescription,
      });
      if (response['success'] == true) {
        return response['data'] as Map<String, dynamic>?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get trip history for the current user.
  Future<List<Map<String, dynamic>>> getTripHistory() async {
    try {
      final response = await _client.get('/trips/history');
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

  /// Cancel a trip by ID.
  Future<bool> cancelTrip(String tripId) async {
    try {
      final response = await _client.post('/trips/$tripId/cancel');
      return response['success'] == true;
    } catch (e) {
      return false;
    }
  }
}
