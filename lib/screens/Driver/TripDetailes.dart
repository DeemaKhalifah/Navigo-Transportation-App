import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/route.dart';
import '../../models/schedule_slot.dart';
import '../../services/driver_trip_details_service.dart';
import '../../services/trip_completion_service.dart';
import '../../theme/app_theme.dart';
import 'DriverBottomNavBar.dart';
import 'DriverLiveTripScreen.dart';

class TripDetailes extends StatelessWidget {
  final Map<String, dynamic> trip;

  const TripDetailes({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final DriverTripDetailsService service = DriverTripDetailsService();

    final String tripId = (trip['tripId'] ?? '').toString().trim();
    final String? routeId = trip['routeId']?.toString();

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
              child: FutureBuilder<Map<String, dynamic>?>(
                future: service.getTripDetails(
                  tripId: tripId,
                  routeId: routeId,
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
                          'Failed to load trip details.\n${snapshot.error}',
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
                  final List<Map<String, dynamic>> passengers =
                      List<Map<String, dynamic>>.from(
                        data['passengers'] as List,
                      );

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NavigoSizes.screenPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: NavigoDecorations.kCardDecoration,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                service.lineText(route),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NavigoTextStyles.titleSmall.copyWith(
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Divider(
                                color: NavigoColors.primaryOrange.withOpacity(
                                  0.3,
                                ),
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
                                  InfoItem(
                                    title: "Trip ID",
                                    value: slot.slotId,
                                  ),
                                  InfoItem(
                                    title: "Vehicle",
                                    value: service.vehicleText(slot),
                                  ),
                                  InfoItem(
                                    title: "Date",
                                    value: service.dateText(slot),
                                  ),
                                  InfoItem(
                                    title: "Time",
                                    value: service.timeText(slot),
                                  ),
                                  InfoItem(
                                    title: "From",
                                    value: route.startPoint,
                                  ),
                                  InfoItem(title: "To", value: route.endPoint),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        Text("Passengers", style: NavigoTextStyles.titleSmall),
                        const SizedBox(height: 10),

                        Expanded(
                          child: passengers.isEmpty
                              ? Center(
                                  child: Text(
                                    'No passengers assigned.',
                                    style: NavigoTextStyles.bodySmall,
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: passengers.length,
                                  separatorBuilder: (_, _) => const SizedBox(
                                    height: NavigoSizes.itemGap,
                                  ),
                                  itemBuilder: (context, index) {
                                    final passenger = passengers[index];
                                    return PassengerTile(
                                      passengerName:
                                          (passenger['name'] ?? 'Passenger')
                                              .toString(),
                                      pickup:
                                          (passenger['pickup'] ??
                                                  route.startPoint)
                                              .toString(),
                                    );
                                  },
                                ),
                        ),

                        const SizedBox(height: 10),

                        SizedBox(
                          width: double.infinity,
                          height: NavigoSizes.buttonHeight,
                          child: ElevatedButton(
                            style: NavigoDecorations.kPrimaryButtonLargeStyle,
                            onPressed: () {
                              final safeTripId = (trip['tripId'] ?? '')
                                  .toString()
                                  .trim();
                              final safeRouteId = (trip['routeId'] ?? '')
                                  .toString()
                                  .trim();

                              if (safeTripId.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Trip ID is missing'),
                                  ),
                                );
                                return;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DriverLiveTripScreen(
                                    tripId: safeTripId,
                                    routeId: safeRouteId,
                                  ),
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InfoItem extends StatelessWidget {
  final String title;
  final String value;

  const InfoItem({super.key, required this.title, required this.value});

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

class PassengerTile extends StatelessWidget {
  final String passengerName;
  final String pickup;

  const PassengerTile({
    super.key,
    required this.passengerName,
    required this.pickup,
  });

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
