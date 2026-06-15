import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_message.dart';
import '../../widgets/responsive.dart';
import 'passenger_bottom_nav_bar.dart';
import '../notifications_screen.dart';
import 'schedule_screen.dart';
import '../../services/passenger_trip_repository.dart';
import '../../services/local_storage_service.dart';
import '../../services/trip_driver_request_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/notification_service.dart';
import '../../services/google_route_path_service.dart';
import '../../modules/route/route_path_info.dart';

class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({
    super.key,
    this.routeStartPoint,
    this.routeEndPoint,
    this.routeId,
    this.trackDriverId,
  });

  /// When provided, a polyline is drawn between these two points (View Route).
  final String? routeStartPoint;
  final String? routeEndPoint;
  final String? routeId;

  /// When provided, live-track this driver on the map.
  final String? trackDriverId;

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  GoogleMapController? _mapController;
  LatLng _initialPosition = const LatLng(31.7683, 35.2137);

  final TextEditingController _searchController = TextEditingController();

  String? _selectedLine;
  String? _selectedLocation;
  bool _isLocating = false;
  bool _isLoadingLines = false;

  final PassengerTripRepository _tripRepository = PassengerTripRepository();
  final TripDriverRequestService _tripRequestService =
      TripDriverRequestService();
  final NotificationService _notificationService = NotificationService();
  final GoogleRoutePathService _routePathService = GoogleRoutePathService();

  List<String> _lines = [];
  List<String> _filteredLines = [];
  bool _showLineSuggestions = false;

  String _userName = "Loading...";

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  BitmapDescriptor? _carIcon;

  int _selectedSeatsCount = 1;

  // ── Live tracking state ──────────────────────────────────────────────────
  StreamSubscription<DocumentSnapshot>? _liveDriverSub;
  StreamSubscription<Position>? _passengerLocationSub;
  bool _isLiveTracking = false;
  LatLng? _trackedDriverPosition;
  LatLng? _passengerTrackingPosition;
  String? _trackingEtaText;
  bool _manualPickupSelected = false;
  String? _activeRouteRenderKey;
  List<LatLng> _decodedRoutePoints = const [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadSavedRoute();
    _loadCarMarker();
    _loadLinesFromFirestore();
    _loadInitialPassengerLocation();
    unawaited(_startPassengerLocationPublishing());

    // Handle View Route if parameters are set
    if (widget.routeStartPoint != null && widget.routeEndPoint != null) {
      _drawRoutePolyline(
        widget.routeStartPoint!,
        widget.routeEndPoint!,
        routeId: widget.routeId,
      );
    }

    // Handle Track Live Trip if driverId is set
    if (widget.trackDriverId != null &&
        widget.trackDriverId!.trim().isNotEmpty) {
      _startLiveTracking(widget.trackDriverId!);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController?.dispose();
    _mapController = null;
    _liveDriverSub?.cancel();
    _liveDriverSub = null;
    _passengerLocationSub?.cancel();
    _passengerLocationSub = null;
    super.dispose();
  }

  // ── Draw Route Polyline ──────────────────────────────────────────────────
  Future<void> _drawRoutePolyline(
    String startPoint,
    String endPoint, {
    String? routeId,
    LatLng? startLocation,
    LatLng? endLocation,
  }) async {
    final renderKey =
        '${routeId?.trim() ?? ''}|$startPoint|$endPoint|${startLocation?.latitude ?? ''},${startLocation?.longitude ?? ''}|${endLocation?.latitude ?? ''},${endLocation?.longitude ?? ''}';
    if (_activeRouteRenderKey == renderKey && _decodedRoutePoints.isNotEmpty) {
      debugPrint('[Map] reuse decoded polyline renderKey=$renderKey');
      _fitBoundsForPoints(_decodedRoutePoints);
      return;
    }
    RoutePathInfo? routeInfo;
    final startLatLng = startLocation;
    final endLatLng = endLocation;

    try {
      if (routeId != null && routeId.trim().isNotEmpty) {
        routeInfo = await _routePathService.getOrFetchRoutePathForRoute(
          routeId: routeId,
          startPoint: startPoint,
          endPoint: endPoint,
        );
      } else if (startLatLng != null && endLatLng != null) {
        routeInfo = await _routePathService.fetchRoutePathByCoordinates(
          start: startLatLng,
          end: endLatLng,
          requirePolyline: true,
        );
      } else {
        routeInfo = await _routePathService.fetchRoutePath(
          startPoint: startPoint,
          endPoint: endPoint,
        );
      }
    } catch (e) {
      debugPrint('Route path API error: $e');
      // Last-resort fallback only if we don't have coordinates.
      if (startLatLng == null || endLatLng == null) {
        final geocodedStart = await GeocodingService.geocodeAddress(startPoint);
        final geocodedEnd = await GeocodingService.geocodeAddress(endPoint);
        if (geocodedStart != null && geocodedEnd != null) {
          routeInfo = await _routePathService.fetchRoutePathByCoordinates(
            start: geocodedStart,
            end: geocodedEnd,
            requirePolyline: true,
          );
        }
      }
    }

    if (!mounted) return;

    final start = startLatLng ?? routeInfo?.startLocation;
    final end = endLatLng ?? routeInfo?.endLocation;

    if (start == null || end == null) {
      AppMessage.showError(context, 'Could not geocode route points');
      return;
    }

    // Use only the decoded Directions API points. Manually forcing the marker
    // coordinates into the polyline creates a fake straight segment before the
    // road-snapped route begins.
    final routePoints = _dedupeConsecutivePoints(
      routeInfo?.path ?? const <LatLng>[],
    );
    _debugRouteDraw(
      source: 'PassengerHome',
      startMarker: start,
      endMarker: end,
      routeOrigin: routeInfo?.startLocation ?? start,
      routeDestination: routeInfo?.endLocation ?? end,
      decodedPoints: routePoints,
    );
    if (routePoints.length < 2) {
      AppMessage.showError(context, 'Could not load route polyline');
      return;
    }
    _decodedRoutePoints = routePoints;
    _activeRouteRenderKey = renderKey;

    setState(() {
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route_line'),
          points: routePoints,
          color: NavigoColors.primaryOrange,
          width: 5,
        ),
      );

      // Add start and end markers
      _markers.removeWhere(
        (m) =>
            m.markerId.value == 'route_start' ||
            m.markerId.value == 'route_end',
      );
      _markers.add(
        Marker(
          markerId: const MarkerId('route_start'),
          position: start,
          infoWindow: InfoWindow(
            title: context.texts.t('from'),
            snippet: startPoint,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
      _markers.add(
        Marker(
          markerId: const MarkerId('route_end'),
          position: end,
          infoWindow: InfoWindow(
            title: context.texts.t('to'),
            snippet: endPoint,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    });

    // Zoom to fit both points
    _fitBoundsForPoints(routePoints);
  }

  List<LatLng> _dedupeConsecutivePoints(List<LatLng> points) {
    final cleaned = <LatLng>[];
    for (final point in points) {
      if (cleaned.isNotEmpty && _sameLatLng(cleaned.last, point)) continue;
      cleaned.add(point);
    }
    return cleaned;
  }

  bool _sameLatLng(LatLng a, LatLng b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;

  void _debugRouteDraw({
    required String source,
    required LatLng startMarker,
    required LatLng endMarker,
    required LatLng routeOrigin,
    required LatLng routeDestination,
    required List<LatLng> decodedPoints,
  }) {
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

  String _fmt(LatLng point) =>
      '${point.latitude.toStringAsFixed(7)},${point.longitude.toStringAsFixed(7)}';

  void _fitBoundsForPoints(List<LatLng> points) {
    final c = _mapController;
    if (c == null || points.isEmpty) return;

    var south = points.first.latitude;
    var north = points.first.latitude;
    var west = points.first.longitude;
    var east = points.first.longitude;

    for (final point in points) {
      if (point.latitude < south) south = point.latitude;
      if (point.latitude > north) north = point.latitude;
      if (point.longitude < west) west = point.longitude;
      if (point.longitude > east) east = point.longitude;
    }

    c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        80,
      ),
    );
  }

  // ── Live Tracking ────────────────────────────────────────────────────────
  void _startLiveTracking(String driverId) {
    _liveDriverSub?.cancel();
    final db = FirebaseFirestore.instance;

    setState(() {
      _isLiveTracking = true;
      _trackedDriverPosition = null;
      _trackingEtaText = null;
    });

    _liveDriverSub = db.collection('drivers').doc(driverId).snapshots().listen((
      snap,
    ) {
      if (!mounted) return;
      final data = snap.data();
      if (data == null) return;

      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      LatLng? driverPos;

      if (lat != null && lng != null) {
        driverPos = LatLng(lat, lng);
      } else {
        final loc = data['location'];
        if (loc is Map) {
          final la = (loc['lat'] as num?)?.toDouble();
          final lo = (loc['lng'] as num?)?.toDouble();
          if (la != null && lo != null) {
            driverPos = LatLng(la, lo);
          }
        }
      }

      if (driverPos == null) return;

      final etaText = _etaBetween(
        from: driverPos,
        to: _passengerTrackingPosition,
      );

      setState(() {
        _trackedDriverPosition = driverPos;
        _trackingEtaText = etaText;
        _markers.removeWhere((m) => m.markerId.value == 'live_driver');
        _markers.add(
          Marker(
            markerId: const MarkerId('live_driver'),
            position: driverPos!,
            infoWindow: InfoWindow(
              title: context.texts.t('driver'),
              snippet: etaText == null
                  ? context.texts.t('liveLocation')
                  : '${context.texts.t('etaToPickup')}: $etaText',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueOrange,
            ),
          ),
        );
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: driverPos, zoom: 14.5),
        ),
      );
    });
  }

  void _stopLiveTracking() {
    _liveDriverSub?.cancel();
    _liveDriverSub = null;
    if (!mounted) return;
    setState(() {
      _isLiveTracking = false;
      _trackedDriverPosition = null;
      _trackingEtaText = null;
      _markers.removeWhere((m) => m.markerId.value == 'live_driver');
    });
  }

  Future<bool> _ensureLocationPermission({bool showMessages = false}) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (showMessages && mounted) {
        AppMessage.showError(context, 'Please enable location services');
      }
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (showMessages && mounted) {
        AppMessage.showError(context, 'Location permission denied');
      }
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      if (showMessages && mounted) {
        AppMessage.showError(
          context,
          'Enable location permission from settings',
        );
        await Geolocator.openAppSettings();
      }
      return false;
    }

    return true;
  }

  Future<void> _startPassengerLocationPublishing() async {
    if (_passengerLocationSub != null) return;
    final allowed = await _ensureLocationPermission();
    if (!allowed) return;
    debugPrint('[Geolocator] starting passenger location stream');

    _passengerLocationSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 10,
          ),
        ).listen(
          (position) async {
            final location = LatLng(position.latitude, position.longitude);

            if (!mounted) return;
            if (!_manualPickupSelected) {
              try {
                await _tripRepository.syncPassengerLiveLocation(location);
              } catch (e) {
                debugPrint("Passenger live location publish error: $e");
              }

              if (!mounted) return;
              final changed =
                  _passengerTrackingPosition?.latitude != location.latitude ||
                  _passengerTrackingPosition?.longitude != location.longitude;
              if (changed) {
                setState(() {
                  _passengerTrackingPosition = location;
                  _initialPosition = location;
                });
              }
              _refreshTrackingEta();
            }
          },
          onError: (e) {
            debugPrint("Passenger location stream error: $e");
          },
        );
  }

  String? _etaBetween({required LatLng from, required LatLng? to}) {
    if (to == null) return null;

    final meters = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    final minutes = (meters / 1000 / 30 * 60).ceil();
    return _formatEta(minutes < 1 ? 1 : minutes);
  }

  String _formatEta(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (rest == 0) return '${hours}h';
    return '${hours}h ${rest}m';
  }

  void _refreshTrackingEta() {
    if (!mounted) return;
    final driver = _trackedDriverPosition;
    if (driver == null) return;

    setState(() {
      _trackingEtaText = _etaBetween(
        from: driver,
        to: _passengerTrackingPosition,
      );
    });
  }

  // ── Existing methods ─────────────────────────────────────────────────────
  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() => _userName = "Guest");
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        setState(() {
          _userName = "${doc['firstName'] ?? ''} ${doc['lastName'] ?? ''}"
              .trim();
          if (_userName.isEmpty) _userName = "Guest";
        });
      } else {
        setState(() => _userName = "Guest");
      }
    } catch (e) {
      debugPrint("User load error: $e");
      if (!mounted) return;
      setState(() => _userName = "Guest");
    }
  }

  Future<void> _loadLinesFromFirestore() async {
    if (!mounted) return;
    setState(() => _isLoadingLines = true);

    try {
      final routes = await _tripRepository.fetchRoutes();

      final lines =
          routes
              .map(PassengerTripRepository.buildLineLabel)
              .where((line) => line.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort();

      if (!mounted) return;

      setState(() {
        _lines = lines;
        if (_showLineSuggestions) {
          _filteredLines = List.from(lines);
        }
      });

      debugPrint('Loaded route lines: $_lines');
    } catch (e) {
      debugPrint("Routes load error: $e");
      if (!mounted) return;
      AppMessage.showError(context, 'Failed to load routes: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingLines = false);
      }
    }
  }

  Future<void> _loadSavedRoute() async {
    final savedLine = await LocalStorageService.getSelectedLine();

    if (savedLine != null && mounted) {
      setState(() {
        _selectedLine = savedLine;
        _searchController.text = savedLine;
        _filteredLines = [];
        _showLineSuggestions = false;
      });
      unawaited(_drawSelectedLineRoute(savedLine));
    }
  }

  Future<void> _loadInitialPassengerLocation() async {
    try {
      final savedLocation = await _tripRepository.getSavedPassengerLocation();
      if (!mounted) return;

      if (savedLocation != null) {
        _setSelectedLocation(savedLocation, saveToFirestore: false);
        return;
      }

      await _getUserLocation();
    } catch (e) {
      debugPrint("Initial location load error: $e");
    }
  }

  Future<void> _loadCarMarker() async {
    try {
      final ByteData data = await rootBundle.load('assets/images/logo.png');
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 80,
        targetHeight: 90,
      );
      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? byteData = await fi.image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null && mounted) {
        setState(() {
          _carIcon = BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
        });
      }
    } catch (e) {
      debugPrint("Car marker load error: $e");
    }
  }

  Future<void> _getUserLocation() async {
    if (_isLocating) return;

    if (!mounted) return;
    setState(() => _isLocating = true);

    try {
      final allowed = await _ensureLocationPermission(showMessages: true);
      if (!allowed) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final newPosition = LatLng(position.latitude, position.longitude);

      // Reverse-geocode to area name
      final areaName = await GeocodingService.reverseGeocodeLabel(newPosition);

      if (!mounted) return;
      setState(() {
        _manualPickupSelected = false;
        _initialPosition = newPosition;
        _passengerTrackingPosition = newPosition;
        _selectedLocation = areaName;

        _markers.removeWhere((m) => m.markerId.value == "current_location");
        _markers.add(
          Marker(
            markerId: const MarkerId("current_location"),
            position: newPosition,
            infoWindow: InfoWindow(title: context.texts.t('myLocation')),
          ),
        );
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: newPosition, zoom: 15.5),
        ),
      );

      await _tripRepository.savePassengerLocation(newPosition);
      await _tripRepository.syncPassengerLiveLocation(newPosition);
      unawaited(_startPassengerLocationPublishing());
    } catch (e) {
      debugPrint("Location error: $e");
      if (!mounted) return;
      AppMessage.showError(context, 'Error getting location');
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  void _setSelectedLocation(LatLng location, {bool saveToFirestore = true}) {
    if (!mounted) return;

    setState(() {
      if (saveToFirestore) _manualPickupSelected = true;
      _initialPosition = location;
      _passengerTrackingPosition = location;
      // Show loading text while geocoding
      _selectedLocation = 'Loading area name...';

      _markers.removeWhere((m) => m.markerId.value == "current_location");
      _markers.add(
        Marker(
          markerId: const MarkerId("current_location"),
          position: location,
          infoWindow: InfoWindow(title: context.texts.t('myLocation')),
        ),
      );
    });

    // Reverse-geocode asynchronously
    GeocodingService.reverseGeocodeLabel(location).then((areaName) {
      if (!mounted) return;
      setState(() => _selectedLocation = areaName);
      if (saveToFirestore) {
        _tripRepository
            .syncPassengerDocumentLocation(
              location,
              pickupLocationDescription: areaName,
            )
            .catchError((e) {
              debugPrint("Manual passenger pickup label save error: $e");
            });
      }
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: location, zoom: 15.5),
      ),
    );

    if (saveToFirestore) {
      _tripRepository.savePassengerLocation(location).catchError((e) {
        debugPrint("Manual passenger location save error: $e");
      });
    }

    _refreshTrackingEta();
  }

  void _filterLines(String query) {
    final trimmed = query.trim().toLowerCase();

    setState(() {
      _showLineSuggestions = trimmed.isNotEmpty;
      if (trimmed.isEmpty) {
        _filteredLines = [];
      } else {
        _filteredLines = _lines.where((line) {
          return line.toLowerCase().contains(trimmed);
        }).toList();
      }
    });
  }

  Future<void> _drawSelectedLineRoute(String line) async {
    try {
      final route = await _tripRepository.getRouteForLine(line);
      if (route == null) return;

      final startLoc = route.startLocation;
      final endLoc = route.endLocation;
      final startLatLng =
          (startLoc != null &&
              startLoc['lat'] != null &&
              startLoc['lng'] != null)
          ? LatLng(startLoc['lat']!, startLoc['lng']!)
          : null;
      final endLatLng =
          (endLoc != null && endLoc['lat'] != null && endLoc['lng'] != null)
          ? LatLng(endLoc['lat']!, endLoc['lng']!)
          : null;

      await _drawRoutePolyline(
        route.startPoint,
        route.endPoint,
        routeId: route.routeId,
        startLocation: startLatLng,
        endLocation: endLatLng,
      );
    } catch (e) {
      debugPrint('Draw selected route error: $e');
    }
  }

  void _clearRouteLine() {
    setState(() {
      _polylines.clear();
      _decodedRoutePoints = const [];
      _activeRouteRenderKey = null;
      _markers.removeWhere(
        (marker) =>
            marker.markerId.value == 'route_start' ||
            marker.markerId.value == 'route_end',
      );
    });
  }

  Future<void> _showDriversNow() async {
    final hasLine = _selectedLine != null && _selectedLine!.trim().isNotEmpty;

    final filteredDrivers = hasLine
        ? await _tripRepository.getDriversForLine(_selectedLine!)
        : await _tripRepository.getAllDrivers();

    if (!mounted) return;

    if (filteredDrivers.isEmpty) {
      AppMessage.showInfo(context, context.texts.t('noVehiclesFound'));
      return;
    }

    final Set<Marker> driverMarkers = filteredDrivers.map((driver) {
      return Marker(
        markerId: MarkerId(driver['id'] as String),
        position: LatLng(driver['lat'] as double, driver['lng'] as double),
        icon:
            _carIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: driver['name'] as String,
          snippet: "${driver['line']} • ${driver['eta']}",
        ),
        onTap: () {
          _showDriverTripSheet(driver);
        },
      );
    }).toSet();

    setState(() {
      _markers.removeWhere((m) => m.markerId.value != "current_location");
      _markers.addAll(driverMarkers);
    });

    final first = filteredDrivers.first;
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(first['lat'] as double, first['lng'] as double),
          zoom: 12.8,
        ),
      ),
    );
  }

  void _showDriverTripSheet(Map<String, dynamic> driver) {
    _selectedSeatsCount = 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
                top: false,
                child: Wrap(
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: NavigoColors.lightorange,
                          child: const Icon(
                            Icons.directions_car,
                            color: NavigoColors.primaryOrange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            driver['name'] as String,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: NavigoColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _tripInfoRow(
                      Icons.confirmation_number,
                      context.texts.t('vehicle'),
                      driver['busNumber'] as String,
                    ),
                    _tripInfoRow(
                      Icons.directions_bus,
                      context.texts.t('vehicleType'),
                      driver['vehicleType'] as String,
                    ),
                    _tripInfoRow(
                      Icons.route,
                      context.texts.t('line'),
                      driver['line'] as String,
                    ),
                    _tripInfoRow(
                      Icons.event_seat,
                      context.texts.t('availableSeats'),
                      "${driver['availableSeats']}",
                    ),
                    _tripInfoRow(
                      Icons.phone,
                      context.texts.t('phone'),
                      driver['phone'] as String,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text(
                          context.texts.t('numberOfSeats'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: NavigoColors.textDark,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: NavigoColors.backgroundLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  if (_selectedSeatsCount > 1) {
                                    setModalState(() {
                                      _selectedSeatsCount--;
                                    });
                                  }
                                },
                                icon: const Icon(
                                  Icons.remove,
                                  size: 18,
                                  color: NavigoColors.primaryOrange,
                                ),
                              ),
                              SizedBox(
                                width: 35,
                                child: Center(
                                  child: Text(
                                    _selectedSeatsCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  if (_selectedSeatsCount <
                                      (driver['availableSeats'] as int)) {
                                    setModalState(() {
                                      _selectedSeatsCount++;
                                    });
                                  }
                                },
                                icon: const Icon(
                                  Icons.add,
                                  size: 18,
                                  color: NavigoColors.primaryOrange,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () async {
                          final nav = Navigator.of(context);
                          nav.pop();
                          try {
                            await _tripRequestService.createRequest(
                              driverId: driver['id'] as String,
                              routeId:
                                  (driver['routeId'] as String?)?.trim() ?? '',
                              scheduleId:
                                  (driver['scheduleId'] as String?)?.trim() ??
                                  (driver['slotId'] as String?)?.trim() ??
                                  '',
                              seatsRequested: _selectedSeatsCount,
                              lineLabel: driver['line'] as String? ?? '',
                              startPoint: driver['from'] as String? ?? '',
                              endPoint: driver['to'] as String? ?? '',
                              pickupDescription: _selectedLocation ?? '',
                            );
                            if (!this.context.mounted) return;
                            AppMessage.showSuccess(
                              this.context,
                              '${context.texts.t('requestSentTo')} ${driver['name']}. '
                              '${context.texts.t('driverAcceptDecline')}',
                            );
                          } catch (e) {
                            if (!this.context.mounted) return;
                            AppMessage.showError(
                              this.context,
                              e.toString().replaceFirst('Exception: ', ''),
                            );
                          }
                        },
                        style: NavigoDecorations.kPrimaryButtonLargeStyle,
                        child: Text(
                          context.texts.t('confirmTrip'),
                          style: NavigoTextStyles.button,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _tripInfoRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: NavigoColors.accentGreen),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 15,
                  color: NavigoColors.textDark,
                ),
                children: [
                  TextSpan(
                    text: "$title: ",
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openScheduleTrip() async {
    final saved = await LocalStorageService.getSelectedLine();
    final line = (saved != null && saved.trim().isNotEmpty)
        ? saved.trim()
        : _selectedLine?.trim();

    if (line == null || line.isEmpty) {
      if (!mounted) return;
      AppMessage.showError(context, context.texts.t('selectLineFirst'));
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScheduleScreen(selectedLine: line)),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[Map] PassengerHomeScreen build');
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final pagePadding = Responsive.horizontalPadding(context);
    final bannerTop = media.padding.top + (isLandscape ? 132 : 180);

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const PassengerBottomNavBar(currentIndex: 0),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialPosition,
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (controller) {
              _mapController = controller;
              // If we have route points, fit bounds after map is created
              if (widget.routeStartPoint != null &&
                  widget.routeEndPoint != null &&
                  _polylines.isNotEmpty) {
                final points = _polylines.first.points;
                if (points.length >= 2) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _fitBoundsForPoints(points);
                  });
                }
              }
            },
            onTap: (latLng) => _setSelectedLocation(latLng),
          ),
          SafeArea(
            child: Padding(
              // Responsive safe padding keeps the search/header overlay inside
              // notches and balanced across phones/tablets.
              padding: EdgeInsets.all(pagePadding.clamp(12, 20)),
              child: Column(
                children: [
                  NavigoDecorations.homeStyleTitleBar(
                    title: "${context.texts.t('hello')}, $_userName",
                    subtitle: context.texts.t('whereToGo'),
                    avatar: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                                    const Icon(
                                      Icons.notifications_none,
                                      size: 20,
                                    ),
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
                  SizedBox(height: Responsive.verticalGap(context, 12)),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                              controller: _searchController,
                              style: const TextStyle(
                                color: NavigoColors.textDark,
                              ),
                              decoration: NavigoDecorations.kInputDecoration
                                  .copyWith(
                                    hintText: _isLoadingLines
                                        ? context.texts.t('loadingRoutes')
                                        : context.texts.t('searchRoute'),
                                    filled: true,
                                    fillColor: NavigoColors.surfaceWhite,
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: NavigoColors.accentGreen,
                                    ),
                                    suffixIcon: _isLoadingLines
                                        ? const Padding(
                                            padding: EdgeInsets.all(12),
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          )
                                        : (_searchController.text.isNotEmpty
                                              ? IconButton(
                                                  icon: const Icon(
                                                    Icons.close,
                                                    color: Colors.grey,
                                                  ),
                                                  onPressed: () {
                                                    setState(() {
                                                      _searchController.clear();
                                                      _selectedLine = null;
                                                      _filteredLines = [];
                                                      _showLineSuggestions =
                                                          false;
                                                    });
                                                  },
                                                )
                                              : null),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(30),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                              onChanged: _filterLines,
                            ),
                            if (_showLineSuggestions &&
                                _filteredLines.isNotEmpty &&
                                _searchController.text.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                constraints: const BoxConstraints(
                                  maxHeight: 180,
                                ),
                                decoration: BoxDecoration(
                                  color: NavigoColors.surfaceWhite,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _filteredLines.length,
                                  itemBuilder: (context, index) {
                                    final line = _filteredLines[index];
                                    return ListTile(
                                      title: Text(line),
                                      onTap: () async {
                                        setState(() {
                                          _selectedLine = line;
                                          _searchController.text = line;
                                          _filteredLines = [];
                                          _showLineSuggestions = false;
                                        });
                                        FocusScope.of(context).unfocus();
                                        await LocalStorageService.saveSelectedLine(
                                          line,
                                        );
                                        await _drawSelectedLineRoute(line);
                                      },
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(width: Responsive.verticalGap(context, 10)),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _isLocating
                              ? const CircularProgressIndicator()
                              : FloatingActionButton.small(
                                  backgroundColor: NavigoColors.primaryOrange,
                                  onPressed: _getUserLocation,
                                  child: const Icon(Icons.my_location),
                                ),
                          if (_polylines.isNotEmpty && !_isLiveTracking) ...[
                            const SizedBox(height: 4),
                            FloatingActionButton.small(
                              heroTag: 'clear_route_line',
                              backgroundColor: NavigoColors.surfaceWhite,
                              onPressed: _clearRouteLine,
                              child: const Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(
                                    Icons.route_outlined,
                                    size: 20,
                                    color: NavigoColors.primaryOrange,
                                  ),
                                  Positioned(
                                    right: -5,
                                    top: -5,
                                    child: Icon(
                                      Icons.close,
                                      size: 12,
                                      color: NavigoColors.accentRed,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Live tracking banner ──────────────────────────────────────────
          if (_isLiveTracking)
            Positioned(
              top: bannerTop,
              left: pagePadding,
              right: pagePadding,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: NavigoColors.accentGreen,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 8),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.gps_fixed, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _trackingEtaText == null
                            ? context.texts.t('trackingDriverLive')
                            : '${context.texts.t('etaToPickup')}: $_trackingEtaText',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _stopLiveTracking,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          context.texts.t('stop'),
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          DraggableScrollableSheet(
            initialChildSize: 0.10,
            minChildSize: 0.10,
            maxChildSize: isLandscape ? 0.33 : 0.22,
            snap: true,
            snapSizes: isLandscape ? const [0.40,0.33] :const[0.15,0.22],
            builder: (context, scrollController) {
              return Container(
                margin: EdgeInsets.symmetric(horizontal: pagePadding * 0.5),
                decoration: BoxDecoration(
                  color: NavigoColors.lightorange,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(isLandscape ? 18 : 25),
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 16),
                  ],
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    pagePadding,
                    Responsive.verticalGap(context, 10),
                    pagePadding,
                    media.padding.bottom + Responsive.verticalGap(context, 18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: NavigoColors.textMuted.withValues(
                              alpha: 0.4,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(
                            Icons.directions_bus,
                            color: NavigoColors.accentGreen,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "${context.texts.t('line')}: ${_selectedLine ?? context.texts.t('notSelected')}",
                              style: NavigoTextStyles.bodyMedium.copyWith(
                                color: NavigoColors.textDark,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: NavigoColors.accentGreen,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "${context.texts.t('location')}: ${_selectedLocation ?? context.texts.t('notSelected')}",
                              style: NavigoTextStyles.bodyMedium.copyWith(
                                color: NavigoColors.textDark,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: Responsive.verticalGap(context, 16)),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: Responsive.buttonHeight(context),
                              child: ElevatedButton(
                                onPressed: _showDriversNow,
                                style:
                                    NavigoDecorations.kPrimaryButtonLargeStyle,
                                child: Text(
                                  context.texts.t('now'),
                                  style: NavigoTextStyles.button,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: Responsive.verticalGap(context, 12)),
                          Expanded(
                            child: SizedBox(
                              height: Responsive.buttonHeight(context),
                              child: ElevatedButton(
                                onPressed: () => _openScheduleTrip(),
                                style:
                                    NavigoDecorations.kPrimaryButtonLargeStyle,
                                child: Text(
                                  context.texts.t('scheduleTrip'),
                                  style: NavigoTextStyles.button,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
