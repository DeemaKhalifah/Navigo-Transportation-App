import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../localization/localization_x.dart';
import '../../services/google_route_path_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/responsive.dart';
import 'passenger_bottom_nav_bar.dart';

/// Live map: driver from `drivers`, passenger from `passengers` only.
class PassengerLiveTrackScreen extends StatefulWidget {
  const PassengerLiveTrackScreen({
    super.key,
    required this.driverId,
    this.routeId = '',
    this.slotId = '',
    this.driverName,
  });

  final String driverId;
  final String routeId;
  final String slotId;
  final String? driverName;

  @override
  State<PassengerLiveTrackScreen> createState() =>
      _PassengerLiveTrackScreenState();
}

class _PassengerLiveTrackScreenState extends State<PassengerLiveTrackScreen> {
  GoogleMapController? _mapController;

  Map<String, dynamic>? _driverDocData;

  Map<String, dynamic>? _passengerData;
  final GoogleRoutePathService _routePathService = GoogleRoutePathService();
  Set<Polyline> _polylines = {};
  String? _activeLiveRouteKey;
  String? _pendingLiveRouteKey;

  StreamSubscription<DocumentSnapshot>? _driversSub;
  StreamSubscription<DocumentSnapshot>? _passengerSub;

  static const LatLng _fallback = LatLng(31.7683, 35.2137);

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    _driversSub = db
        .collection('drivers')
        .doc(widget.driverId)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() => _driverDocData = snap.data());
          _scheduleFollowDriver();
          unawaited(_refreshLiveRoute());
        });

    if (uid != null && uid.isNotEmpty) {
      _passengerSub = db.collection('passengers').doc(uid).snapshots().listen((
        snap,
      ) {
        if (!mounted) return;
        setState(() => _passengerData = snap.data());
        unawaited(_refreshLiveRoute());
      });
    }
  }

  void _scheduleFollowDriver() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _mapController;
      final d = _driverLatLng();
      if (c == null || d == null) return;
      final p = _passengerLatLng();
      if (p != null) {
        unawaited(_recenter());
      } else {
        c.animateCamera(CameraUpdate.newLatLngZoom(d, 14.2));
      }
    });
  }

  @override
  void dispose() {
    _driversSub?.cancel();
    _passengerSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  LatLng? _driverLatLng() {
    final d = _driverDocData;
    if (d == null) return null;
    final lat = (d['latitude'] as num?)?.toDouble();
    final lng = (d['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null) return LatLng(lat, lng);
    return _latLngFromMap(d['location']);
  }

  LatLng? _passengerLatLng() {
    final p = _passengerData;
    if (p == null) return null;
    final lat = (p['latitude'] as num?)?.toDouble();
    final lng = (p['longitude'] as num?)?.toDouble();
    if (lat != null && lng != null) return LatLng(lat, lng);
    return _latLngFromMap(p['location']);
  }

  static LatLng? _latLngFromMap(dynamic location) {
    if (location is GeoPoint) {
      return LatLng(location.latitude, location.longitude);
    }
    if (location is! Map) return null;
    final lat =
        (location['lat'] as num?)?.toDouble() ??
        (location['latitude'] as num?)?.toDouble();
    final lng =
        (location['lng'] as num?)?.toDouble() ??
        (location['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  LatLng _cameraTarget() {
    final d = _driverLatLng();
    if (d != null) return d;
    final p = _passengerLatLng();
    if (p != null) return p;
    return _fallback;
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    final driverPos = _driverLatLng();
    if (driverPos != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: driverPos,
          infoWindow: InfoWindow(
            title: widget.driverName?.trim().isNotEmpty == true
                ? widget.driverName!
                : 'Driver',
            snippet: 'Live location',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
        ),
      );
    }

    final passPos = _passengerLatLng();
    if (passPos != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('me'),
          position: passPos,
          infoWindow: InfoWindow(
            title: context.texts.t('you'),
            snippet: context.texts.t('yourPickup'),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    return markers;
  }

  Future<void> _refreshLiveRoute() async {
    final driver = _driverLatLng();
    final passenger = _passengerLatLng();
    _debugRouteDraw(
      source: 'PassengerLiveTrack',
      startMarker: driver,
      endMarker: passenger,
      routeOrigin: driver,
      routeDestination: passenger,
      decodedPoints: _polylines.isEmpty
          ? const <LatLng>[]
          : _polylines.first.points,
    );

    if (driver == null || passenger == null) {
      if (!mounted) return;
      setState(() {
        _polylines = {};
        _activeLiveRouteKey = null;
        _pendingLiveRouteKey = null;
      });
      return;
    }

    final key =
        '${_fmt(driver)}->${_fmt(passenger)}';
    if (_activeLiveRouteKey == key || _pendingLiveRouteKey == key) return;

    _pendingLiveRouteKey = key;
    try {
      final info = await _routePathService.fetchRoutePathByCoordinates(
        start: driver,
        end: passenger,
        requirePolyline: true,
      );
      final points = _dedupeConsecutivePoints(info.path);
      _debugRouteDraw(
        source: 'PassengerLiveTrack',
        startMarker: driver,
        endMarker: passenger,
        routeOrigin: info.startLocation,
        routeDestination: info.endLocation,
        decodedPoints: points,
      );
      if (!mounted || _pendingLiveRouteKey != key || points.length < 2) return;
      setState(() {
        _activeLiveRouteKey = key;
        _pendingLiveRouteKey = null;
        // Draw only the decoded route points returned by Google. No manual
        // driver/passenger endpoint points are inserted into the path.
        _polylines = {
          Polyline(
            polylineId: const PolylineId('live_driver_to_passenger'),
            points: points,
            color: NavigoColors.primaryOrange,
            width: 5,
          ),
        };
      });
    } catch (e) {
      debugPrint('[PassengerLiveTrack] live route redraw failed: $e');
      if (!mounted || _pendingLiveRouteKey != key) return;
      setState(() => _pendingLiveRouteKey = null);
    }
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
    debugPrint('[$source] start marker coordinates=${_fmtNullable(startMarker)}');
    debugPrint('[$source] end marker coordinates=${_fmtNullable(endMarker)}');
    debugPrint('[$source] route origin coordinates=${_fmtNullable(routeOrigin)}');
    debugPrint(
      '[$source] route destination coordinates=${_fmtNullable(routeDestination)}',
    );
    if (decodedPoints.isEmpty) {
      debugPrint('[$source] decoded polyline has no points');
      return;
    }
    debugPrint(
      '[$source] first decoded polyline point=${_fmtNullable(decodedPoints.first)}',
    );
    debugPrint(
      '[$source] last decoded polyline point=${_fmtNullable(decodedPoints.last)}',
    );
  }

  String _fmt(LatLng point) =>
      '${point.latitude.toStringAsFixed(5)},${point.longitude.toStringAsFixed(5)}';

  String _fmtNullable(LatLng? point) {
    if (point == null) return 'null';
    return '${point.latitude.toStringAsFixed(7)},${point.longitude.toStringAsFixed(7)}';
  }

  Future<void> _recenter() async {
    final c = _mapController;
    if (c == null) return;
    final d = _driverLatLng();
    final p = _passengerLatLng();
    if (d != null && p != null) {
      final south = math.min(d.latitude, p.latitude);
      final north = math.max(d.latitude, p.latitude);
      final west = math.min(d.longitude, p.longitude);
      final east = math.max(d.longitude, p.longitude);
      await c.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(south, west),
            northeast: LatLng(north, east),
          ),
          80,
        ),
      );
      return;
    }
    await c.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: _cameraTarget(), zoom: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final driverPos = _driverLatLng();
    final markers = _buildMarkers();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const PassengerBottomNavBar(currentIndex: 2),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pop(context),
              context: context,
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.texts.t('liveTracking'),
                    style: NavigoTextStyles.titleLarge,
                  ),
                  SizedBox(height: Responsive.verticalGap(context, 4)),
                  Text(
                    driverPos == null
                        ? context.texts.t('waitingDriverLocation')
                        : context.texts.t('followingDriver'),
                    style: NavigoTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            SizedBox(height: Responsive.verticalGap(context, 10)),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: padding * 0.7),
                child: ClipRRect(
                  // The map fills the remaining Expanded area while the border
                  // radius scales down in landscape to preserve usable map room.
                  borderRadius: BorderRadius.circular(isLandscape ? 14 : 22),
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _cameraTarget(),
                          zoom: 13.5,
                        ),
                        myLocationEnabled: false,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        markers: markers,
                        polylines: _polylines,
                        onMapCreated: (controller) {
                          _mapController = controller;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _recenter();
                            unawaited(_refreshLiveRoute());
                          });
                        },
                      ),
                      Positioned(
                        top: Responsive.verticalGap(context, 12),
                        right: Responsive.verticalGap(context, 12),
                        child: Material(
                          color: NavigoColors.surfaceWhite,
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: const Icon(
                              Icons.fit_screen,
                              color: NavigoColors.primaryOrange,
                            ),
                            onPressed: _recenter,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: Responsive.verticalGap(context, 10)),
          ],
        ),
      ),
    );
  }
}
