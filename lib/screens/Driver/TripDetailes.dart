import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/trip_completion_service.dart';
import '../../theme/app_theme.dart';
import 'DriverBottomNavBar.dart';
import 'DriverHomeScreen.dart';
import 'DriverLiveTripScreen.dart';

class TripDetailes extends StatelessWidget {
  final Map<String, dynamic> trip;

  const TripDetailes({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final passengers = [
      {"name": "Ahmad Ali", "pickup": "Birzeit - Main Gate"},
      {"name": "Lina Omar", "pickup": "Al-Bireh - Roundabout"},
      {"name": "Celine Hanna", "pickup": "Ramallah - Clock Square"},
    ];

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const DriverBottomNavBar(currentIndex: 1),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── TOP BAR ───────────────────────────────────────
            NavigoDecorations.topBar(onBack: () => Navigator.pop(context)),

            // ── HEADER ────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Trip Details", style: NavigoTextStyles.titleLarge),
                  SizedBox(height: 4),
                  Text(
                    "Review before starting",
                    style: NavigoTextStyles.bodySmall,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NavigoSizes.screenPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── TRIP INFO CARD ─────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: NavigoDecorations.kCardDecoration,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trip["title"] ?? "Birzeit → Ramallah",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NavigoTextStyles.titleSmall.copyWith(
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Divider(
                            color: NavigoColors.primaryOrange.withOpacity(0.3),
                            height: 12,
                          ),
                          GridView.count(
                            shrinkWrap: true,
                            crossAxisCount: 2,
                            childAspectRatio: 9,
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 8,
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _InfoItem(
                                title: "Trip ID",
                                value: trip["tripId"] ?? "T001",
                              ),
                              _InfoItem(
                                title: "Vehicle",
                                value: trip["vehicle"] ?? "Bus",
                              ),
                              _InfoItem(
                                title: "Date",
                                value: trip["date"] ?? "01 Apr 2026",
                              ),
                              _InfoItem(
                                title: "Time",
                                value: trip["time"] ?? "09:50",
                              ),
                              _InfoItem(
                                title: "From",
                                value: trip["from"] ?? "Birzeit",
                              ),
                              _InfoItem(
                                title: "To",
                                value: trip["to"] ?? "Ramallah",
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text("Passengers", style: NavigoTextStyles.titleSmall),
                    const SizedBox(height: 10),

                    // ── PASSENGER LIST ─────────────────────────
                    Expanded(
                      child: ListView.separated(
                        itemCount: passengers.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: NavigoSizes.itemGap),
                        itemBuilder: (context, index) {
                          return _PassengerTile(
                            passengerName: passengers[index]["name"]!,
                            pickup: passengers[index]["pickup"]!,
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ── START TRIP BUTTON ──────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: NavigoSizes.buttonHeight,
                      child: ElevatedButton(
                        style: NavigoDecorations.kPrimaryButtonLargeStyle,
                        onPressed: () async {
                          final uid = FirebaseAuth.instance.currentUser?.uid;
                          if (uid != null) {
                            await TripCompletionService()
                                .markDriverLiveTripStarted(driverId: uid);
                          }
                          if (!context.mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DriverLiveTripScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          "Start Trip",
                          style: NavigoTextStyles.button,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    Center(
                      child: Text(
                        "Starting the trip will share your live location",
                        style: NavigoTextStyles.bodySmall.copyWith(
                          fontSize: 12,
                        ),
                      ),
                    ),

                    const SizedBox(height: NavigoSizes.itemGap),
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

class _InfoItem extends StatelessWidget {
  final String title;
  final String value;

  const _InfoItem({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          "$title: ",
          style: NavigoTextStyles.bodySmall.copyWith(fontSize: 11),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NavigoTextStyles.bodySmall.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: NavigoColors.textDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _PassengerTile extends StatelessWidget {
  final String passengerName;
  final String pickup;

  const _PassengerTile({required this.passengerName, required this.pickup});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: NavigoDecorations.kCardDecoration,
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: NavigoColors.accentGreen,
            child: Icon(Icons.person, color: NavigoColors.textLight),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passengerName,
                  style: NavigoTextStyles.titleSmall.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  "Pickup: $pickup",
                  style: NavigoTextStyles.bodySmall.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
