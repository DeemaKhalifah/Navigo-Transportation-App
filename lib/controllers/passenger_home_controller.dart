import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/passenger_trip_repository.dart';
import '../services/local_storage_service.dart';
import '../services/trip_driver_request_service.dart';
import '../services/user_api_service.dart';
import '../services/routes_api_service.dart';

/// Manages passenger home screen business logic:
/// user data, line filtering, driver discovery, and trip requests.
///
/// All data operations delegate to API services.
/// No direct Firestore access.
class PassengerHomeController extends ChangeNotifier {
  final PassengerTripRepository _tripRepository = PassengerTripRepository();
  final TripDriverRequestService _tripRequestService =
      TripDriverRequestService();
  final UserApiService _userApi = UserApiService();
  final RoutesApiService _routesApi = RoutesApiService();

  String userName = "Loading...";
  String? selectedLine;
  String? selectedLocation;
  bool isLocating = false;
  bool isLoadingLines = false;

  List<String> lines = [];
  List<String> filteredLines = [];

  Future<void> loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        userName = "Guest";
        notifyListeners();
        return;
      }

      // Fetch user data from backend API
      final data = await _userApi.getProfile();
      if (data != null) {
        userName =
            "${data['firstName'] ?? ''} ${data['lastName'] ?? ''}".trim();
        if (userName.isEmpty) userName = "Guest";
      } else {
        userName = "Guest";
      }
      notifyListeners();
    } catch (e) {
      debugPrint("User load error: $e");
      userName = "Guest";
      notifyListeners();
    }
  }

  Future<void> loadLinesFromFirestore() async {
    isLoadingLines = true;
    notifyListeners();

    try {
      // Fetch routes from backend API
      final routes = await _routesApi.fetchRoutes();
      final linesList = routes
          .map((r) {
            final start = (r['startPoint'] ?? '').toString().trim();
            final end = (r['endPoint'] ?? '').toString().trim();
            if (start.isEmpty || end.isEmpty) return '';
            return '$start <-----> $end';
          })
          .where((line) => line.trim().isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      lines = linesList;
      filteredLines = List.from(linesList);
    } catch (e) {
      debugPrint("Routes load error: $e");
    } finally {
      isLoadingLines = false;
      notifyListeners();
    }
  }

  Future<void> loadSavedRoute() async {
    final savedLine = await LocalStorageService.getSelectedLine();
    if (savedLine != null) {
      selectedLine = savedLine;
      notifyListeners();
    }
  }

  void filterLines(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      filteredLines = List.from(lines);
    } else {
      filteredLines =
          lines.where((line) => line.toLowerCase().contains(trimmed)).toList();
    }
    notifyListeners();
  }

  void selectLine(String line) {
    selectedLine = line;
    LocalStorageService.saveSelectedLine(line);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> getDriversForDisplay() async {
    final hasLine = selectedLine != null && selectedLine!.trim().isNotEmpty;
    if (hasLine) {
      // Use backend API for driver discovery
      return await _routesApi.fetchDriversForLine(selectedLine!);
    } else {
      return await _routesApi.fetchDriversForLine('');
    }
  }

  Future<void> requestTrip({
    required String driverId,
    required String routeId,
    required String scheduleId,
    required int seatsRequested,
    required String lineLabel,
    required String startPoint,
    required String endPoint,
    required String pickupDescription,
  }) async {
    await _tripRequestService.createRequest(
      driverId: driverId,
      routeId: routeId,
      scheduleId: scheduleId,
      seatsRequested: seatsRequested,
      lineLabel: lineLabel,
      startPoint: startPoint,
      endPoint: endPoint,
      pickupDescription: pickupDescription,
    );
  }
}
