import 'package:flutter/material.dart';

import '../services/schedule_api_service.dart';

/// Manages add schedule slot screen state and operations.
/// Slot creation delegates to [ScheduleApiService].
class AddScheduleSlotController extends ChangeNotifier {
  final ScheduleApiService _scheduleApi = ScheduleApiService();

  bool isSaving = false;

  /// Create one or more slots via backend API.
  /// Returns error message or null on success.
  Future<String?> saveSlots({
    required String routeId,
    required List<Map<String, dynamic>> slots,
  }) async {
    if (slots.isEmpty) return 'No slots to add';

    isSaving = true;
    notifyListeners();

    try {
      await _scheduleApi.addSlots(routeId, slots);
      isSaving = false;
      notifyListeners();
      return null;
    } catch (e) {
      isSaving = false;
      notifyListeners();
      return 'Failed to add slots: $e';
    }
  }

  /// Build slot data maps from form input.
  List<Map<String, dynamic>> buildSlotsToCreate({
    required DateTime departureAt,
    required DateTime arrivalAt,
    required int capacity,
    required String vehicleType,
    required String driverId,
    int count = 1,
  }) {
    final slots = <Map<String, dynamic>>[];
    for (int i = 0; i < count; i++) {
      slots.add({
        'departureAt': departureAt.toIso8601String(),
        'arrivalAt': arrivalAt.toIso8601String(),
        'capacity': capacity,
        'vehicleType': vehicleType,
        'driverId': driverId,
        'status': 'scheduled',
      });
    }
    return slots;
  }

  @override
  void dispose() {
    _scheduleApi.dispose();
    super.dispose();
  }
}
