import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/route.dart';
import '../models/schedule_slot.dart';
import '../services/schedule_api_service.dart';
import '../services/routes_api_service.dart';
import '../services/route_manager_route_id.dart' as rm_route;

/// Manages route schedule screen state and operations.
/// Slot CRUD and queue operations delegate to [ScheduleApiService].
/// Keeps a thin Firestore stream for real-time slot updates.
class RouteScheduleController extends ChangeNotifier {
  final ScheduleApiService _scheduleApi = ScheduleApiService();
  final RoutesApiService _routesApi = RoutesApiService();

  String? routeId;
  RouteModel? route;
  List<ScheduleSlot> slots = [];
  List<String> driverQueueIds = [];
  String selectedVehicleType = 'All';
  bool isLoading = true;
  bool isAssigning = false;

  StreamSubscription? _routeSub;

  /// Initialize with route context from the route_manager's assigned route.
  Future<void> loadRouteContext() async {
    isLoading = true;
    notifyListeners();

    try {
      // Get the route manager's assigned route ID
      routeId = await rm_route.resolveManagedRouteId();

      if (routeId != null && routeId!.isNotEmpty) {
        // Start listening for real-time route updates
        _routeSub = FirebaseFirestore.instance
            .collection('route')
            .doc(routeId)
            .snapshots()
            .listen((snap) {
          if (!snap.exists) return;
          final data = snap.data();
          if (data == null) return;

          route = RouteModel.fromMap(data);
          slots = route?.scheduleSlots ?? [];
          driverQueueIds =
              List<String>.from(data['driverQueueIds'] ?? []);
          notifyListeners();
        });
      }
    } catch (e) {
      debugPrint('Error loading route context: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  List<ScheduleSlot> get filteredSlots {
    if (selectedVehicleType == 'All') return slots;
    return slots
        .where(
            (s) => s.vehicleType.toLowerCase() == selectedVehicleType.toLowerCase())
        .toList();
  }

  void setVehicleTypeFilter(String type) {
    selectedVehicleType = type;
    notifyListeners();
  }

  /// Delete a slot via backend API.
  Future<String?> deleteSlot(String slotId) async {
    if (routeId == null) return 'No route loaded';
    try {
      await _scheduleApi.deleteSlot(routeId!, slotId);
      return null;
    } catch (e) {
      return 'Failed to delete slot: $e';
    }
  }

  /// Auto-assign next driver from queue via backend API.
  Future<String?> assignNextFromQueue({String? vehicleType}) async {
    if (routeId == null) return 'No route loaded';

    isAssigning = true;
    notifyListeners();

    try {
      await _scheduleApi.assignNextFromQueue(
        routeId!,
        vehicleType: vehicleType,
      );
      isAssigning = false;
      notifyListeners();
      return null;
    } catch (e) {
      isAssigning = false;
      notifyListeners();
      return 'Failed to assign: $e';
    }
  }

  @override
  void dispose() {
    _routeSub?.cancel();
    _scheduleApi.dispose();
    super.dispose();
  }
}
