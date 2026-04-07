import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../theme/app_theme.dart';
import 'PassengerBottomNavBar.dart';
import '../NotificationsScreen.dart';
import 'ScheduleScreen.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

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

  final List<String> _lines = [
    'Birzeit <-----> Ramallah',
    'Nablus <-----> Ramallah',
    'Jerusalem <-----> Ramallah',
  ];
  List<String> _filteredLines = [];

  String _userName = "Loading...";

  final Set<Marker> _markers = {};
  BitmapDescriptor? _carIcon;

  int _selectedSeatsCount = 1;

  // ================= EXAMPLE DRIVERS DATA =================
  final List<Map<String, dynamic>> _drivers = [
    {
      'id': 'd1',
      'name': 'Ahmad Khaled',
      'busNumber': 'BUS-101',
      'line': 'Birzeit <-----> Ramallah',
      'from': 'Birzeit',
      'to': 'Ramallah',
      'availableSeats': 4,
      'price': '5 NIS',
      'eta': '6 min',
      'phone': '+970 59 123 4567',
      'vehicleType': 'Bus',
      'lat': 31.9555,
      'lng': 35.2042,
    },
    {
      'id': 'd2',
      'name': 'Omar Naser',
      'busNumber': 'BUS-205',
      'line': 'Birzeit <-----> Ramallah',
      'from': 'Ramallah',
      'to': 'Birzeit',
      'availableSeats': 2,
      'price': '5 NIS',
      'eta': '9 min',
      'phone': '+970 59 987 6543',
      'vehicleType': 'Bus',
      'lat': 31.9528,
      'lng': 35.1988,
    },
    {
      'id': 'd3',
      'name': 'Sami Yousef',
      'busNumber': 'MICRO-11',
      'line': 'Birzeit <-----> Ramallah',
      'from': 'Birzeit',
      'to': 'Ramallah',
      'availableSeats': 6,
      'price': '4 NIS',
      'eta': '3 min',
      'phone': '+970 59 222 3344',
      'vehicleType': 'Microbus',
      'lat': 31.9586,
      'lng': 35.2103,
    },
    {
      'id': 'd4',
      'name': 'Yousef Adel',
      'busNumber': 'BUS-301',
      'line': 'Nablus <-----> Ramallah',
      'from': 'Nablus',
      'to': 'Ramallah',
      'availableSeats': 7,
      'price': '10 NIS',
      'eta': '12 min',
      'phone': '+970 59 332 1111',
      'vehicleType': 'Bus',
      'lat': 32.2200,
      'lng': 35.2544,
    },
    {
      'id': 'd5',
      'name': 'Majd Ali',
      'busNumber': 'MICRO-22',
      'line': 'Nablus <-----> Ramallah',
      'from': 'Ramallah',
      'to': 'Nablus',
      'availableSeats': 3,
      'price': '9 NIS',
      'eta': '8 min',
      'phone': '+970 59 444 5555',
      'vehicleType': 'Microbus',
      'lat': 32.2155,
      'lng': 35.2610,
    },
    {
      'id': 'd6',
      'name': 'Khaled Issa',
      'busNumber': 'BUS-401',
      'line': 'Jerusalem <-----> Ramallah',
      'from': 'Jerusalem',
      'to': 'Ramallah',
      'availableSeats': 5,
      'price': '8 NIS',
      'eta': '15 min',
      'phone': '+970 59 777 8888',
      'vehicleType': 'Bus',
      'lat': 31.7950,
      'lng': 35.2200,
    },
    {
      'id': 'd7',
      'name': 'Fadi Hasan',
      'busNumber': 'MICRO-33',
      'line': 'Jerusalem <-----> Ramallah',
      'from': 'Ramallah',
      'to': 'Jerusalem',
      'availableSeats': 4,
      'price': '7 NIS',
      'eta': '11 min',
      'phone': '+970 59 666 1212',
      'vehicleType': 'Microbus',
      'lat': 31.8050,
      'lng': 35.2350,
    },
  ];

  @override
  void initState() {
    super.initState();
    _filteredLines = List.from(_lines);
    _loadUserData();
    _loadCarMarker();

    Future.delayed(const Duration(milliseconds: 500), () {
      _getUserLocation();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  // ================= USER DATA =================
  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        setState(() => _userName = "Guest");
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

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
      setState(() => _userName = "Guest");
    }
  }

  // ================= IMAGE MARKER =================
  Future<void> _loadCarMarker() async {
    try {
      final ByteData data = await rootBundle.load('assets/images/logo.png');
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 80, // same pixel width as a default pin
        targetHeight: 90, // same pixel height as a default pin
      );
      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? byteData = await fi.image.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        setState(() {
          _carIcon = BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
        });
      }
    } catch (e) {
      debugPrint("Car marker load error: $e");
    }
  }

  // ================= LOCATION =================
  Future<void> _getUserLocation() async {
    if (_isLocating) return;

    setState(() => _isLocating = true);

    try {
      // ✅ Step 1: check service
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enable location services")),
        );
        return;
      }

      // ✅ Step 2: check permission safely
      LocationPermission permission;

      try {
        permission = await Geolocator.checkPermission();
      } catch (e) {
        debugPrint("Permission check error: $e");
        return;
      }

      // ✅ Step 3: request permission ONLY if needed
      if (permission == LocationPermission.denied) {
        try {
          permission = await Geolocator.requestPermission();
        } catch (e) {
          debugPrint("Permission request error: $e");
          return;
        }
      }

      // ❌ still denied
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied")),
        );
        return;
      }

      // ❌ permanently denied
      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Enable location permission from settings"),
          ),
        );
        await Geolocator.openAppSettings();
        return;
      }

      // ✅ Step 4: get location
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final LatLng newPosition = LatLng(position.latitude, position.longitude);

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
    } catch (e) {
      debugPrint("Location error: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error getting location")));
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  // ================= FILTER LINES =================
  void _filterLines(String query) {
    setState(() {
      _filteredLines = _lines
          .where((line) => line.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  // ================= FILTER DRIVERS BY LINE =================
  List<Map<String, dynamic>> _getFilteredDrivers() {
    if (_selectedLine == null || _selectedLine!.trim().isEmpty) {
      return _drivers;
    }

    return _drivers.where((driver) {
      return driver['line'] == _selectedLine;
    }).toList();
  }

  // ================= SHOW DRIVERS NOW =================
  void _showDriversNow() {
    final filteredDrivers = _getFilteredDrivers();

    if (filteredDrivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No vehicles found for this line")),
      );
      return;
    }

    final Set<Marker> driverMarkers = filteredDrivers.map((driver) {
      return Marker(
        markerId: MarkerId(driver['id']),
        position: LatLng(driver['lat'], driver['lng']),
        icon:
            _carIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: driver['name'],
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
        CameraPosition(target: LatLng(first['lat'], first['lng']), zoom: 12.8),
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
                            driver['name'],
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
                      driver['busNumber'],
                    ),
                    _tripInfoRow(
                      Icons.directions_bus,
                      "Type",
                      driver['vehicleType'],
                    ),
                    _tripInfoRow(Icons.route, "Line", driver['line']),
                    _tripInfoRow(
                      Icons.event_seat,
                      "Available seats",
                      "${driver['availableSeats']}",
                    ),
                    _tripInfoRow(Icons.phone, "Phone", driver['phone']),

                    const SizedBox(height: 18),

                    /// 🔥 NUMBER OF SEATS (INLINE + FIXED STYLE)
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
                                      color: Colors.black, // ✅ FIXED BLACK TEXT
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

                    /// 🔥 EXTRA SPACE BEFORE BUTTON
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

  // ================= NAVIGATION =================
  void _openScheduleTrip() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScheduleScreen()),
    );
  }

  // ================= BUILD =================
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
                                    hintText: "Search or select a line",
                                    filled: true,
                                    fillColor: NavigoColors.surfaceWhite,
                                    prefixIcon: const Icon(
                                      Icons.search,
                                      color: NavigoColors.accentGreen,
                                    ),
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
                                  maxHeight: 150,
                                ),
                                decoration: BoxDecoration(
                                  color: NavigoColors.surfaceWhite,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _filteredLines.length,
                                  itemBuilder: (context, index) {
                                    return ListTile(
                                      title: Text(_filteredLines[index]),
                                      onTap: () {
                                        setState(() {
                                          _selectedLine = _filteredLines[index];
                                          _searchController.text =
                                              _selectedLine!;
                                          _filteredLines = [];
                                        });
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
                            onPressed: _openScheduleTrip,
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
