import 'package:flutter/material.dart';

import '../../models/schedule_slot.dart';
import '../../models/trip_status.dart';
import '../../services/driver_trips_service.dart';
import '../../theme/app_theme.dart';
import 'DriverBottomNavBar.dart';
import 'DriverHomeScreen.dart';
import 'DriverLiveTripScreen.dart';
import 'TripDetailes.dart';

class DriverTripsScreen extends StatefulWidget {
  const DriverTripsScreen({super.key});

  @override
  State<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends State<DriverTripsScreen> {
  final DriverTripsService _tripsService = DriverTripsService();

  String _filterStatus = TripStatus.all;

  List<ScheduleSlot> _applyFilter(List<ScheduleSlot> trips) {
    if (_filterStatus == TripStatus.all) return trips;

    return trips.where((trip) {
      return _tripsService.statusOf(trip) == _filterStatus;
    }).toList();
  }

  Color _statusColor(String status) {
    switch (TripStatus.normalize(status)) {
      case TripStatus.scheduled:
        return NavigoColors.accentBlue;
      case TripStatus.onTrip:
        return NavigoColors.accentBlue;
      case TripStatus.completed:
        return NavigoColors.accentGreen;
      case TripStatus.cancelled:
        return NavigoColors.accentRed;
      default:
        return NavigoColors.primaryOrange;
    }
  }

  IconData _statusIcon(String status) {
    switch (TripStatus.normalize(status)) {
      case TripStatus.scheduled:
        return Icons.schedule;
      case TripStatus.onTrip:
        return Icons.directions_bus;
      case TripStatus.completed:
        return Icons.check_circle_outline;
      case TripStatus.cancelled:
        return Icons.cancel_outlined;
      default:
        return Icons.directions_bus;
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

  void _openTrip(ScheduleSlot trip) {
    final status = _tripsService.statusOf(trip);

    if (status == TripStatus.scheduled) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TripDetailes(
            trip: {
              'title': _tripsService.lineOf(trip),
              'tripId': trip.slotId,
              'routeId': trip.routeId,
              'vehicle': _tripsService.vehicleTextOf(trip),
              'date': _tripsService.dateTextOf(trip),
              'time': _tripsService.timeTextOf(trip),
              'from': _tripsService.fromOf(trip),
              'to': _tripsService.toOf(trip),
            },
          ),
        ),
      );
      return;
    }

    _showDetails(trip);
  }

  void _showDetails(ScheduleSlot trip) {
    final status = _tripsService.statusOf(trip);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NavigoColors.transparent,
      builder: (_) {
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

              _detailRow('Line', _tripsService.lineOf(trip)),
              _detailRow('Date', _tripsService.dateTextOf(trip)),
              _detailRow('Time', _tripsService.timeTextOf(trip)),
              _detailRow('Price', _tripsService.priceTextOf(trip)),
              _detailRow(
                'Booked Seats',
                _tripsService.bookedSeatsOf(trip).toString(),
              ),
              _detailRow('Vehicle', _tripsService.vehicleTextOf(trip)),

              const SizedBox(height: 20),

              if (status == TripStatus.onTrip)
                SizedBox(width: double.infinity, height: 52),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
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
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const DriverBottomNavBar(currentIndex: 1),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
              ),
              context: context,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
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
                stream: _tripsService.watchDriverTrips(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Failed to load trips.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: NavigoTextStyles.bodySmall,
                        ),
                      ),
                    );
                  }

                  final trips = _applyFilter(snapshot.data ?? []);

                  if (trips.isEmpty) {
                    return Center(
                      child: Text(
                        'No trips found.',
                        style: NavigoTextStyles.bodySmall,
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: trips.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final trip = trips[i];
                      final status = _tripsService.statusOf(trip);

                      return GestureDetector(
                        onTap: () => _openTrip(trip),
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
                                      _tripsService.lineOf(trip),
                                      style: NavigoTextStyles.bodyMedium
                                          .copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: NavigoColors.textDark,
                                            fontSize: 14,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_tripsService.fromOf(trip)}  →  ${_tripsService.toOf(trip)}',
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
                                          '${_tripsService.dateTextOf(trip)}  •  ${_tripsService.timeTextOf(trip)}',
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
