import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../theme/app_theme.dart';
import '../../services/trip_completion_service.dart';
import '../Driver/DriverTripsScreen.dart';
import 'DriverBottomNavBar.dart';
import 'DriverHomeScreen.dart';

class DriverLiveTripScreen extends StatefulWidget {
  const DriverLiveTripScreen({super.key});

  @override
  State<DriverLiveTripScreen> createState() => _DriverLiveTripScreenState();
}

class _DriverLiveTripScreenState extends State<DriverLiveTripScreen> {
  GoogleMapController? _mapController;
  LatLng _initialPosition = const LatLng(31.9038, 35.2034);

  bool _isLocating = false;
  String _driverName = "Driver";

  final Set<Marker> _markers = {
    const Marker(
      markerId: MarkerId("destination"),
      position: LatLng(31.9038, 35.2034),
      infoWindow: InfoWindow(title: "Destination"),
    ),
  };

  final Set<Polyline> _polylines = {
    const Polyline(
      polylineId: PolylineId("trip_route"),
      points: [
        LatLng(31.9545, 35.2123),
        LatLng(31.9390, 35.2060),
        LatLng(31.9205, 35.2039),
        LatLng(31.9038, 35.2034),
      ],
      width: 5,
      color: NavigoColors.primaryOrange,
    ),
  };

  final String destination = "Ramallah – Al-Manara";
  final String eta = "18 min";
  final String price = "3.00";
  final String nextStop = "Al-Bireh – Roundabout";
  final String status = "On time";

  double tripProgress = 0.56;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getUserLocation();
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadDriverData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() => _driverName = "Driver");
        return;
      }
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final firstName = data['firstName'] ?? '';
        final lastName = data['lastName'] ?? '';
        setState(() {
          _driverName = "$firstName $lastName".trim().isEmpty
              ? "Driver"
              : "$firstName $lastName".trim();
        });
      }
    } catch (e) {
      debugPrint("Driver load error: $e");
    }
  }

  Future<void> _getUserLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        return;

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final position =
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception("Location timeout"),
          );

      if (!mounted) return;

      final newPosition = LatLng(position.latitude, position.longitude);
      setState(() {
        _initialPosition = newPosition;
        _markers.add(
          Marker(
            markerId: const MarkerId("driver_location"),
            position: newPosition,
            infoWindow: const InfoWindow(title: "Your Location"),
          ),
        );
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: newPosition, zoom: 14.5),
        ),
      );
    } catch (e) {
      debugPrint("Location error: $e");
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _openFullScreenMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenMapView(
          initialPosition: _initialPosition,
          markers: _markers,
          polylines: _polylines,
        ),
      ),
    );
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
            // ── TOP BAR ─────────────────────────────────────
            NavigoDecorations.topBar(onBack: () => Navigator.pop(context)),

            // ── HEADER ──────────────────────────────────────
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

            // ── REST OF CONTENT ──────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: [
                    // ── MAP ─────────────────────────────────
                    Container(
                      height: 250,
                      width: double.infinity,
                      decoration: NavigoDecorations.surfaceDecoration(
                        radius: 22,
                        bordered: false,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: _initialPosition,
                              zoom: 13.8,
                            ),
                            myLocationEnabled: true,
                            myLocationButtonEnabled: false,
                            zoomControlsEnabled: false,
                            markers: _markers,
                            polylines: _polylines,
                            onMapCreated: (controller) =>
                                _mapController = controller,
                          ),
                          Positioned(
                            top: 10,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: NavigoDecorations.surfaceDecoration(
                                radius: 20,
                                color: NavigoColors.surfaceWhite.withOpacity(
                                  0.92,
                                ),
                                bordered: false,
                              ),
                              child: Text(
                                "Live navigation",
                                style: NavigoTextStyles.bodySmall.copyWith(
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
                            right: 54,
                            child: GestureDetector(
                              onTap: _openFullScreenMap,
                              child: const CircleAvatar(
                                radius: 18,
                                backgroundColor: NavigoColors.surfaceWhite,
                                child: Icon(
                                  Icons.fullscreen,
                                  color: NavigoColors.primaryOrange,
                                  size: 20,
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
                                    backgroundColor: NavigoColors.surfaceWhite,
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : GestureDetector(
                                    onTap: _getUserLocation,
                                    child: const CircleAvatar(
                                      radius: 18,
                                      backgroundColor:
                                          NavigoColors.surfaceWhite,
                                      child: Icon(
                                        Icons.my_location,
                                        color: NavigoColors.primaryOrange,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── TRIP INFO CARD ───────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: NavigoDecorations.kCardDecoration,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "To: $destination",
                                  style: NavigoTextStyles.titleSmall.copyWith(
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                              NavigoDecorations.statusChip(
                                label: status,
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
                            "ETA $eta • $price NIS",
                            style: NavigoTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Divider(
                            color: NavigoColors.primaryOrange.withOpacity(0.3),
                            height: 12,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Next stop",
                            style: NavigoTextStyles.bodySmall.copyWith(
                              fontWeight: FontWeight.w800,
                              fontStyle: FontStyle.italic,
                              color: NavigoColors.accentGreen,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            nextStop,
                            style: NavigoTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                              fontStyle: FontStyle.italic,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              value: tripProgress,
                              minHeight: 7,
                              backgroundColor: NavigoColors.borderLight,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                NavigoColors.primaryOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // ── END TRIP BUTTON ──────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: NavigoSizes.buttonHeight,
                      child: ElevatedButton(
                        onPressed: () async {
                          final uid = FirebaseAuth.instance.currentUser?.uid;
                          if (uid != null) {
                            await TripCompletionService()
                                .releaseDriverAfterTrip(driverId: uid);
                          }
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DriverTripsScreen(),
                            ),
                          );
                        },
                        style: NavigoDecorations.kPrimaryButtonLargeStyle,
                        child: const Text(
                          "End Trip",
                          style: NavigoTextStyles.button,
                        ),
                      ),
                    ),

                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── FULL SCREEN MAP ───────────────────────────────────────────────────────────
class FullScreenMapView extends StatefulWidget {
  final LatLng initialPosition;
  final Set<Marker> markers;
  final Set<Polyline> polylines;

  const FullScreenMapView({
    super.key,
    required this.initialPosition,
    required this.markers,
    required this.polylines,
  });

  @override
  State<FullScreenMapView> createState() => _FullScreenMapViewState();
}

class _FullScreenMapViewState extends State<FullScreenMapView> {
  GoogleMapController? _fullMapController;

  @override
  void dispose() {
    _fullMapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.initialPosition,
              zoom: 14.5,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: false,
            markers: widget.markers,
            polylines: widget.polylines,
            onMapCreated: (controller) => _fullMapController = controller,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: NavigoDecorations.topBar(
                onBack: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
