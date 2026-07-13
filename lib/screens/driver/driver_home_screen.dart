import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/schedule_slot.dart';
import '../../models/trip_status.dart';
import '../../models/driver_status.dart';
import '../../models/route.dart';
import '../../services/driver_live_trip_service.dart';
import '../../services/driver_trips_service.dart';
import '../../services/google_route_path_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/notification_service.dart';
import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_message.dart';
import '../../widgets/responsive.dart';
import 'driver_bottom_nav_bar.dart';
import 'package:navigo/screens/notifications_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key, this.initialActiveSlot});

  final ScheduleSlot? initialActiveSlot;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  // ── Map ─────────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  LatLng _currentPosition = const LatLng(31.7683, 35.2137);
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  bool _isDisposed = false;

  // ── Driver info ──────────────────────────────────────────────────────────────
  String _driverName = 'Driver';
  int _assignedTripsCount = 0;
  int _passengersOnMap = 0;
  String _driverStatus = DriverStatus.offline;
  DocumentReference<Map<String, dynamic>>? _driverDocRef;

  // ── Services ─────────────────────────────────────────────────────────────────
  final DriverTripsService _tripsService = DriverTripsService();
  final DriverLiveTripService _liveService = DriverLiveTripService();
  final NotificationService _notificationService = NotificationService();

  // ── Subscriptions ────────────────────────────────────────────────────────────
  StreamSubscription? _tripsSub;
  StreamSubscription<Position>? _locationSub;
  StreamSubscription? _liveDataSub;
  StreamSubscription? _driverDocSub;
  StreamSubscription? _passengersSub;

  // ── Live trip state ──────────────────────────────────────────────────────────
  bool _isLocating = false;
  bool _isEndingTrip = false;
  ScheduleSlot? _activeSlot;
  String? _activeRouteId;
  String? _etaText;
  String? _tripLine;
  String _activeRoutePolyline = '';
  List<LatLng> _decodedTripPath = const [];
  String? _locationStreamDriverId;
  bool _liveTrackingStarted = false;
  bool _hasCenteredDriverLocation = false;
  DateTime? _lastDriverLocationPublishAt;
  LatLng? _lastDriverMarkerPosition;
  static const Duration _locationTimeout = Duration(seconds: 10);
  static const Duration _normalActionTimeout = Duration(seconds: 20);

  // ── Passenger pin data ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> _passengerPins = [];

  @override
  void initState() {
    super.initState();
    _primeStartedTrip();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposed) return;
      _loadSavedDriverStatus();
      _loadSavedDriverName();
      _loadDriverName();
      _watchDriverStatus();
      _watchTrips();

      final initialSlot = widget.initialActiveSlot;
      if (initialSlot != null) {
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          if (!mounted || _isDisposed || _liveTrackingStarted) return;
          _startLiveTracking(initialSlot);
        });
      } else {
        _getUserLocation();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _tripsSub?.cancel();
    _locationSub?.cancel();
    _liveDataSub?.cancel();
    _driverDocSub?.cancel();
    _passengersSub?.cancel();
    try {
      _mapController?.dispose();
    } catch (e) {
      if (kDebugMode) debugPrint('Driver map controller dispose error: $e');
    }
    super.dispose();
  }

  void _primeStartedTrip() {
    final slot = widget.initialActiveSlot;
    if (slot == null) return;

    _activeSlot = slot;
    _activeRouteId = slot.routeId;
    _tripLine = _routeLabelFromCachedTrip(slot);
    _assignedTripsCount = 1;
    _driverStatus = DriverStatus.onTrip;
  }

  String? _routeLabelFromCachedTrip(ScheduleSlot slot) {
    final label = _tripsService.lineOf(slot).trim();
    if (_isRouteEndpointLabel(label)) return label;
    return null;
  }

  String? _routeLabelFromRoute(RouteModel? route) {
    if (route == null) return null;
    final start = route.startPoint.trim();
    final end = route.endPoint.trim();
    if (start.isEmpty || end.isEmpty) return null;
    return '$start ↔ $end';
  }

  bool _isRouteEndpointLabel(String label) {
    return label.contains('↔') || label.contains('→') || label.contains('->');
  }

  Future<void> _loadRouteLabel(String routeId) async {
    final safeRouteId = routeId.trim();
    if (safeRouteId.isEmpty) return;
    final sw = Stopwatch()..start();

    try {
      final snap = await FirebaseFirestore.instance
          .collection('route')
          .doc(safeRouteId)
          .get()
          .timeout(_normalActionTimeout);
      if (!mounted || _isDisposed || !snap.exists) return;
      final data = snap.data() ?? {};
      final routeMap = Map<String, dynamic>.from(data);
      routeMap['routeId'] = (routeMap['routeId'] ?? snap.id).toString();
      final label = _routeLabelFromRoute(RouteModel.fromMap(routeMap));
      if (label == null) return;
      setState(() => _tripLine = label);
    } catch (e) {
      if (kDebugMode) debugPrint('Driver route label load error: $e');
    } finally {
      sw.stop();
      if (kDebugMode) {
        debugPrint(
          '[PERF] driver route label load: ${sw.elapsedMilliseconds} ms',
        );
      }
    }
  }

  Future<void> _loadSavedDriverStatus() async {
    final status = await LocalStorageService.getDriverStatus();
    if (!mounted || _isDisposed || _activeSlot != null) return;
    setState(() => _driverStatus = status);
  }

  Future<void> _loadSavedDriverName() async {
    final name = await LocalStorageService.getDriverDisplayName();
    if (!mounted || _isDisposed || name == null) return;
    setState(() => _driverName = name);
  }

  Future<void> _watchDriverStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _driverDocRef = FirebaseFirestore.instance.collection('drivers').doc(uid);
    try {
      final direct = await _driverDocRef!.get().timeout(_normalActionTimeout);
      if (!direct.exists) {
        final q = await FirebaseFirestore.instance
            .collection('drivers')
            .where('userId', isEqualTo: uid)
            .limit(1)
            .get()
            .timeout(_normalActionTimeout);
        if (q.docs.isNotEmpty) {
          _driverDocRef = q.docs.first.reference;
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Driver status doc resolve error: $e');
    }

    _driverDocSub?.cancel();
    _driverDocSub = _driverDocRef?.snapshots().listen((snap) {
      if (!mounted || _isDisposed) return;
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      final status = DriverStatus.normalize(
        data['status']?.toString() ?? DriverStatus.offline,
      );
      unawaited(LocalStorageService.saveDriverStatus(status));
      setState(() {
        _driverStatus = status;
      });
    });
  }

  Future<void> _loadDriverName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final sw = Stopwatch()..start();
    try {
      final db = FirebaseFirestore.instance;
      final userDocFuture = db
          .collection('users')
          .doc(uid)
          .get()
          .timeout(_normalActionTimeout);
      final driverDocFuture = db
          .collection('drivers')
          .doc(uid)
          .get()
          .timeout(_normalActionTimeout);
      final userDoc = await userDocFuture;
      final driverDoc = await driverDocFuture;
      DocumentSnapshot<Map<String, dynamic>>? userIdDriverDoc;

      if (!driverDoc.exists) {
        final query = await db
            .collection('drivers')
            .where('userId', isEqualTo: uid)
            .limit(1)
            .get()
            .timeout(_normalActionTimeout);
        if (query.docs.isNotEmpty) {
          userIdDriverDoc = query.docs.first;
        }
      }

      final name = _displayNameFromMaps([
        userDoc.data(),
        driverDoc.data(),
        userIdDriverDoc?.data(),
        {
          'displayName': FirebaseAuth.instance.currentUser?.displayName,
          'phone': FirebaseAuth.instance.currentUser?.phoneNumber,
          'email': FirebaseAuth.instance.currentUser?.email,
        },
      ]);
      if (!mounted || _isDisposed) return;
      if (name.isNotEmpty) {
        await LocalStorageService.saveDriverDisplayName(name);
        if (!mounted || _isDisposed) return;
        setState(() => _driverName = name);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Driver name load error: $e');
    } finally {
      sw.stop();
      if (kDebugMode) {
        debugPrint(
          '[PERF] driver profile header load: ${sw.elapsedMilliseconds} ms',
        );
      }
    }
  }

  String _displayNameFromMaps(List<Map<String, dynamic>?> maps) {
    for (final data in maps) {
      if (data == null) continue;
      final direct =
          (data['fullName'] ??
                  data['name'] ??
                  data['displayName'] ??
                  data['driverName'] ??
                  '')
              .toString()
              .trim();
      if (direct.isNotEmpty) return direct;

      final first = (data['firstName'] ?? '').toString().trim();
      final last = (data['lastName'] ?? '').toString().trim();
      final full = '$first $last'.trim();
      if (full.isNotEmpty) return full;
    }

    return '';
  }

  void _watchTrips() {
    _tripsSub = _tripsService.watchDriverTrips().listen((trips) {
      if (!mounted || _isDisposed) return;

      final scheduled = trips
          .where((t) => _tripsService.statusOf(t) == TripStatus.scheduled)
          .length;
      final onTripSlots = trips
          .where((t) => _tripsService.statusOf(t) == TripStatus.onTrip)
          .toList();

      setState(() {
        _assignedTripsCount = scheduled + onTripSlots.length;
      });

      final newActive = onTripSlots.isNotEmpty ? onTripSlots.first : null;
      final newSlotId = newActive?.slotId;
      final oldSlotId = _activeSlot?.slotId;

      if (newSlotId != oldSlotId) {
        _stopLiveTracking();
        if (newActive != null) {
          _startLiveTracking(newActive);
        }
      } else if (newActive != null && !_liveTrackingStarted) {
        _startLiveTracking(newActive);
      }
    });
  }

  void _startLiveTracking(ScheduleSlot slot) {
    if (_isDisposed) return;
    if (_liveTrackingStarted && _activeSlot?.slotId == slot.slotId) return;

    final driverId =
        _driverDocRef?.id ?? FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null) return;

    _liveTrackingStarted = true;
    setState(() {
      _activeSlot = slot;
      _activeRouteId = slot.routeId;
      _tripLine = _routeLabelFromCachedTrip(slot);
    });

    if (_tripLine == null) {
      unawaited(_loadRouteLabel(slot.routeId));
    }

    _startGpsPublishing(driverId);

    _liveDataSub = _liveService
        .watchLiveTrip(routeId: slot.routeId, tripId: slot.slotId)
        .listen((data) {
          if (!mounted || _isDisposed || data == null) return;

          final startLat = _toDouble(data['startLat']);
          final startLng = _toDouble(data['startLng']);
          final endLat = _toDouble(data['endLat']);
          final endLng = _toDouble(data['endLng']);
          final routePolyline =
              (data['polyline'] ?? data['routePolyline'] ?? '').toString();
          final liveRoute = data['route'] is RouteModel
              ? data['route'] as RouteModel
              : null;
          final liveRouteLabel = _routeLabelFromRoute(liveRoute);
          if (routePolyline.trim().isNotEmpty &&
              routePolyline != _activeRoutePolyline) {
            _activeRoutePolyline = routePolyline;
            _decodedTripPath = GoogleRoutePathService.decodePolyline(
              routePolyline,
            );
          }
          final routePath = _decodedTripPath;

          final start = startLat != null && startLng != null
              ? LatLng(startLat, startLng)
              : null;
          final end = endLat != null && endLng != null
              ? LatLng(endLat, endLng)
              : null;
          final cleanedRoutePath = _dedupeConsecutivePoints(routePath);
          _debugRouteDraw(
            source: 'DriverHome',
            startMarker: start,
            endMarker: end,
            routeOrigin: start,
            routeDestination: end,
            decodedPoints: cleanedRoutePath,
          );

          if (mounted && !_isDisposed) {
            setState(() {
              if (liveRouteLabel != null) {
                _tripLine = liveRouteLabel;
              }
              _polylines.clear();
              _markers.removeWhere(
                (m) =>
                    m.markerId.value == 'route_start' ||
                    m.markerId.value == 'route_end',
              );

              // The active-trip path must be the decoded route only. A manual
              // [start, end] fallback draws a misleading straight segment.
              if (cleanedRoutePath.length >= 2) {
                _polylines.add(
                  Polyline(
                    polylineId: const PolylineId('trip_path'),
                    points: cleanedRoutePath,
                    width: 5,
                    color: NavigoColors.primaryOrange,
                  ),
                );
              }

              if (start != null) {
                _markers.add(
                  Marker(
                    markerId: const MarkerId('route_start'),
                    position: start,
                    infoWindow: const InfoWindow(title: 'Route start'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen,
                    ),
                  ),
                );
              }
              if (end != null) {
                _markers.add(
                  Marker(
                    markerId: const MarkerId('route_end'),
                    position: end,
                    infoWindow: const InfoWindow(title: 'Route end'),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed,
                    ),
                  ),
                );
              }
            });
          }

          final driverLoc = data['driverLocation'] as Map<String, double>?;
          final eta = _liveService.etaText(
            from: driverLoc,
            toLat: endLat,
            toLng: endLng,
          );
          if (mounted && !_isDisposed) {
            final etaChanged = _etaText != eta;
            if (etaChanged) {
              setState(() => _etaText = eta);
            }
          }
        });

    _passengersSub = _liveService
        .watchAssignedPassengerPins(slot.passengersIds)
        .listen((pins) {
          if (!mounted || _isDisposed) return;
          _passengerPins = pins;
          _rebuildPassengerMarkers();
        });
  }

  void _stopLiveTracking() {
    _liveTrackingStarted = false;
    _locationSub?.cancel();
    _locationSub = null;
    _locationStreamDriverId = null;
    _liveDataSub?.cancel();
    _liveDataSub = null;
    _passengersSub?.cancel();
    _passengersSub = null;
    _activeSlot = null;
    _activeRouteId = null;
    _tripLine = null;
    _etaText = null;
    _activeRoutePolyline = '';
    _decodedTripPath = const [];
    _passengerPins = [];
    _polylines.clear();
    _markers.removeWhere(
      (m) =>
          m.markerId.value.startsWith('passenger_') ||
          m.markerId.value == 'route_start' ||
          m.markerId.value == 'route_end',
    );
  }

  Future<bool> _ensureLocationPermission({bool showMessages = false}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (showMessages && mounted && !_isDisposed) {
        AppMessage.showError(
          context,
          context.texts.t('enableLocationServices'),
        );
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (showMessages && mounted && !_isDisposed) {
        AppMessage.showError(
          context,
          context.texts.t('locationPermissionDenied'),
        );
      }
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      if (showMessages && mounted && !_isDisposed) {
        AppMessage.showError(
          context,
          context.texts.t('enableLocationPermissionSettings'),
        );
        await Geolocator.openAppSettings();
      }
      return false;
    }

    return true;
  }

  Future<void> _startGpsPublishing(String driverId) async {
    if (_isLocating || _isDisposed) return;
    if (mounted) setState(() => _isLocating = true);
    final sw = Stopwatch()..start();

    try {
      final allowed = await _ensureLocationPermission();
      if (!allowed) return;

      final lastKnown = await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      if (lastKnown != null) {
        _updateDriverMarker(
          LatLng(lastKnown.latitude, lastKnown.longitude),
          animateCamera: false,
          force: true,
        );
      }

      final current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(_locationTimeout);

      await _liveService.updateDriverLocation(
        driverId: driverId,
        latitude: current.latitude,
        longitude: current.longitude,
      );

      _updateDriverMarker(
        LatLng(current.latitude, current.longitude),
        animateCamera: !_hasCenteredDriverLocation,
        force: true,
      );
      _hasCenteredDriverLocation = true;
      await _ensureDriverLocationStream(driverId);
    } on TimeoutException {
      if (kDebugMode) debugPrint('GPS publish timed out');
    } catch (e) {
      if (kDebugMode) debugPrint('GPS publish error: $e');
    } finally {
      sw.stop();
      if (kDebugMode) {
        debugPrint(
          '[PERF] driver GPS publish start: ${sw.elapsedMilliseconds} ms',
        );
      }
      if (mounted && !_isDisposed) setState(() => _isLocating = false);
    }
  }

  Future<void> _getUserLocation() async {
    if (_isLocating || _isDisposed) return;
    if (mounted) setState(() => _isLocating = true);
    final sw = Stopwatch()..start();

    try {
      final allowed = await _ensureLocationPermission(showMessages: true);
      if (!allowed) return;

      final lastKnown = await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      if (lastKnown != null) {
        _updateDriverMarker(
          LatLng(lastKnown.latitude, lastKnown.longitude),
          animateCamera: false,
          force: true,
        );
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(_locationTimeout);
      _updateDriverMarker(
        LatLng(pos.latitude, pos.longitude),
        animateCamera: true,
        force: true,
      );
      _hasCenteredDriverLocation = true;

      final driverId =
          _driverDocRef?.id ?? FirebaseAuth.instance.currentUser?.uid;
      if (driverId != null && driverId.trim().isNotEmpty) {
        await _liveService.updateDriverLocation(
          driverId: driverId,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );
        await _ensureDriverLocationStream(driverId);
      }
    } on TimeoutException {
      if (kDebugMode) debugPrint('Driver location request timed out');
      if (!mounted || _isDisposed) return;
      AppMessage.showError(context, context.texts.t('locationTimedOutRetry'));
    } catch (e) {
      if (kDebugMode) debugPrint('Location error: $e');
      if (!mounted || _isDisposed) return;
      AppMessage.showError(context, context.texts.t('errorGettingLocation'));
    } finally {
      sw.stop();
      if (kDebugMode) {
        debugPrint('[PERF] driver location load: ${sw.elapsedMilliseconds} ms');
      }
      if (mounted && !_isDisposed) setState(() => _isLocating = false);
    }
  }

  Future<void> _ensureDriverLocationStream(String driverId) async {
    final safeDriverId = driverId.trim();
    if (safeDriverId.isEmpty) return;
    if (_locationSub != null && _locationStreamDriverId == safeDriverId) {
      return;
    }
    await _locationSub?.cancel();
    _locationSub = null;
    _locationStreamDriverId = safeDriverId;
    debugPrint('[Geolocator] starting driver location stream');
    _locationSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 25,
          ),
        ).listen((pos) async {
          if (_isDisposed) return;
          final now = DateTime.now();
          final shouldPublish =
              _lastDriverLocationPublishAt == null ||
              now.difference(_lastDriverLocationPublishAt!) >
                  const Duration(seconds: 15);
          if (shouldPublish) {
            _lastDriverLocationPublishAt = now;
            await _liveService.updateDriverLocation(
              driverId: safeDriverId,
              latitude: pos.latitude,
              longitude: pos.longitude,
            );
          }
          _updateDriverMarker(
            LatLng(pos.latitude, pos.longitude),
            animateCamera: false,
            force: false,
          );
        });
  }

  void _updateDriverMarker(
    LatLng pos, {
    required bool animateCamera,
    bool force = false,
  }) {
    if (_isDisposed || !mounted) return;
    final previous = _lastDriverMarkerPosition;
    if (!force &&
        previous != null &&
        Geolocator.distanceBetween(
              previous.latitude,
              previous.longitude,
              pos.latitude,
              pos.longitude,
            ) <
            15) {
      return;
    }
    _lastDriverMarkerPosition = pos;
    setState(() {
      _currentPosition = pos;
      _markers.removeWhere((m) => m.markerId.value == 'driver_location');
      _markers.add(
        Marker(
          markerId: const MarkerId('driver_location'),
          position: pos,
          infoWindow: InfoWindow(title: _driverName, snippet: 'You'),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
        ),
      );
    });
    if (animateCamera) {
      _safeAnimateCamera(pos);
    }
  }

  void _rebuildPassengerMarkers() {
    if (_isDisposed || !mounted) return;

    _markers.removeWhere((m) => m.markerId.value.startsWith('passenger_'));

    int onMapCount = 0;
    for (final p in _passengerPins) {
      final lat = p['latitude'];
      final lng = p['longitude'];
      if (lat is num && lng is num) {
        onMapCount++;
        _markers.add(
          Marker(
            markerId: MarkerId('passenger_${p['userId']}'),
            position: LatLng(lat.toDouble(), lng.toDouble()),
            infoWindow: InfoWindow(
              title: (p['name'] ?? 'Passenger').toString(),
              snippet: 'Pickup: ${(p['pickup'] ?? '').toString()}',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueBlue,
            ),
          ),
        );
      }
    }

    setState(() => _passengersOnMap = onMapCount);
  }

  Future<void> _safeAnimateCamera(LatLng target) async {
    if (_isDisposed || !mounted) return;
    final c = _mapController;
    if (c == null) return;
    try {
      await c.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 14.5),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Driver map camera animate error: $e');
    }
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  List<LatLng> _dedupeConsecutivePoints(List<LatLng> points) {
    final cleaned = <LatLng>[];
    for (final point in points) {
      if (cleaned.isNotEmpty &&
          cleaned.last.latitude == point.latitude &&
          cleaned.last.longitude == point.longitude) {
        continue;
      }
      cleaned.add(point);
    }
    return cleaned;
  }

  void _debugRouteDraw({
    required String source,
    required LatLng? startMarker,
    required LatLng? endMarker,
    required LatLng? routeOrigin,
    required LatLng? routeDestination,
    required List<LatLng> decodedPoints,
  }) {
    if (!kDebugMode) return;
    debugPrint('[$source] start marker coordinates=${_fmt(startMarker)}');
    debugPrint('[$source] end marker coordinates=${_fmt(endMarker)}');
    debugPrint('[$source] route origin coordinates=${_fmt(routeOrigin)}');
    debugPrint(
      '[$source] route destination coordinates=${_fmt(routeDestination)}',
    );
    if (decodedPoints.isEmpty) {
      debugPrint('[$source] decoded polyline has no points');
      return;
    }
    debugPrint(
      '[$source] first decoded polyline point=${_fmt(decodedPoints.first)}',
    );
    debugPrint(
      '[$source] last decoded polyline point=${_fmt(decodedPoints.last)}',
    );
  }

  String _fmt(LatLng? point) {
    if (point == null) return 'null';
    return '${point.latitude.toStringAsFixed(7)},${point.longitude.toStringAsFixed(7)}';
  }

  Future<void> _endTrip() async {
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null || _activeSlot == null) return;

    setState(() => _isEndingTrip = true);

    try {
      _locationSub?.cancel();
      _locationSub = null;
      _locationStreamDriverId = null;

      await _liveService.completeTrip(
        routeId: _activeRouteId ?? '',
        tripId: _activeSlot!.slotId,
        driverId: driverId,
      );

      if (!mounted || _isDisposed) return;
      AppMessage.showSuccess(context, 'Trip ended successfully');

      _stopLiveTracking();
      await LocalStorageService.saveDriverStatus(DriverStatus.available);
      setState(() => _driverStatus = DriverStatus.available);
    } catch (e) {
      if (!mounted || _isDisposed) return;
      AppMessage.showError(context, 'Failed to end trip: $e');
    } finally {
      if (mounted && !_isDisposed) setState(() => _isEndingTrip = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    debugPrint('[Map] DriverHomeScreen build');
    final bool hasActiveTrip = _activeSlot != null;
    final bool isAvailable = _driverStatus == DriverStatus.available;
    final bool isOffline = _driverStatus == DriverStatus.offline;
    final bool isAssigned = _driverStatus == DriverStatus.assigned;

    final String statusLabel = isAvailable
        ? context.texts.t('available')
        : (isAssigned
              ? context.texts.t('assigned')
              : context.texts.t('offline'));
    final Color statusColor = isAvailable
        ? NavigoColors.accentGreen
        : (isAssigned ? NavigoColors.primaryOrange : NavigoColors.accentRed);
    final IconData statusIcon = isAvailable
        ? Icons.check_circle_outline
        : (isAssigned
              ? Icons.assignment_turned_in_outlined
              : Icons.cancel_outlined);
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final pagePadding = Responsive.horizontalPadding(context);
    final bottomCardMaxHeight = media.size.height * (isLandscape ? 0.58 : 0.48);

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const DriverBottomNavBar(currentIndex: 0),
      body: Stack(
        children: [
          // ── Full-screen map ──────────────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentPosition,
              zoom: 14,
            ),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (c) => _mapController = c,
          ),

          // ── Top header ───────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: pagePadding,
                vertical: Responsive.verticalGap(context, 10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Title + subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${context.texts.t('hello')}, $_driverName',
                          style: NavigoTextStyles.titleSmall,
                        ),
                        Text(
                          hasActiveTrip
                              ? context.texts.t('liveTripInProgress')
                              : context.texts.t('noActiveTrip'),
                          style: NavigoTextStyles.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  // Notification button — same style as PassengerHomeScreen
                  Container(
                    decoration: NavigoDecorations.kTopBarBackButton,
                    child: StreamBuilder<int>(
                      stream: _notificationService.watchUnreadCount(
                        FirebaseAuth.instance.currentUser?.uid ?? '',
                      ),
                      initialData: 0,
                      builder: (context, snapshot) {
                        final unreadCount = snapshot.data ?? 0;
                        return IconButton(
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.notifications_none, size: 20),
                              if (unreadCount > 0)
                                Positioned(
                                  right: -6,
                                  top: -6,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minWidth: 16,
                                      minHeight: 16,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: NavigoColors.accentRed,
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(999),
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      unreadCount > 99
                                          ? '99+'
                                          : unreadCount.toString(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationsScreen(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Avatar — radius 30, logo 40×40, matching PassengerHomeScreen
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: NavigoColors.surfaceWhite,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.contain,
                          width: 40,
                          height: 40,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── My location button ───────────────────────────────────────────────
          Positioned(
            // Keep the floating map control below the safe header and move it
            // closer in landscape so it does not collide with the bottom sheet.
            top: media.padding.top + (isLandscape ? 78 : 120),
            right: pagePadding,
            child: _isLocating
                ? const CircleAvatar(
                    radius: 18,
                    backgroundColor: NavigoColors.surfaceWhite,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FloatingActionButton.small(
                    heroTag: 'myLocBtn',
                    backgroundColor: NavigoColors.surfaceWhite,
                    onPressed: _getUserLocation,
                    child: const Icon(
                      Icons.my_location,
                      color: NavigoColors.primaryOrange,
                      size: 20,
                    ),
                  ),
          ),

          // ── Bottom info card ─────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: bottomCardMaxHeight),
              child: Container(
                decoration: BoxDecoration(
                  color: NavigoColors.surfaceWhite,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(isLandscape ? 20 : 28),
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 16),
                  ],
                ),
                padding: EdgeInsets.fromLTRB(
                  pagePadding,
                  Responsive.verticalGap(context, 12),
                  pagePadding,
                  math.max(media.padding.bottom, 16),
                ),
                child: SingleChildScrollView(
                  // The bottom trip card can contain stats and action buttons;
                  // constraining and scrolling it prevents landscape overflow
                  // while keeping the GoogleMap filling the background.
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      if (!hasActiveTrip) ...[
                        // ── No active trip ────────────────────────────────────────
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration:
                                  NavigoDecorations.iconCircleDecoration(
                                    statusColor,
                                  ),
                              child: Icon(
                                statusIcon,
                                color: statusColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isOffline
                                        ? context.texts.t('youAreOffline')
                                        : (isAssigned
                                              ? context.texts.t(
                                                  'youHaveAssignedTrip',
                                                )
                                              : context.texts.t(
                                                  'youAreAvailable',
                                                )),
                                    style: NavigoTextStyles.titleSmall.copyWith(
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${context.texts.t('assignedTrips')}: $_assignedTripsCount',
                                    style: NavigoTextStyles.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            NavigoDecorations.statusChip(
                              label: statusLabel,
                              color: statusColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // ── Active trip ───────────────────────────────────────────
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration:
                                  NavigoDecorations.iconCircleDecoration(
                                    NavigoColors.accentBlue,
                                  ),
                              child: const Icon(
                                Icons.directions_bus,
                                color: NavigoColors.accentBlue,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _tripLine ?? context.texts.t('activeTrip'),
                                    style: NavigoTextStyles.titleSmall.copyWith(
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  if (_etaText != null)
                                    Text(
                                      '${context.texts.t('eta')}: $_etaText',
                                      style: NavigoTextStyles.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            NavigoDecorations.statusChip(
                              label: context.texts.t('onTrip'),
                              color: NavigoColors.accentBlue,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),
                        Divider(
                          color: NavigoColors.primaryOrange.withOpacity(0.25),
                          height: 1,
                        ),
                        const SizedBox(height: 12),

                        // Passenger stats
                        Row(
                          children: [
                            _statChip(
                              icon: Icons.people,
                              label: context.texts.t('total'),
                              value: '${_activeSlot!.passengersIds.length}',
                              color: NavigoColors.primaryOrange,
                            ),
                            const SizedBox(width: 10),
                            _statChip(
                              icon: Icons.location_on,
                              label: context.texts.t('onMap'),
                              value: '$_passengersOnMap',
                              color: NavigoColors.accentBlue,
                            ),
                            const SizedBox(width: 10),
                            _statChip(
                              icon: Icons.event_seat,
                              label: context.texts.t('capacity'),
                              value: '${_activeSlot!.capacity}',
                              color: NavigoColors.accentGreen,
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // End trip button
                        SizedBox(
                          width: double.infinity,
                          height: NavigoSizes.buttonHeight,
                          child: ElevatedButton(
                            onPressed: _isEndingTrip ? null : _endTrip,
                            style: NavigoDecorations.kPrimaryButtonLargeStyle
                                .copyWith(
                                  backgroundColor: const WidgetStatePropertyAll(
                                    NavigoColors.accentRed,
                                  ),
                                ),
                            child: _isEndingTrip
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: NavigoColors.textLight,
                                    ),
                                  )
                                : Text(
                                    context.texts.t('endTrip'),
                                    style: NavigoTextStyles.button,
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }
}
