import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../controllers/trip_notification_controller.dart';
import '../../models/route.dart';
import '../../models/schedule_slot.dart';
import '../../services/driver_trip_details_service.dart';
import '../../services/driver_live_trip_service.dart';
import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_message.dart';
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
  final TripNotificationController _tripNotificationController =
      TripNotificationController();

  bool _isCancelling = false;
  bool _isStarting = false;
  late Future<Map<String, dynamic>?> _tripDetailsFuture;
  Timer? _clockTick;

  @override
  void initState() {
    super.initState();
    _tripDetailsFuture = _loadTripDetails();
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

  Future<Map<String, dynamic>?> _loadTripDetails() {
    return service.getTripDetails(
      tripId: (widget.trip['tripId'] ?? '').toString().trim(),
      routeId: widget.trip['routeId']?.toString(),
    );
  }

  Future<void> _startTrip(ScheduleSlot slot) async {
    if (_isStarting) return;

    final safeTripId = (widget.trip['tripId'] ?? slot.slotId).toString().trim();
    final safeRouteId = (widget.trip['routeId'] ?? slot.routeId)
        .toString()
        .trim();
    final driverId = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (safeTripId.isEmpty) {
      AppMessage.showError(context, context.texts.t('tripIdMissing'));
      return;
    }

    if (driverId.trim().isEmpty) {
      AppMessage.showError(context, 'Driver ID is missing.');
      return;
    }

    setState(() => _isStarting = true);

    try {
      final isOffline = await _liveTripService.isDriverOffline(driverId);

      if (isOffline) {
        if (!mounted) return;
        setState(() => _isStarting = false);
        await _showOfflineStatusDialog();
        return;
      }

      await _liveTripService.startTrip(
        routeId: safeRouteId,
        tripId: safeTripId,
        driverId: driverId,
      );
    } on OfflineDriverStartTripException {
      if (!mounted) return;
      setState(() => _isStarting = false);
      await _showOfflineStatusDialog();
      return;
    } catch (e) {
      if (!mounted) return;
      AppMessage.showError(context, '${context.texts.t('couldNotStart')}: $e');
      setState(() => _isStarting = false);
      return;
    }

    unawaited(
      _tripNotificationController.notifyPassengersTripStarted(
        routeId: slot.routeId,
        tripId: slot.slotId,
        passengerIds: slot.passengersIds,
      ).catchError((_) {}),
    );

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => DriverHomeScreen(initialActiveSlot: slot),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
      (route) => false,
    );
  }

  Future<void> _showOfflineStatusDialog() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Offline Status'),
        content: const Text(
          'You are currently offline. You cannot start a trip while your status is Offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelTrip() async {
    final driverId = FirebaseAuth.instance.currentUser?.uid;
    if (driverId == null || driverId.trim().isEmpty) return;

    final tripId = (widget.trip['tripId'] ?? '').toString().trim();
    final routeId = (widget.trip['routeId'] ?? '').toString().trim();

    if (tripId.isEmpty) {
      AppMessage.showError(context, context.texts.t('tripIdMissing'));
      return;
    }

    // Confirm with the user
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.texts.t('cancelTrip')),
        content: Text(context.texts.t('cancelTripConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.texts.t('no')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: NavigoColors.accentRed,
            ),
            child: Text(context.texts.t('yesCancelTrip')),
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
      AppMessage.showSuccess(context, context.texts.t('tripCancelledSuccess'));
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverTripsScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      AppMessage.showError(context, '${context.texts.t('failedToCancel')}: $e');
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
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
            NavigoDecorations.topBar(
              onBack: () => Navigator.pop(context),
              context: context,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.texts.t('tripDetails'),
                    style: NavigoTextStyles.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.texts.t('reviewBeforeStarting'),
                    style: NavigoTextStyles.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: FutureBuilder<Map<String, dynamic>?>(
                future: _tripDetailsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          '${context.texts.t('failedToLoadTripDetails')}\n${snapshot.error}',
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
                        context.texts.t('tripNotFound'),
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
                  final startWindow = slot.departureAt.subtract(
                    const Duration(minutes: 30),
                  );
                  // Enable by time window only. Date equality checks can fail
                  // around timezone/day-boundary cases even when the slot is valid.
                  final canStartTrip = !now.isBefore(startWindow);

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
                                    title: context.texts.t('tripIdLabel'),
                                    value: slot.slotId,
                                  ),
                                  InfoItem(
                                    title: context.texts.t('vehicle'),
                                    value: service.vehicleText(slot),
                                  ),
                                  InfoItem(
                                    title: context.texts.t('date'),
                                    value: service.dateText(slot),
                                  ),
                                  InfoItem(
                                    title: context.texts.t('time'),
                                    value: service.timeText(slot),
                                  ),
                                  InfoItem(
                                    title: context.texts.t('from'),
                                    value: route.startPoint,
                                  ),
                                  InfoItem(
                                    title: context.texts.t('to'),
                                    value: route.endPoint,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        Text(
                          context.texts.t('passengers'),
                          style: NavigoTextStyles.titleSmall,
                        ),
                        const SizedBox(height: 10),

                        Expanded(
                          child: passengers.isEmpty
                              ? Center(
                                  child: Text(
                                    context.texts.t('noPassengersAssigned'),
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
                                          (passenger['name'] ??
                                                  context.texts.t('passenger'))
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
                            onPressed: canStartTrip && !_isStarting
                                ? () => _startTrip(slot)
                                : null,
                            child: _isStarting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: NavigoColors.textLight,
                                    ),
                                  )
                                : Text(
                                    context.texts.t('startTrip'),
                                    style: NavigoTextStyles.button,
                                  ),
                          ),
                        ),

                        if (!canStartTrip) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              context.texts.t('canStartBefore'),
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
                                : Text(
                                    context.texts.t('cancelTrip'),
                                    style: NavigoTextStyles.button,
                                  ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        Center(
                          child: Text(
                            context.texts.t('startingSharesLocation'),
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
                  "${context.texts.t('pickup')}: $pickup",
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
