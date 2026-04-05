import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../theme/app_theme.dart';
import 'schedulescreen.dart';
import 'PassengerBottomNavBar.dart';
import '../NotificationsScreen.dart';

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
  bool _isLocating = false;

  final List<String> _lines = ['Birzeit <-----> Ramallah'];
  List<String> _filteredLines = [];

  // ✅ USER DATA
  String _userName = "Loading...";

  @override
  void initState() {
    super.initState();
    _filteredLines = List.from(_lines);

    _loadUserData(); // ✅ load user

    WidgetsBinding.instance.addPostFrameCallback((_) {
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
        });
      } else {
        setState(() => _userName = "Guest");
      }
    } catch (e) {
      debugPrint("User load error: $e");
      setState(() => _userName = "Guest");
    }
  }

  // ================= LOCATION =================
  Future<void> _getUserLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      Position position =
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception("Location timeout"),
          );

      if (!mounted) return;

      final newPosition = LatLng(position.latitude, position.longitude);
      setState(() => _initialPosition = newPosition);
      _mapController?.animateCamera(CameraUpdate.newLatLng(newPosition));
    } catch (e) {
      debugPrint("Location error: $e");
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  // ================= SEARCH =================
  void _filterLines(String query) {
    setState(() {
      _filteredLines = _lines
          .where((line) => line.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  // ================= NAVIGATION =================
  void _openSchedule() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScheduleScreen(selectedLine: _selectedLine),
      ),
    );
  }

  void _confirmRide() {
    if (_selectedLine == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please select a line")));
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Ride Confirmed 🚀")));
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const PassengerBottomNavBar(currentIndex: 0),
      body: Stack(
        children: [
          // ── MAP ──────────────────────────────────────────
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialPosition,
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (controller) => _mapController = controller,
          ),

          // ── TOP UI ───────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ── HEADER ───────────────────────────────
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

                  // ── SEARCH + LOCATION ─────────────────────
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

          // ── BOTTOM PANEL ─────────────────────────────────
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
                      Text(
                        "Line: ${_selectedLine ?? 'Not selected'}",
                        style: NavigoTextStyles.bodyMedium.copyWith(
                          color: NavigoColors.textMuted,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _confirmRide,
                      style: NavigoDecorations.kPrimaryButtonLargeStyle,
                      child: const Text(
                        "Confirm Ride",
                        style: NavigoTextStyles.button,
                      ),
                    ),
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
