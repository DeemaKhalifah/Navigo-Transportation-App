import 'package:flutter/material.dart';

import '../../models/schedule_slot.dart';
import '../../models/trip_status.dart';
import '../../services/passenger_trip_history_service.dart';
import '../../theme/app_theme.dart';
import '../passenger/PassengerHomeScreen.dart';
import 'PassengerBottomNavBar.dart';
import 'PassengerLiveTrackScreen.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  final PassengerTripHistoryService _historyService =
      PassengerTripHistoryService();

  String _filterStatus = TripStatus.all;

  List<ScheduleSlot> _applyFilter(List<ScheduleSlot> slots) {
    if (_filterStatus == TripStatus.all) return slots;

    return slots.where((slot) {
      return _historyService.statusOf(slot) == _filterStatus;
    }).toList();
  }

  Color _statusColor(String status) {
    switch (TripStatus.normalize(status)) {
      case TripStatus.completed:
        return NavigoColors.accentGreen;
      case TripStatus.cancelled:
        return NavigoColors.accentRed;
      case TripStatus.onTrip:
        return NavigoColors.accentBlue;
      case TripStatus.scheduled:
        return NavigoColors.primaryOrange;
      default:
        return NavigoColors.primaryOrange;
    }
  }

  IconData _statusIcon(String status) {
    switch (TripStatus.normalize(status)) {
      case TripStatus.completed:
        return Icons.check_circle_outline;
      case TripStatus.cancelled:
        return Icons.cancel_outlined;
      case TripStatus.onTrip:
        return Icons.directions_bus;
      case TripStatus.scheduled:
        return Icons.schedule;
      default:
        return Icons.schedule;
    }
  }

  Widget _filterChip({required String label, required String value}) {
    final selected = _filterStatus == value;

    return NavigoDecorations.selectorChip(
      label: label,
      selected: selected,
      onTap: () => setState(() => _filterStatus = value),
    );
  }

  void _showDetails(ScheduleSlot slot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NavigoColors.transparent,
      builder: (_) =>
          _TripHistoryDetailsSheet(slot: slot, historyService: _historyService),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const PassengerBottomNavBar(currentIndex: 2),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const PassengerHomeScreen()),
              ),
              context: context,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('Trip History', style: NavigoTextStyles.titleLarge),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(label: 'All', value: TripStatus.all),
                    const SizedBox(width: 7),
                    _filterChip(
                      label: 'Scheduled',
                      value: TripStatus.scheduled,
                    ),
                    const SizedBox(width: 7),
                    _filterChip(label: 'On Trip', value: TripStatus.onTrip),
                    const SizedBox(width: 7),
                    _filterChip(
                      label: 'Completed',
                      value: TripStatus.completed,
                    ),
                    const SizedBox(width: 7),
                    _filterChip(
                      label: 'Cancelled',
                      value: TripStatus.cancelled,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<ScheduleSlot>>(
                stream: _historyService.watchPassengerTripHistory(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Failed to load trip history.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: NavigoTextStyles.bodySmall,
                        ),
                      ),
                    );
                  }

                  final slots = _applyFilter(snapshot.data ?? []);

                  if (slots.isEmpty) {
                    return Center(
                      child: Text(
                        'No trips found.',
                        style: NavigoTextStyles.bodySmall,
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: slots.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, index) {
                      final slot = slots[index];
                      final status = _historyService.statusOf(slot);

                      return GestureDetector(
                        onTap: () => _showDetails(slot),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: NavigoDecorations.kCardDecoration,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration:
                                    NavigoDecorations.iconCircleDecoration(
                                      _statusColor(status),
                                    ),
                                child: Icon(
                                  _statusIcon(status),
                                  color: _statusColor(status),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _historyService.lineOf(slot),
                                      style: NavigoTextStyles.bodyMedium
                                          .copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: NavigoColors.textDark,
                                            fontSize: 14,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_historyService.fromOf(slot)}  →  ${_historyService.toOf(slot)}',
                                      style: NavigoTextStyles.bodySmall,
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.calendar_today,
                                          size: 13,
                                          color: NavigoColors.textMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${PassengerTripHistoryService.formatDate(slot.departureAt)}  •  ${PassengerTripHistoryService.formatTime(slot.departureAt)}',
                                          style: NavigoTextStyles.bodySmall
                                              .copyWith(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              NavigoDecorations.statusChip(
                                label: TripStatus.label(status),
                                color: _statusColor(status),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
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

class _TripHistoryDetailsSheet extends StatelessWidget {
  const _TripHistoryDetailsSheet({
    required this.slot,
    required this.historyService,
  });

  final ScheduleSlot slot;
  final PassengerTripHistoryService historyService;

  Color _statusColor(String status) {
    switch (TripStatus.normalize(status)) {
      case TripStatus.completed:
        return NavigoColors.accentGreen;
      case TripStatus.cancelled:
        return NavigoColors.accentRed;
      case TripStatus.onTrip:
        return NavigoColors.accentBlue;
      case TripStatus.scheduled:
        return NavigoColors.primaryOrange;
      default:
        return NavigoColors.primaryOrange;
    }
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: NavigoTextStyles.label),
          ),
          Expanded(
            child: Text(
              value,
              style: NavigoTextStyles.bodyMedium.copyWith(
                color: NavigoColors.textDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = historyService.statusOf(slot);

    return Container(
      decoration: NavigoDecorations.kBottomSheetDecoration,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: NavigoDecorations.dragHandle()),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Trip Details', style: NavigoTextStyles.titleSmall),
              NavigoDecorations.statusChip(
                label: TripStatus.label(status),
                color: _statusColor(status),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: NavigoColors.primaryOrange.withOpacity(0.3)),
          const SizedBox(height: 8),
          _row('Slot ID', slot.slotId),
          _row('Route ID', slot.routeId),
          _row('Line', historyService.lineOf(slot)),
          _row('From', historyService.fromOf(slot)),
          _row('To', historyService.toOf(slot)),
          _row(
            'Date',
            PassengerTripHistoryService.formatDate(slot.departureAt),
          ),
          _row(
            'Departure',
            PassengerTripHistoryService.formatTime(slot.departureAt),
          ),
          _row(
            'Arrival',
            PassengerTripHistoryService.formatTime(slot.arrivalAt),
          ),
          _row('Duration', historyService.durationTextOf(slot)),
          _row('Price', historyService.priceTextOf(slot)),
          _row('Seats', slot.capacity.toString()),
          _row('Vehicle', historyService.vehicleTypeTextOf(slot)),
          _row(
            'Driver ID',
            slot.driverId.isEmpty ? 'Not assigned' : slot.driverId,
          ),
          const SizedBox(height: 20),
          if (status == TripStatus.scheduled || status == TripStatus.onTrip)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  if (status == TripStatus.onTrip) {
                    if (slot.driverId.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No driver assigned for this trip yet.'),
                        ),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PassengerLiveTrackScreen(
                          driverId: slot.driverId.trim(),
                          routeId: slot.routeId,
                          slotId: slot.slotId,
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PassengerHomeScreen(),
                    ),
                  );
                },
                style: NavigoDecorations.kPrimaryButtonLargeStyle,
                icon: const Icon(Icons.location_on, size: 20),
                label: Text(
                  status == TripStatus.onTrip
                      ? 'Track Live Trip'
                      : 'View Route',
                  style: NavigoTextStyles.button,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
