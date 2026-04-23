import 'package:flutter/material.dart';

import '../services/schedule_api_service.dart';
import '../services/routes_api_service.dart';

/// Manages the assign driver screen state and operations.
/// Driver listing and slot assignment delegate to API services.
class AssignDriverController extends ChangeNotifier {
  final ScheduleApiService _scheduleApi = ScheduleApiService();
  final RoutesApiService _routesApi = RoutesApiService();

  List<Map<String, dynamic>> drivers = [];
  bool isLoading = true;
  bool isAssigning = false;

  String? routeId;
  String? slotId;
  String filterQuery = '';

  /// Load available drivers for a route.
  Future<void> loadDrivers(String routeId) async {
    this.routeId = routeId;
    isLoading = true;
    notifyListeners();

    try {
      final queue = await _scheduleApi.getQueue(routeId);
      drivers = queue;
    } catch (e) {
      debugPrint('Error loading drivers: $e');
      drivers = [];
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> get filteredDrivers {
    if (filterQuery.isEmpty) return drivers;
    final q = filterQuery.toLowerCase();
    return drivers.where((d) {
      final name = (d['fullName'] ?? '').toString().toLowerCase();
      final plate = (d['plateNumber'] ?? '').toString().toLowerCase();
      return name.contains(q) || plate.contains(q);
    }).toList();
  }

  void setFilter(String query) {
    filterQuery = query;
    notifyListeners();
  }

  /// Assign a driver to a slot via backend API.
  Future<String?> assignToSlot(String driverId, String targetSlotId) async {
    if (routeId == null) return 'No route loaded';

    isAssigning = true;
    notifyListeners();

    try {
      await _scheduleApi.assignDriver(routeId!, targetSlotId, driverId);
      isAssigning = false;
      notifyListeners();
      return null;
    } catch (e) {
      isAssigning = false;
      notifyListeners();
      return 'Failed to assign driver: $e';
    }
  }

  @override
  void dispose() {
    _scheduleApi.dispose();
    super.dispose();
  }
}
