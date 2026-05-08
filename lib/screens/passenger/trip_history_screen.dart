import 'package:flutter/material.dart';

import '../../localization/localization_x.dart';
import '../../models/schedule_slot.dart';
import '../../models/trip_status.dart';
import '../../services/passenger_trip_history_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_message.dart';
import 'passenger_home_screen.dart';
import 'passenger_bottom_nav_bar.dart';

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

  String _localizedStatus(String status) {
    switch (TripStatus.normalize(status)) {
      case TripStatus.scheduled:
        return context.texts.t('scheduled');
      case TripStatus.completed:
        return context.texts.t('completed');
      case TripStatus.cancelled:
        return context.texts.t('cancelled');
      case TripStatus.onTrip:
        return context.texts.t('onTrip');
      case TripStatus.all:
        return context.texts.t('all');
      default:
        return context.texts.t('scheduled');
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
              child: Text(
                context.texts.t('tripHistory'),
                style: NavigoTextStyles.titleLarge,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(
                      label: context.texts.t('all'),
                      value: TripStatus.all,
                    ),
                    const SizedBox(width: 7),
                    _filterChip(
                      label: context.texts.t('scheduled'),
                      value: TripStatus.scheduled,
                    ),
                    const SizedBox(width: 7),
                    _filterChip(
                      label: context.texts.t('onTrip'),
                      value: TripStatus.onTrip,
                    ),
                    const SizedBox(width: 7),
                    _filterChip(
                      label: context.texts.t('completed'),
                      value: TripStatus.completed,
                    ),
                    const SizedBox(width: 7),
                    _filterChip(
                      label: context.texts.t('cancelled'),
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
                          '${context.texts.t('failedToLoadTrips')}\n${snapshot.error}',
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
                        context.texts.t('noTripsFound'),
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
                                label: _localizedStatus(status),
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

// ── Simplified Trip Details Bottom Sheet ─────────────────────────────────────
class _TripHistoryDetailsSheet extends StatefulWidget {
  const _TripHistoryDetailsSheet({
    required this.slot,
    required this.historyService,
  });

  final ScheduleSlot slot;
  final PassengerTripHistoryService historyService;

  @override
  State<_TripHistoryDetailsSheet> createState() =>
      _TripHistoryDetailsSheetState();
}

class _TripHistoryDetailsSheetState extends State<_TripHistoryDetailsSheet> {
  String _plateNumber = '...';
  String _driverPhone = '...';
  bool _loadingDriverInfo = true;

  @override
  void initState() {
    super.initState();
    _fetchDriverInfo();
  }

  Future<void> _fetchDriverInfo() async {
    final info = await widget.historyService.getDriverInfo(
      widget.slot.driverId,
    );
    if (!mounted) return;
    setState(() {
      _plateNumber = info['plateNumber'] ?? 'N/A';
      _driverPhone = info['phone'] ?? 'N/A';
      _loadingDriverInfo = false;
    });
  }

  String _localizedStatus(String status) {
    switch (TripStatus.normalize(status)) {
      case TripStatus.scheduled:
        return context.texts.t('scheduled');
      case TripStatus.completed:
        return context.texts.t('completed');
      case TripStatus.cancelled:
        return context.texts.t('cancelled');
      case TripStatus.onTrip:
        return context.texts.t('onTrip');
      case TripStatus.all:
        return context.texts.t('all');
      default:
        return context.texts.t('scheduled');
    }
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

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
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
    final status = widget.historyService.statusOf(widget.slot);

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
              Text(
                context.texts.t('tripDetails'),
                style: NavigoTextStyles.titleSmall,
              ),
              NavigoDecorations.statusChip(
                label: _localizedStatus(status),
                color: _statusColor(status),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: NavigoColors.primaryOrange.withOpacity(0.3)),
          const SizedBox(height: 8),

          // Only show: Line, Date, Departure, Arrival, Vehicle, Plate Number, Driver Phone
          _row(
            context.texts.t('line'),
            widget.historyService.lineOf(widget.slot),
          ),
          _row(
            context.texts.t('date'),
            PassengerTripHistoryService.formatDate(widget.slot.departureAt),
          ),
          _row(
            context.texts.t('departure'),
            PassengerTripHistoryService.formatTime(widget.slot.departureAt),
          ),
          _row(
            context.texts.t('arrival'),
            PassengerTripHistoryService.formatTime(widget.slot.arrivalAt),
          ),
          _row(
            context.texts.t('vehicle'),
            widget.historyService.vehicleTypeTextOf(widget.slot),
          ),
          _row(
            context.texts.t('vehiclePlateNo'),
            _loadingDriverInfo ? '...' : _plateNumber,
          ),
          _row(
            context.texts.t('driverPhone'),
            _loadingDriverInfo ? '...' : _driverPhone,
          ),

          const SizedBox(height: 20),

          // "View Route" button for scheduled trips
          if (status == TripStatus.scheduled)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  final startPoint = widget.historyService.fromOf(widget.slot);
                  final endPoint = widget.historyService.toOf(widget.slot);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PassengerHomeScreen(
                        routeId: widget.slot.routeId,
                        routeStartPoint: startPoint,
                        routeEndPoint: endPoint,
                      ),
                    ),
                  );
                },
                style: NavigoDecorations.kPrimaryButtonLargeStyle,
                icon: const Icon(Icons.route, size: 20),
                label: Text(
                  context.texts.t('viewRoute'),
                  style: NavigoTextStyles.button,
                ),
              ),
            ),

          // "Track Live Trip" button for on-trip trips
          if (status == TripStatus.onTrip)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  if (widget.slot.driverId.trim().isEmpty) {
                    AppMessage.showError(
                      context,
                      context.texts.t('noDriverAssigned'),
                    );
                    return;
                  }
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PassengerHomeScreen(
                        trackDriverId: widget.slot.driverId.trim(),
                      ),
                    ),
                  );
                },
                style: NavigoDecorations.kPrimaryButtonLargeStyle,
                icon: const Icon(Icons.gps_fixed, size: 20),
                label: Text(
                  context.texts.t('trackLiveTrip'),
                  style: NavigoTextStyles.button,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
