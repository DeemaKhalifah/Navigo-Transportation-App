import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'drivers_api_service.dart';

/// Thin service that wraps the device GPS stream and publishes
/// location updates to the backend API via [DriversApiService].
///
/// Replaces the `_startGpsPublishing()` logic previously in DriverHomeScreen.
class GpsPublisherService {
  final DriversApiService _driversApi = DriversApiService();

  StreamSubscription<Position>? _positionSub;
  bool _isPublishing = false;

  bool get isPublishing => _isPublishing;

  /// Start publishing GPS updates to the backend.
  /// [intervalMs] controls the minimum distance between updates (in meters).
  void start({int distanceFilter = 10}) {
    if (_isPublishing) return;
    _isPublishing = true;

    _positionSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
      ),
    ).listen(
      (Position position) async {
        try {
          await _driversApi.updateLocation(
            position.latitude,
            position.longitude,
          );
        } catch (e) {
          debugPrint('GPS publish error: $e');
        }
      },
      onError: (e) {
        debugPrint('GPS stream error: $e');
      },
    );
  }

  /// Stop publishing GPS updates.
  void stop() {
    _positionSub?.cancel();
    _positionSub = null;
    _isPublishing = false;
  }

  /// Check and request location permissions.
  /// Returns true if permissions are granted.
  static Future<bool> ensurePermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  void dispose() {
    stop();
    _driversApi.dispose();
  }
}
