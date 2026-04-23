import 'api_client.dart';

/// Flutter API service for schedule/slot backend operations.
class ScheduleApiService {
  final ApiClient _api = ApiClient();

  /// Get all schedule slots for a route.
  Future<List<Map<String, dynamic>>> getSlots(String routeId) async {
    final response = await _api.get('/schedule/$routeId/slots');
    final data = response['data'];
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Add one or more schedule slots to a route.
  Future<List<Map<String, dynamic>>> addSlots(
    String routeId,
    List<Map<String, dynamic>> slots,
  ) async {
    final response = await _api.post('/schedule/$routeId/slots', body: {
      'slots': slots,
    });
    final data = response['data'];
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Update a specific schedule slot.
  Future<Map<String, dynamic>> updateSlot(
    String routeId,
    String slotId,
    Map<String, dynamic> updates,
  ) async {
    final response = await _api.put(
      '/schedule/$routeId/slots/$slotId',
      body: updates,
    );
    return response['data'] as Map<String, dynamic>;
  }

  /// Delete a specific schedule slot.
  Future<void> deleteSlot(String routeId, String slotId) async {
    await _api.delete('/schedule/$routeId/slots/$slotId');
  }

  /// Assign a driver to a slot.
  Future<Map<String, dynamic>> assignDriver(
    String routeId,
    String slotId,
    String driverId,
  ) async {
    final response = await _api.post(
      '/schedule/$routeId/slots/$slotId/assign',
      body: {'driverId': driverId},
    );
    return response['data'] as Map<String, dynamic>;
  }

  /// Get the driver queue for a route.
  Future<List<Map<String, dynamic>>> getQueue(String routeId) async {
    final response = await _api.get('/schedule/$routeId/queue');
    final data = response['data'];
    if (data is List) {
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  /// Queue all available drivers for a route.
  Future<void> queueAllDrivers(String routeId) async {
    await _api.post('/schedule/$routeId/queue/all');
  }

  /// Clear the driver queue.
  Future<void> clearQueue(String routeId) async {
    await _api.delete('/schedule/$routeId/queue');
  }

  /// Add a single driver to the queue.
  Future<void> addDriverToQueue(String routeId, String driverId) async {
    await _api.post('/schedule/$routeId/queue/$driverId');
  }

  /// Remove a single driver from the queue.
  Future<void> removeDriverFromQueue(String routeId, String driverId) async {
    await _api.delete('/schedule/$routeId/queue/$driverId');
  }

  /// Auto-assign next driver from queue to an unassigned slot.
  Future<Map<String, dynamic>> assignNextFromQueue(
    String routeId, {
    String? vehicleType,
  }) async {
    final response = await _api.post(
      '/schedule/$routeId/assign-next',
      body: vehicleType != null ? {'vehicleType': vehicleType} : {},
    );
    return response['data'] as Map<String, dynamic>;
  }

  void dispose() => _api.dispose();
}
