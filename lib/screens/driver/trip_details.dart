import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/route.dart';
import '../../models/schedule_slot.dart';
import '../../services/driver_trip_details_service.dart';
import '../../services/driver_live_trip_service.dart';
import '../../theme/app_theme.dart';
import 'driver_home_screen.dart';
import 'driver_bottom_nav_bar.dart';
import 'driver_trips_screen.dart';

class TripDetailes extends StatefulWidget {
  final Map<String, dynamic> trip;

  const TripDetailes({super.key, required this.trip});

  @override
  State<TripDetailes> createState() => _TripDetailesState();
}

class _TripDetailesState extends State<TripDetailes> {
  final DriverTripDetailsService service = DriverTripDetailsService();
  final DriverLiveTripService _liveTripService = DriverLiveTripService();
  bool _isCancelling = false;
  Timer? _clockTick;

  @override
  void initState() {
    super.initState();
    // Refresh UI so the "Start Trip" button enables itself
    // when the allowed window is reached.
    _clockTick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clockTick?.cancel();
    super.dispose();
  }

  Future<void> _cancelTrip() async {
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null || driverId.trim().isEmpty) return;

    final tripId = (widget.trip['tripId'] ?? '').toString().trim();
    final routeId = (widget.trip['routeId'] ?? '').toString().trim();

    if (tripId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Trip ID is missing')));
      return;
    }

    // Confirm with the user
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Trip'),
        content: const Text(
          'Are you sure you want to cancel this trip? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: NavigoColors.accentRed,
            ),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);

    try {
      await _liveTripService.cancelTrip(
        routeId: routeId,
        tripId: tripId,
        driverId: driverId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip cancelled successfully')),
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverTripsScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to cancel: $e')));
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final String tripId = (widget.trip['tripId'] ?? '').toString().trim();
    final String? routeId = widget.trip['routeId']?.toString();

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

                  final now = DateTime.now();
                  final startWindow =
                      slot.departureAt.subtract(const Duration(minutes: 30));
                  final isSameDate =
                      now.year == slot.departureAt.year &&
                      now.month == slot.departureAt.month &&
                      now.day == slot.departureAt.day;
                  final canStartTrip = isSameDate && !now.isBefore(startWindow);

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
                                  separatorBuilder: (_, __) => const SizedBox(
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

                        // Start Trip button
                        SizedBox(
                          width: double.infinity,
                          height: NavigoSizes.buttonHeight,
                          child: ElevatedButton(
                            style: NavigoDecorations.kPrimaryButtonLargeStyle,
                            onPressed: canStartTrip
                                ? () async {
                              final safeTripId = (widget.trip['tripId'] ?? '')
                                  .toString()
                                  .trim();
                              final safeRouteId = (widget.trip['routeId'] ?? '')
                                  .toString()
                                  .trim();
                              final driverId =
                                  FirebaseAuth.instance.currentUser?.uid ?? '';

                              if (safeTripId.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Trip ID is missing'),
                                  ),
                                );
                                return;
                              }

                              try {
                                await _liveTripService.startTrip(
                                  routeId: safeRouteId,
                                  tripId: safeTripId,
                                  driverId: driverId,
                                );
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Could not start: $e'),
                                  ),
                                );
                                return;
                              }

                              if (!context.mounted) return;
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const DriverHomeScreen(),
                                ),
                                (route) => false,
                              );
                            }
                                : null,
                            child: const Text(
                              "Start Trip",
                              style: NavigoTextStyles.button,
                            ),
                          ),
                        ),

                        if (!canStartTrip) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              "You can start this trip 30 minutes before departure.",
                              textAlign: TextAlign.center,
                              style: NavigoTextStyles.bodySmall.copyWith(
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),

                        // Cancel Trip button (red)
                        SizedBox(
                          width: double.infinity,
                          height: NavigoSizes.buttonHeight,
                          child: ElevatedButton(
                            onPressed: _isCancelling ? null : _cancelTrip,
                            style: NavigoDecorations.kPrimaryButtonLargeStyle
                                .copyWith(
                                  backgroundColor: const WidgetStatePropertyAll(
                                    NavigoColors.accentRed,
                                  ),
                                ),
                            child: _isCancelling
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: NavigoColors.textLight,
                                    ),
                                  )
                                : const Text(
                                    "Cancel Trip",
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
