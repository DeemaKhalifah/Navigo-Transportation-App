import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../theme/app_theme.dart';
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
        });

    if (uid != null && uid.isNotEmpty) {
      _passengerSub = db
          .collection('passengers')
          .doc(uid)
          .snapshots()
          .listen((snap) {
            if (!mounted) return;
            setState(() => _passengerData = snap.data());
          });
    }
  }

  void _scheduleFollowDriver() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = _mapController;
      final d = _driverLatLng();
      if (c == null || d == null) return;
      c.animateCamera(CameraUpdate.newLatLngZoom(d, 14.2));
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
    return null;
  }

  static LatLng? _latLngFromMap(dynamic location) {
    if (location is! Map) return null;
    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
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
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        ),
      );
    }

    final passPos = _passengerLatLng();
    if (passPos != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('me'),
          position: passPos,
          infoWindow: const InfoWindow(title: 'You', snippet: 'Your pickup'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
      );
    }

    return markers;
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
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Live tracking', style: NavigoTextStyles.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    driverPos == null
                        ? 'Waiting for driver location…'
                        : 'Following driver on the map',
                    style: NavigoTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
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
                        onMapCreated: (controller) {
                          _mapController = controller;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _recenter();
                          });
                        },
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
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
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
