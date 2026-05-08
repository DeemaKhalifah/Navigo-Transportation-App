import 'package:flutter/material.dart';

import '../services/schedule_api_service.dart';
import '../services/slot_driver_assignment_service.dart';

class AddScheduleSlotController extends ChangeNotifier {
  final ScheduleApiService _scheduleApi = ScheduleApiService();
  final SlotDriverAssignmentService _slotAssign = SlotDriverAssignmentService();

  bool isSaving = false;

  Future<String?> saveSlots({
    required String routeId,
    required List<Map<String, dynamic>> slots,
  }) async {
    if (slots.isEmpty) return 'No slots to add';

    isSaving = true;
    notifyListeners();

    try {
      await _scheduleApi.addSlots(routeId, slots);

      await _slotAssign.autoAssignUpcomingUnassignedSlots(
        routeId: routeId,
      );

      isSaving = false;
      notifyListeners();
      return null;
    } catch (e) {
      isSaving = false;
      notifyListeners();
      return 'Failed to add slots: $e';
    }
  }

  List<Map<String, dynamic>> buildSlotsToCreate({
    required DateTime departureAt,
    required DateTime arrivalAt,
    required int capacity,
    required String vehicleType,
    String? driverId,
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