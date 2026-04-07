import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

import '../../theme/app_theme.dart';
import 'PassengerBottomNavBar.dart';
import '../NotificationsScreen.dart';
import 'ScheduleScreen.dart';
import '../../services/passenger_trip_repository.dart';
import '../../services/local_storage_service.dart';

class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({super.key});

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

  List<String> _lines = [];
  List<String> _filteredLines = [];

  String _userName = "Loading...";

  final Set<Marker> _markers = {};
  BitmapDescriptor? _carIcon;

  int _selectedSeatsCount = 1;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadSavedRoute();
    _loadCarMarker();
    _loadLinesFromFirestore();
    _tripRepository.ensureManualDriverLocations();
    _loadInitialPassengerLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

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

      if (!mounted) return;
      setState(() {
        _initialPosition = newPosition;
        _selectedLocation =
            "${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}";

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
      _selectedLocation =
          "${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}";

      _markers.removeWhere((m) => m.markerId.value == "current_location");
      _markers.add(
        Marker(
          markerId: const MarkerId("current_location"),
          position: location,
          infoWindow: const InfoWindow(title: "My Location"),
        ),
      );
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
                        onPressed: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Trip confirmed with ${driver['name']} for $_selectedSeatsCount seat(s) 🚀",
                              ),
                            ),
                          );
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
      MaterialPageRoute(
        builder: (_) => ScheduleScreen(selectedLine: line),
      ),
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
            onMapCreated: (controller) => _mapController = controller,
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
                          child: IconButton(
                            icon: const Icon(
                              Icons.notifications_none,
                              size: 20,
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const NotificationsScreen(),
                              ),
                            ),
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
                            color: NavigoColors.textMuted,
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
                            color: NavigoColors.textMuted,
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
