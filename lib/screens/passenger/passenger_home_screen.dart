import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

import '../../theme/app_theme.dart';
import 'passenger_bottom_nav_bar.dart';
import '../notifications_screen.dart';
import 'schedule_screen.dart';
import '../../services/passenger_trip_repository.dart';
import '../../services/local_storage_service.dart';
import '../../services/trip_driver_request_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/notification_service.dart';

class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({
    super.key,
    this.routeStartPoint,
    this.routeEndPoint,
    this.trackDriverId,
  });

  /// When provided, a polyline is drawn between these two points (View Route).
  final String? routeStartPoint;
  final String? routeEndPoint;

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

  List<String> _lines = [];
  List<String> _filteredLines = [];

  String _userName = "Loading...";

  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  BitmapDescriptor? _carIcon;

  int _selectedSeatsCount = 1;

  // ── Live tracking state ──────────────────────────────────────────────────
  StreamSubscription<DocumentSnapshot>? _liveDriverSub;
  bool _isLiveTracking = false;
  String? _trackingDriverId;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadSavedRoute();
    _loadCarMarker();
    _loadLinesFromFirestore();
    _loadInitialPassengerLocation();

    // Handle View Route if parameters are set
    if (widget.routeStartPoint != null && widget.routeEndPoint != null) {
      _drawRoutePolyline(widget.routeStartPoint!, widget.routeEndPoint!);
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
    _liveDriverSub?.cancel();
    super.dispose();
  }

  // ── Draw Route Polyline ──────────────────────────────────────────────────
  Future<void> _drawRoutePolyline(String startPoint, String endPoint) async {
    final startLatLng = await GeocodingService.geocodeAddress(startPoint);
    final endLatLng = await GeocodingService.geocodeAddress(endPoint);

    if (!mounted) return;

    if (startLatLng == null || endLatLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not geocode route points')),
      );
      return;
    }

    setState(() {
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route_line'),
          points: [startLatLng, endLatLng],
          color: NavigoColors.primaryOrange,
          width: 4,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
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
          position: startLatLng,
          infoWindow: InfoWindow(title: 'Start', snippet: startPoint),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );
      _markers.add(
        Marker(
          markerId: const MarkerId('route_end'),
          position: endLatLng,
          infoWindow: InfoWindow(title: 'End', snippet: endPoint),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    });

    // Zoom to fit both points
    _fitBounds(startLatLng, endLatLng);
  }

  void _fitBounds(LatLng a, LatLng b) {
    final c = _mapController;
    if (c == null) return;

    final south =
        a.latitude < b.latitude ? a.latitude : b.latitude;
    final north =
        a.latitude > b.latitude ? a.latitude : b.latitude;
    final west =
        a.longitude < b.longitude ? a.longitude : b.longitude;
    final east =
        a.longitude > b.longitude ? a.longitude : b.longitude;

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
      _trackingDriverId = driverId;
    });

    _liveDriverSub = db
        .collection('drivers')
        .doc(driverId)
        .snapshots()
        .listen((snap) {
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

          setState(() {
            _markers.removeWhere((m) => m.markerId.value == 'live_driver');
            _markers.add(
              Marker(
                markerId: const MarkerId('live_driver'),
                position: driverPos!,
                infoWindow: const InfoWindow(
                  title: 'Driver',
                  snippet: 'Live location',
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
      _trackingDriverId = null;
      _markers.removeWhere((m) => m.markerId.value == 'live_driver');
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
        _filteredLines = List.from(lines);
      });

      debugPrint('Loaded route lines: $_lines');
    } catch (e) {
      debugPrint("Routes load error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to load routes: $e")));
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
      });
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
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enable location services")),
        );
        return;
      }

      LocationPermission permission;
      try {
        permission = await Geolocator.checkPermission();
      } catch (e) {
        debugPrint("Permission check error: $e");
        return;
      }

      if (permission == LocationPermission.denied) {
        try {
          permission = await Geolocator.requestPermission();
        } catch (e) {
          debugPrint("Permission request error: $e");
          return;
        }
      }

      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied")),
        );
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Enable location permission from settings"),
          ),
        );
        await Geolocator.openAppSettings();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final newPosition = LatLng(position.latitude, position.longitude);

      // Reverse-geocode to area name
      final areaName = await GeocodingService.reverseGeocodeLabel(newPosition);

      if (!mounted) return;
      setState(() {
        _initialPosition = newPosition;
        _selectedLocation = areaName;

        _markers.removeWhere((m) => m.markerId.value == "current_location");
        _markers.add(
          Marker(
            markerId: const MarkerId("current_location"),
            position: newPosition,
            infoWindow: const InfoWindow(title: "My Location"),
          ),
        );
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: newPosition, zoom: 15.5),
        ),
      );

      await _tripRepository.savePassengerLocation(newPosition);
    } catch (e) {
      debugPrint("Location error: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Error getting location")));
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  void _setSelectedLocation(LatLng location, {bool saveToFirestore = true}) {
    if (!mounted) return;

    setState(() {
      _initialPosition = location;
      // Show loading text while geocoding
      _selectedLocation = 'Loading area name...';

      _markers.removeWhere((m) => m.markerId.value == "current_location");
      _markers.add(
        Marker(
          markerId: const MarkerId("current_location"),
          position: location,
          infoWindow: const InfoWindow(title: "My Location"),
        ),
      );
    });

    // Reverse-geocode asynchronously
    GeocodingService.reverseGeocodeLabel(location).then((areaName) {
      if (!mounted) return;
      setState(() => _selectedLocation = areaName);
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: location, zoom: 15.5),
      ),
    );

    if (saveToFirestore) {
      _tripRepository.savePassengerLocation(location);
    }
  }

  void _filterLines(String query) {
    final trimmed = query.trim().toLowerCase();

    setState(() {
      if (trimmed.isEmpty) {
        _filteredLines = List.from(_lines);
      } else {
        _filteredLines = _lines.where((line) {
          return line.toLowerCase().contains(trimmed);
        }).toList();
      }
    });
  }

  Future<void> _showDriversNow() async {
    final hasLine = _selectedLine != null && _selectedLine!.trim().isNotEmpty;

    final filteredDrivers = hasLine
        ? await _tripRepository.getDriversForLine(_selectedLine!)
        : await _tripRepository.getAllDrivers();

    if (!mounted) return;

    if (filteredDrivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No vehicles found for this line")),
      );
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
                      "Vehicle",
                      driver['busNumber'] as String,
                    ),
                    _tripInfoRow(
                      Icons.directions_bus,
                      "Type",
                      driver['vehicleType'] as String,
                    ),
                    _tripInfoRow(Icons.route, "Line", driver['line'] as String),
                    _tripInfoRow(
                      Icons.event_seat,
                      "Available seats",
                      "${driver['availableSeats']}",
                    ),
                    _tripInfoRow(
                      Icons.phone,
                      "Phone",
                      driver['phone'] as String,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Text(
                          "Number of seats",
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
                          final messenger = ScaffoldMessenger.of(this.context);
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
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Request sent to ${driver['name']}. '
                                  'The driver can accept or decline in Requests.',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!this.context.mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString().replaceFirst('Exception: ', ''),
                                ),
                              ),
                            );
                          }
                        },
                        style: NavigoDecorations.kPrimaryButtonLargeStyle,
                        child: const Text(
                          "Confirm Trip",
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a line first")),
      );
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
                    _fitBounds(points.first, points.last);
                  });
                }
              }
            },
            onTap: (latLng) => _setSelectedLocation(latLng),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  NavigoDecorations.homeStyleTitleBar(
                    title: "Hello, $_userName",
                    subtitle: "Where would you like to go?",
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
                  const SizedBox(height: 14),
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
                                        ? "Loading routes..."
                                        : "Search or select a route",
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
                                                      _filteredLines =
                                                          List.from(_lines);
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
                            if (_filteredLines.isNotEmpty &&
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
                                        });
                                        await LocalStorageService.saveSelectedLine(
                                          line,
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _isLocating
                          ? const CircularProgressIndicator()
                          : FloatingActionButton.small(
                              backgroundColor: NavigoColors.primaryOrange,
                              onPressed: _getUserLocation,
                              child: const Icon(Icons.my_location),
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
              top: 180,
              left: 16,
              right: 16,
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
                    const Icon(
                      Icons.gps_fixed,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Tracking driver live…',
                        style: TextStyle(
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
                        child: const Text(
                          'Stop',
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

          // ── Route view banner ─────────────────────────────────────────────
          if (_polylines.isNotEmpty && !_isLiveTracking)
            Positioned(
              top: 180,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: NavigoColors.primaryOrange,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 8),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.route, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${widget.routeStartPoint ?? ''} → ${widget.routeEndPoint ?? ''}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _polylines.clear();
                          _markers.removeWhere(
                            (m) =>
                                m.markerId.value == 'route_start' ||
                                m.markerId.value == 'route_end',
                          );
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Close',
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

          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: NavigoColors.lightorange,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(25),
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 16),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
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
                          "Line: ${_selectedLine ?? 'Not selected'}",
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
                          "Location: ${_selectedLocation ?? 'Not selected'}",
                          style: NavigoTextStyles.bodyMedium.copyWith(
                            color: NavigoColors.textDark,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _showDriversNow,
                            style: NavigoDecorations.kPrimaryButtonLargeStyle,
                            child: const Text(
                              "Now",
                              style: NavigoTextStyles.button,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: () => _openScheduleTrip(),
                            style: NavigoDecorations.kPrimaryButtonLargeStyle,
                            child: const Text(
                              "Schedule a trip",
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
          ),
        ],
      ),
    );
  }
}
