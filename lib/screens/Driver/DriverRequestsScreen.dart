import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'DriverBottomNavBar.dart';
import 'DriverHomeScreen.dart';

class DriverRequestsScreen extends StatefulWidget {
  const DriverRequestsScreen({super.key});

  @override
  State<DriverRequestsScreen> createState() => _DriverRequestsScreenState();
}

class _DriverRequestsScreenState extends State<DriverRequestsScreen> {
  String searchText = "";
  bool nearbyOnly = false;

  late List<Map<String, dynamic>> requests;

  @override
  void initState() {
    super.initState();
    requests = [
      {
        "passenger": "Cileen",
        "route": "Birzeit → Ramallah",
        "pickup": "Birzeit - Main Gate",
        "dropoff": "Ramallah - Al-Manara",
        "isNearby": true,
      },
      {
        "passenger": "Ahmad",
        "route": "Al-Bireh → Ramallah",
        "pickup": "Al-Bireh - Roundabout",
        "dropoff": "Ramallah - Al-Manara",
        "isNearby": true,
      },
      {
        "passenger": "Rawan",
        "route": "Birzeit → Nablus",
        "pickup": "Birzeit - Campus Gate",
        "dropoff": "Nablus - City Center",
        "isNearby": false,
      },
    ];
  }

  List<Map<String, dynamic>> get filteredRequests {
    return requests.where((request) {
      final passenger = request["passenger"].toString().toLowerCase();
      final pickup = request["pickup"].toString().toLowerCase();
      final dropoff = request["dropoff"].toString().toLowerCase();
      final route = request["route"].toString().toLowerCase();
      final query = searchText.toLowerCase();

      final matchesSearch =
          query.isEmpty ||
          passenger.contains(query) ||
          pickup.contains(query) ||
          dropoff.contains(query) ||
          route.contains(query);

      final matchesNearby = !nearbyOnly || request["isNearby"] == true;

      return matchesSearch && matchesNearby;
    }).toList();
  }

  void _removeRequest(Map<String, dynamic> request, String actionText) {
    setState(() {
      requests.remove(request);
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Request $actionText")));
  }

  Widget buildRequestCard(Map<String, dynamic> request) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: NavigoDecorations.kCardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person,
                color: NavigoColors.accentGreen,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                request["passenger"],
                style: NavigoTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: NavigoColors.textDark,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            request["route"],
            style: NavigoTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: NavigoColors.textDark,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            "Pickup: ${request["pickup"]}",
            style: NavigoTextStyles.bodySmall,
          ),

          const SizedBox(height: 4),

          Text(
            "Drop-off: ${request["dropoff"]}",
            style: NavigoTextStyles.bodySmall,
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    _removeRequest(request, "Declined");
                  },
                  style: NavigoDecorations.coloredButton(
                    NavigoColors.accentRed,
                  ),
                  child: const Text("Decline"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    _removeRequest(request, "Accepted");
                  },
                  style: NavigoDecorations.kPrimaryButtonLargeStyle,
                  child: const Text("Accept"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildNearbyButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          nearbyOnly = !nearbyOnly;
        });
      },
      child: Container(
        height: 45,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: NavigoDecorations.selectorDecoration(
          selected: nearbyOnly,
        ).copyWith(color: nearbyOnly ? null : NavigoColors.lightorange),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.near_me,
              size: 16,
              color: nearbyOnly
                  ? NavigoColors.textLight
                  : NavigoColors.primaryOrange,
            ),
            const SizedBox(width: 5),
            Text(
              "Nearby",
              style: NavigoTextStyles.chip.copyWith(
                color: nearbyOnly
                    ? NavigoColors.textLight
                    : NavigoColors.primaryOrange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const DriverBottomNavBar(currentIndex: 2),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => DriverHomeScreen()),
              ),
              context: context,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text("Trip Requests", style: NavigoTextStyles.titleLarge),
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: NavigoDecorations.kInputDecoration.copyWith(
                        hintText: "Search requests...",
                        prefixIcon: const Icon(
                          Icons.search,
                          color: NavigoColors.accentGreen,
                        ),
                        fillColor: NavigoColors.surfaceWhite,
                      ),
                      onChanged: (value) {
                        setState(() {
                          searchText = value;
                        });
                      },
                    ),
                  ),

                  const SizedBox(width: 10),

                  buildNearbyButton(),
                ],
              ),
            ),

            const SizedBox(height: 18),

            Expanded(
              child: filteredRequests.isEmpty
                  ? Center(
                      child: Text(
                        "No requests found",
                        style: NavigoTextStyles.bodySmall,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredRequests.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, index) {
                        return buildRequestCard(filteredRequests[index]);
                      },
                    ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
