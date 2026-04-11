import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/route.dart';
import '../../models/schedule_slot.dart';
import '../../services/driver_live_trip_service.dart';
import '../../theme/app_theme.dart';
import '../Driver/DriverTripsScreen.dart';
import 'DriverBottomNavBar.dart';

class DriverLiveTripScreen extends StatefulWidget {
  final String tripId;
  final String routeId;

  /// When true, trip is already `ongoing` in Firestore — only attach GPS tracking, do not run [startTrip] again.
  final bool resumeExistingTrip;

  const DriverLiveTripScreen({
    super.key,
    required this.tripId,
    required this.routeId,
    this.resumeExistingTrip = false,
  });

  @override
  State<DriverLiveTripScreen> createState() => _DriverLiveTripScreenState();
}

class _DriverLiveTripScreenState extends State<DriverLiveTripScreen> {
  final DriverLiveTripService _service = DriverLiveTripService();

  GoogleMapController? _mapController;
  StreamSubscription<Position>? _locationSubscription;

  bool _isLocating = false;
  bool _isEndingTrip = false;
  bool _isDisposed = false;
  bool _hasStartedTrip = false;

  LatLng _fallbackCenter = const LatLng(31.9038, 35.2034);

  @override
  void initState() {
    super.initState();
    _startTripAndTracking();
  }

  Future<void> _startTripAndTracking() async {
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null || driverId.trim().isEmpty) return;

    try {
      if (!_hasStartedTrip) {
        _hasStartedTrip = true;

        if (!widget.resumeExistingTrip) {
          double? startLat;
          double? startLng;
          try {
            var permission = await Geolocator.checkPermission();
            if (permission == LocationPermission.denied) {
              permission = await Geolocator.requestPermission();
            }
            if (permission != LocationPermission.denied &&
                permission != LocationPermission.deniedForever) {
              if (await Geolocator.isLocationServiceEnabled()) {
                final pos = await Geolocator.getCurrentPosition(
                  desiredAccuracy: LocationAccuracy.high,
                );
                startLat = pos.latitude;
                startLng = pos.longitude;
              }
            }
          } catch (e) {
            debugPrint('Start trip initial location: $e');
          }

          await _service.startTrip(
            routeId: widget.routeId,
            tripId: widget.tripId,
            driverId: driverId,
            startLatitude: startLat,
            startLongitude: startLng,
          );

          if (startLat != null && startLng != null) {
            await _service.updateDriverLocation(
              driverId: driverId,
              latitude: startLat,
              longitude: startLng,
            );
          }
        }
      }

      await _startLiveTracking(driverId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start trip: $e')));
    }
  }

  Future<void> _startLiveTracking(String driverId) async {
    if (_isLocating || _isDisposed) return;

    if (mounted) {
      setState(() => _isLocating = true);
    }

    try {
      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;

      final current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await _service.updateDriverLocation(
        driverId: driverId,
        latitude: current.latitude,
        longitude: current.longitude,
      );

      if (mounted && !_isDisposed) {
        setState(() {
          _fallbackCenter = LatLng(current.latitude, current.longitude);
        });
      }

      await _safeAnimateCamera(LatLng(current.latitude, current.longitude));

      await _locationSubscription?.cancel();

      _locationSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10,
            ),
          ).listen((position) async {
            if (_isDisposed) return;

            try {
              await _service.updateDriverLocation(
                driverId: driverId,
                latitude: position.latitude,
                longitude: position.longitude,
              );

              if (!mounted || _isDisposed) return;

              final driverLatLng = LatLng(
                position.latitude,
                position.longitude,
              );

              setState(() {
                _fallbackCenter = driverLatLng;
              });

              await _safeAnimateCamera(driverLatLng);
            } catch (_) {}
          });
    } catch (e) {
      debugPrint('Driver live tracking error: $e');
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isLocating = false);
      }
    }
  }

  Future<void> _safeAnimateCamera(LatLng target) async {
    if (_isDisposed || !mounted) return;
    final controller = _mapController;
    if (controller == null) return;

    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 14.5),
        ),
      );
    } catch (_) {
      // Ignore if map was rebuilt/disposed.
    }
  }

  Future<void> _endTrip() async {
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null || driverId.trim().isEmpty) return;

    try {
      if (mounted) {
        setState(() => _isEndingTrip = true);
      }

      await _locationSubscription?.cancel();
      _locationSubscription = null;

      await _service.completeTrip(
        routeId: widget.routeId,
        tripId: widget.tripId,
        driverId: driverId,
      );

      if (!mounted || _isDisposed) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverTripsScreen()),
      );
    } catch (e) {
      if (!mounted || _isDisposed) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to end trip: $e')));
    } finally {
      if (mounted && !_isDisposed) {
        setState(() => _isEndingTrip = false);
      }
    }
  }

  Set<Marker> _buildMarkers({
    required Map<String, double>? driverLocation,
    required List<Map<String, dynamic>> passengers,
    required double? startLat,
    required double? startLng,
    required double? endLat,
    required double? endLng,
  }) {
    final Set<Marker> markers = {};

    if (driverLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver_location'),
          position: LatLng(driverLocation['lat']!, driverLocation['lng']!),
          infoWindow: const InfoWindow(title: 'Driver'),
        ),
      );
    }

    if (startLat != null && startLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('route_start'),
          position: LatLng(startLat, startLng),
          infoWindow: const InfoWindow(title: 'Start point'),
        ),
      );
    }

    if (endLat != null && endLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('route_end'),
          position: LatLng(endLat, endLng),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    }

    for (final passenger in passengers) {
      final lat = passenger['latitude'];
      final lng = passenger['longitude'];

      if (lat is num && lng is num) {
        markers.add(
          Marker(
            markerId: MarkerId('passenger_${passenger['userId']}'),
            position: LatLng(lat.toDouble(), lng.toDouble()),
            infoWindow: InfoWindow(
              title: (passenger['name'] ?? 'Passenger').toString(),
              snippet: 'Pickup: ${(passenger['pickup'] ?? '').toString()}',
            ),
          ),
        );
      }
    }

    return markers;
  }

  Set<Polyline> _buildPolylines({
    required double? startLat,
    required double? startLng,
    required double? endLat,
    required double? endLng,
  }) {
    if (startLat == null ||
        startLng == null ||
        endLat == null ||
        endLng == null) {
      return {};
    }

    return {
      Polyline(
        polylineId: const PolylineId('trip_path'),
        points: [LatLng(startLat, startLng), LatLng(endLat, endLng)],
        width: 5,
        color: NavigoColors.primaryOrange,
      ),
    };
  }

  LatLng _cameraCenter({
    required Map<String, double>? driverLocation,
    required double? startLat,
    required double? startLng,
  }) {
    if (driverLocation != null) {
      return LatLng(driverLocation['lat']!, driverLocation['lng']!);
    }

    if (startLat != null && startLng != null) {
      return LatLng(startLat, startLng);
    }

    return _fallbackCenter;
  }

  Future<void> _refreshMyLocation() async {
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null || driverId.trim().isEmpty) return;
    await _startLiveTracking(driverId);
  }

  @override
  void dispose() {
    _isDisposed = true;

    _locationSubscription?.cancel();
    _locationSubscription = null;

    try {
      _mapController?.dispose();
    } catch (_) {}

    _mapController = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const DriverBottomNavBar(currentIndex: 1),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pop(context),
              context: context,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Live Trip", style: NavigoTextStyles.titleLarge),
                  SizedBox(height: 2),
                  Text(
                    "Navigate and update progress",
                    style: NavigoTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Expanded(
              child: StreamBuilder<Map<String, dynamic>?>(
                stream: _service.watchLiveTrip(
                  routeId: widget.routeId,
                  tripId: widget.tripId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Failed to load live trip.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: NavigoTextStyles.bodySmall,
                        ),
                      ),
                    );
                  }

                  final data = snapshot.data;
                  if (data == null) {
                    return Center(
                      child: Text(
                        'Trip not found.',
                        style: NavigoTextStyles.bodySmall,
                      ),
                    );
                  }

                  final RouteModel route = data['route'] as RouteModel;
                  final ScheduleSlot slot = data['slot'] as ScheduleSlot;
                  final List<Map<String, dynamic>> passengersSnapshot =
                      List<Map<String, dynamic>>.from(
                        data['passengers'] as List,
                      );
                  final Map<String, double>? driverLocationFallback =
                      _latLngMapFromDynamic(data['driverLocation']);
                  final double? startLat = data['startLat'] as double?;
                  final double? startLng = data['startLng'] as double?;
                  final double? endLat = data['endLat'] as double?;
                  final double? endLng = data['endLng'] as double?;

                  return StreamBuilder<Map<String, double>?>(
                    stream: _service.watchDriverDocumentLocation(slot.driverId),
                    builder: (context, driverGpsSnap) {
                      final Map<String, double>? driverLocation =
                          driverGpsSnap.data ?? driverLocationFallback;

                      return StreamBuilder<List<Map<String, dynamic>>>(
                        stream: _service.watchAssignedPassengerPins(
                          slot.passengersIds,
                        ),
                        builder: (context, passLiveSnap) {
                          final List<Map<String, dynamic>> passengers =
                              passLiveSnap.data ?? passengersSnapshot;

                          final markers = _buildMarkers(
                            driverLocation: driverLocation,
                            passengers: passengers,
                            startLat: startLat,
                            startLng: startLng,
                            endLat: endLat,
                            endLng: endLng,
                          );

                          final polylines = _buildPolylines(
                            startLat: startLat,
                            startLng: startLng,
                            endLat: endLat,
                            endLng: endLng,
                          );

                          final cameraCenter = _cameraCenter(
                            driverLocation: driverLocation,
                            startLat: startLat,
                            startLng: startLng,
                          );

                          final eta = _service.etaText(
                            from:
                                driverLocation ??
                                (startLat != null && startLng != null
                                    ? {'lat': startLat, 'lng': startLng}
                                    : null),
                            toLat: endLat,
                            toLng: endLng,
                          );

                          final passengersWithPin = passengers.where((p) {
                            final lat = p['latitude'];
                            final lng = p['longitude'];
                            return lat is num && lng is num;
                          }).length;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Column(
                              children: [
                                Container(
                                  height: 250,
                                  width: double.infinity,
                                  decoration:
                                      NavigoDecorations.surfaceDecoration(
                                    radius: 22,
                                    bordered: false,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Stack(
                                    children: [
                                      GoogleMap(
                                        initialCameraPosition: CameraPosition(
                                          target: cameraCenter,
                                          zoom: 13.8,
                                        ),
                                        myLocationEnabled: true,
                                        myLocationButtonEnabled: false,
                                        zoomControlsEnabled: false,
                                        markers: markers,
                                        polylines: polylines,
                                        onMapCreated: (controller) {
                                          _mapController = controller;
                                        },
                                      ),
                                      Positioned(
                                        top: 10,
                                        left: 10,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 7,
                                          ),
                                          decoration:
                                              NavigoDecorations
                                                  .surfaceDecoration(
                                            radius: 20,
                                            color: NavigoColors.surfaceWhite
                                                .withOpacity(0.92),
                                            bordered: false,
                                          ),
                                          child: Text(
                                            "Live navigation",
                                            style: NavigoTextStyles.bodySmall
                                                .copyWith(
                                              color: NavigoColors.accentGreen,
                                              fontWeight: FontWeight.w700,
                                              fontStyle: FontStyle.italic,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 10,
                                        right: 10,
                                        child: _isLocating
                                            ? const CircleAvatar(
                                                radius: 18,
                                                backgroundColor:
                                                    NavigoColors.surfaceWhite,
                                                child: SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                              )
                                            : GestureDetector(
                                                onTap: _refreshMyLocation,
                                                child: const CircleAvatar(
                                                  radius: 18,
                                                  backgroundColor:
                                                      NavigoColors.surfaceWhite,
                                                  child: Icon(
                                                    Icons.my_location,
                                                    color: NavigoColors
                                                        .primaryOrange,
                                                    size: 18,
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 12),

                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: NavigoDecorations.kCardDecoration,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              "To: ${_service.toText(route)}",
                                              style: NavigoTextStyles
                                                  .titleSmall
                                                  .copyWith(
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                          NavigoDecorations.statusChip(
                                            label: slot.status.toString(),
                                            color: NavigoColors.accentGreen,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        "ETA: $eta • ${_service.priceText(slot, route)}",
                                        style: NavigoTextStyles.bodyMedium
                                            .copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Divider(
                                        color: NavigoColors.primaryOrange
                                            .withOpacity(0.3),
                                        height: 12,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Path",
                                        style: NavigoTextStyles.bodySmall
                                            .copyWith(
                                          fontWeight: FontWeight.w800,
                                          fontStyle: FontStyle.italic,
                                          color: NavigoColors.accentGreen,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _service.pathText(route),
                                        style: NavigoTextStyles.bodyMedium
                                            .copyWith(
                                          fontWeight: FontWeight.w700,
                                          fontStyle: FontStyle.italic,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Passengers on map: $passengersWithPin / '
                                        '${slot.passengersIds.length}',
                                        style: NavigoTextStyles.bodySmall
                                            .copyWith(
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 14),

                                SizedBox(
                                  width: double.infinity,
                                  height: NavigoSizes.buttonHeight,
                                  child: ElevatedButton(
                                    onPressed:
                                        _isEndingTrip ? null : _endTrip,
                                    style: NavigoDecorations
                                        .kPrimaryButtonLargeStyle,
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
                                            "End Trip",
                                            style: NavigoTextStyles.button,
                                          ),
                                  ),
                                ),

                                const Spacer(),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Map<String, double>? _latLngMapFromDynamic(dynamic v) {
    if (v is! Map) return null;
    final lat = (v['lat'] as num?)?.toDouble();
    final lng = (v['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return {'lat': lat, 'lng': lng};
  }
}
