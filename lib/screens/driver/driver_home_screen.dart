import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/schedule_slot.dart';
import '../../models/trip_status.dart';
import '../../models/driver_status.dart';
import '../../services/driver_live_trip_service.dart';
import '../../services/driver_trips_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import 'driver_bottom_nav_bar.dart';
import 'package:navigo/screens/notifications_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

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

  // ── Passenger pin data ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> _passengerPins = [];

  @override
  void initState() {
    super.initState();
    _loadDriverName();
    _watchDriverStatus();
    _getUserLocation();
    _watchTrips();
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
    } catch (_) {}
    super.dispose();
  }

  Future<void> _watchDriverStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _driverDocRef = FirebaseFirestore.instance.collection('drivers').doc(uid);
    try {
      final direct = await _driverDocRef!.get();
      if (!direct.exists) {
        final q = await FirebaseFirestore.instance
            .collection('drivers')
            .where('userId', isEqualTo: uid)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          _driverDocRef = q.docs.first.reference;
        }
      }
    } catch (_) {}

    _driverDocSub?.cancel();
    _driverDocSub = _driverDocRef?.snapshots().listen((snap) {
      if (!mounted || _isDisposed) return;
      if (!snap.exists) return;
      final data = snap.data() ?? {};
      setState(() {
        _driverStatus = DriverStatus.normalize(
          data['status']?.toString() ?? DriverStatus.offline,
        );
      });
    });
  }

  Future<void> _loadDriverName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!mounted || _isDisposed) return;
      final first = (doc.data()?['firstName'] ?? '').toString().trim();
      final last = (doc.data()?['lastName'] ?? '').toString().trim();
      final name = '$first $last'.trim();
      setState(() => _driverName = name.isNotEmpty ? name : 'Driver');
    } catch (_) {}
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
      }
    });
  }

  void _startLiveTracking(ScheduleSlot slot) {
    if (_isDisposed) return;

    final driverId =
        _driverDocRef?.id ?? FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null) return;

    setState(() {
      _activeSlot = slot;
      _activeRouteId = slot.routeId;
      _tripLine = _tripsService.lineOf(slot);
    });

    _startGpsPublishing(driverId);

    _liveDataSub = _liveService
        .watchLiveTrip(routeId: slot.routeId, tripId: slot.slotId)
        .listen((data) {
          if (!mounted || _isDisposed || data == null) return;

          final startLat = data['startLat'] as double?;
          final startLng = data['startLng'] as double?;
          final endLat = data['endLat'] as double?;
          final endLng = data['endLng'] as double?;
          final routePath = <LatLng>[];
          for (final point in data['routePath'] as List? ?? const []) {
            if (point is! Map) continue;
            final lat = point['lat'];
            final lng = point['lng'];
            if (lat is num && lng is num) {
              routePath.add(LatLng(lat.toDouble(), lng.toDouble()));
            }
          }

          _polylines.clear();
          if (routePath.isNotEmpty) {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('trip_path'),
                points: routePath,
                width: 5,
                color: NavigoColors.primaryOrange,
              ),
            );
          } else if (startLat != null &&
              startLng != null &&
              endLat != null &&
              endLng != null) {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('trip_path'),
                points: [LatLng(startLat, startLng), LatLng(endLat, endLng)],
                width: 4,
                color: NavigoColors.primaryOrange,
              ),
            );
          }

          final driverLoc = data['driverLocation'] as Map<String, double>?;
          final eta = _liveService.etaText(
            from: driverLoc,
            toLat: endLat,
            toLng: endLng,
          );
          if (mounted && !_isDisposed) setState(() => _etaText = eta);
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
    _locationSub?.cancel();
    _locationSub = null;
    _liveDataSub?.cancel();
    _liveDataSub = null;
    _passengersSub?.cancel();
    _passengersSub = null;
    _activeSlot = null;
    _activeRouteId = null;
    _tripLine = null;
    _etaText = null;
    _passengerPins = [];
    _polylines.clear();
    _markers.removeWhere(
      (m) =>
          m.markerId.value.startsWith('passenger_') ||
          m.markerId.value == 'route_start' ||
          m.markerId.value == 'route_end',
    );
  }

  Future<void> _startGpsPublishing(String driverId) async {
    if (_isLocating || _isDisposed) return;
    if (mounted) setState(() => _isLocating = true);

    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await _liveService.updateDriverLocation(
        driverId: driverId,
        latitude: current.latitude,
        longitude: current.longitude,
      );

      _updateDriverMarker(LatLng(current.latitude, current.longitude));

      _locationSub?.cancel();
      _locationSub =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen((pos) async {
            if (_isDisposed) return;
            await _liveService.updateDriverLocation(
              driverId: driverId,
              latitude: pos.latitude,
              longitude: pos.longitude,
            );
            _updateDriverMarker(LatLng(pos.latitude, pos.longitude));
          });
    } catch (e) {
      debugPrint('GPS publish error: $e');
    } finally {
      if (mounted && !_isDisposed) setState(() => _isLocating = false);
    }
  }

  Future<void> _getUserLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _updateDriverMarker(LatLng(pos.latitude, pos.longitude));

      final driverId =
          _driverDocRef?.id ?? FirebaseAuth.instance.currentUser?.uid;
      if (driverId != null && driverId.trim().isNotEmpty) {
        await _liveService.updateDriverLocation(
          driverId: driverId,
          latitude: pos.latitude,
          longitude: pos.longitude,
        );

        _locationSub ??=
            Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 10,
              ),
            ).listen((livePos) async {
              if (_isDisposed) return;
              await _liveService.updateDriverLocation(
                driverId: driverId,
                latitude: livePos.latitude,
                longitude: livePos.longitude,
              );
              _updateDriverMarker(LatLng(livePos.latitude, livePos.longitude));
            });
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  void _updateDriverMarker(LatLng pos) {
    if (_isDisposed || !mounted) return;
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
    _safeAnimateCamera(pos);
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
    } catch (_) {}
  }

  Future<void> _endTrip() async {
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null || _activeSlot == null) return;

    setState(() => _isEndingTrip = true);

    try {
      _locationSub?.cancel();
      _locationSub = null;

      await _liveService.completeTrip(
        routeId: _activeRouteId ?? '',
        tripId: _activeSlot!.slotId,
        driverId: driverId,
      );

      if (!mounted || _isDisposed) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Trip ended successfully')));

      _stopLiveTracking();
      setState(() {});
    } catch (e) {
      if (!mounted || _isDisposed) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to end trip: $e')));
    } finally {
      if (mounted && !_isDisposed) setState(() => _isEndingTrip = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool hasActiveTrip = _activeSlot != null;
    final bool isAvailable = _driverStatus == DriverStatus.available;
    final bool isOffline = _driverStatus == DriverStatus.offline;
    final bool isAssigned = _driverStatus == DriverStatus.assigned;

    final String statusLabel = isAvailable
        ? 'Available'
        : (isAssigned ? 'Assigned' : 'Offline');
    final Color statusColor = isAvailable
        ? NavigoColors.accentGreen
        : (isAssigned ? NavigoColors.primaryOrange : NavigoColors.accentRed);
    final IconData statusIcon = isAvailable
        ? Icons.check_circle_outline
        : (isAssigned
              ? Icons.assignment_turned_in_outlined
              : Icons.cancel_outlined);

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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                          'Hello, $_driverName',
                          style: NavigoTextStyles.titleSmall,
                        ),
                        Text(
                          hasActiveTrip
                              ? 'Live trip in progress'
                              : 'No active trip',
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
            top: 120,
            right: 16,
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
            child: Container(
              decoration: BoxDecoration(
                color: NavigoColors.surfaceWhite,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 16),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                          decoration: NavigoDecorations.iconCircleDecoration(
                            statusColor,
                          ),
                          child: Icon(statusIcon, color: statusColor, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isOffline
                                    ? 'You are Offline'
                                    : (isAssigned
                                          ? 'You have an Assigned trip'
                                          : 'You are Available'),
                                style: NavigoTextStyles.titleSmall.copyWith(
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Assigned trips: $_assignedTripsCount',
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
                          decoration: NavigoDecorations.iconCircleDecoration(
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
                                _tripLine ?? 'Active Trip',
                                style: NavigoTextStyles.titleSmall.copyWith(
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              if (_etaText != null)
                                Text(
                                  'ETA: $_etaText',
                                  style: NavigoTextStyles.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        NavigoDecorations.statusChip(
                          label: 'On Trip',
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
                          label: 'Total',
                          value: '${_activeSlot!.passengersIds.length}',
                          color: NavigoColors.primaryOrange,
                        ),
                        const SizedBox(width: 10),
                        _statChip(
                          icon: Icons.location_on,
                          label: 'On Map',
                          value: '$_passengersOnMap',
                          color: NavigoColors.accentBlue,
                        ),
                        const SizedBox(width: 10),
                        _statChip(
                          icon: Icons.event_seat,
                          label: 'Capacity',
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
                            : const Text(
                                'End Trip',
                                style: NavigoTextStyles.button,
                              ),
                      ),
                    ),
                  ],
                ],
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
