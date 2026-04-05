import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'DriverBottomNavBar.dart';
import 'DriverHomeScreen.dart';
import 'DriverLiveTripScreen.dart';
import 'TripDetailes.dart';

enum DriverTripStatus { upcoming, ongoing, completed, cancelled }

class DriverTrip {
  final String id;
  final String line;
  final String from;
  final String to;
  final String date;
  final String time;
  final String duration;
  final String price;
  final int seats;
  final String vehicleType;
  final DriverTripStatus status;

  const DriverTrip({
    required this.id,
    required this.line,
    required this.from,
    required this.to,
    required this.date,
    required this.time,
    required this.duration,
    required this.price,
    required this.seats,
    required this.vehicleType,
    required this.status,
  });
}

const List<DriverTrip> _trips = [
  DriverTrip(
    id: 'T001',
    line: 'Birzeit ↔ Ramallah (Line 12)',
    from: 'Birzeit - Main Gate',
    to: 'Ramallah - Al-Manara',
    date: '10 Apr 2025',
    time: '09:30',
    duration: '20 min',
    price: '6.00 NIS',
    seats: 1,
    vehicleType: 'Bus',
    status: DriverTripStatus.upcoming,
  ),
  DriverTrip(
    id: 'T002',
    line: 'Birzeit ↔ Ramallah (Line 12)',
    from: 'Birzeit - Main Gate',
    to: 'Ramallah - Al-Manara',
    date: '01 Apr 2026',
    time: '09:50',
    duration: '20 min',
    price: '6.00 NIS',
    seats: 1,
    vehicleType: 'Bus',
    status: DriverTripStatus.ongoing,
  ),
  DriverTrip(
    id: 'T003',
    line: 'Birzeit ↔ Ramallah (Line 12)',
    from: 'Birzeit - Main Gate',
    to: 'Ramallah - Al-Manara',
    date: '01 Apr 2026',
    time: '09:50',
    duration: '20 min',
    price: '6.00 NIS',
    seats: 1,
    vehicleType: 'Bus',
    status: DriverTripStatus.completed,
  ),
  DriverTrip(
    id: 'T004',
    line: 'Birzeit ↔ Ramallah (Line 12)',
    from: 'Birzeit - Main Gate',
    to: 'Ramallah - Al-Manara',
    date: '01 Apr 2026',
    time: '09:50',
    duration: '20 min',
    price: '6.00 NIS',
    seats: 1,
    vehicleType: 'Bus',
    status: DriverTripStatus.cancelled,
  ),
];

class DriverTripsScreen extends StatefulWidget {
  const DriverTripsScreen({super.key});

  @override
  State<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends State<DriverTripsScreen> {
  DriverTripStatus? _filterStatus;

  List<DriverTrip> get _filtered => _filterStatus == null
      ? _trips
      : _trips.where((trip) => trip.status == _filterStatus).toList();

  Color _statusColor(DriverTripStatus status) {
    switch (status) {
      case DriverTripStatus.upcoming:
        return NavigoColors.accentBlue;
      case DriverTripStatus.ongoing:
        return NavigoColors.primaryOrange;
      case DriverTripStatus.completed:
        return NavigoColors.accentGreen;
      case DriverTripStatus.cancelled:
        return NavigoColors.accentRed;
    }
  }

  String _statusLabel(DriverTripStatus status) {
    switch (status) {
      case DriverTripStatus.upcoming:
        return 'Upcoming';
      case DriverTripStatus.ongoing:
        return 'Ongoing';
      case DriverTripStatus.completed:
        return 'Completed';
      case DriverTripStatus.cancelled:
        return 'Cancelled';
    }
  }

  IconData _statusIcon(DriverTripStatus status) {
    switch (status) {
      case DriverTripStatus.upcoming:
        return Icons.schedule;
      case DriverTripStatus.ongoing:
        return Icons.directions_bus;
      case DriverTripStatus.completed:
        return Icons.check_circle_outline;
      case DriverTripStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  void _openTrip(DriverTrip trip) {
    if (trip.status == DriverTripStatus.upcoming) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TripDetailes(
            trip: {
              'title': trip.line,
              'tripId': trip.id,
              'vehicle': trip.vehicleType,
              'date': trip.date,
              'time': trip.time,
              'from': trip.from,
              'to': trip.to,
            },
          ),
        ),
      );
      return;
    }
    if (trip.status == DriverTripStatus.ongoing) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DriverLiveTripScreen()),
      );
      return;
    }
    _showDetails(trip);
  }

  void _showDetails(DriverTrip trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NavigoColors.transparent,
      builder: (_) => _DriverTripDetailSheet(trip: trip),
    );
  }

  // ── FILTER CHIP ───────────────────────────────────────────────────────────
  Widget _filterChip({
    required String label,
    required DriverTripStatus? value,
  }) {
    final selected = _filterStatus == value;
    return NavigoDecorations.selectorChip(
      label: label,
      selected: selected,
      onTap: () => setState(() => _filterStatus = value),
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
                MaterialPageRoute(builder: (_) => DriverHomeScreen()),
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
                    _filterChip(label: 'All', value: null),
                    const SizedBox(width: 7),
                    _filterChip(
                      label: 'Upcoming',
                      value: DriverTripStatus.upcoming,
                    ),
                    const SizedBox(width: 7),
                    _filterChip(
                      label: 'Ongoing',
                      value: DriverTripStatus.ongoing,
                    ),
                    const SizedBox(width: 7),
                    _filterChip(
                      label: 'Completed',
                      value: DriverTripStatus.completed,
                    ),
                    const SizedBox(width: 7),
                    _filterChip(
                      label: 'Cancelled',
                      value: DriverTripStatus.cancelled,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── TRIP LIST ──────────────────────────────────────
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No trips found.',
                        style: NavigoTextStyles.bodySmall,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final trip = _filtered[i];
                        return GestureDetector(
                          onTap: () => _openTrip(trip),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: NavigoDecorations.kCardDecoration,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Status icon ──────────────
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration:
                                      NavigoDecorations.iconCircleDecoration(
                                        _statusColor(trip.status),
                                      ),
                                  child: Icon(
                                    _statusIcon(trip.status),
                                    color: _statusColor(trip.status),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // ── Trip info ────────────────
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        trip.line,
                                        style: NavigoTextStyles.bodyMedium
                                            .copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: NavigoColors.textDark,
                                              fontSize: 14,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${trip.from}  →  ${trip.to}',
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
                                            '${trip.date}  •  ${trip.time}',
                                            style: NavigoTextStyles.bodySmall
                                                .copyWith(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // ── Status badge ─────────────
                                NavigoDecorations.statusChip(
                                  label: _statusLabel(trip.status),
                                  color: _statusColor(trip.status),
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
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── TRIP DETAIL BOTTOM SHEET ──────────────────────────────────────────────────
class _DriverTripDetailSheet extends StatelessWidget {
  final DriverTrip trip;

  const _DriverTripDetailSheet({required this.trip});

  Color get _statusColor {
    switch (trip.status) {
      case DriverTripStatus.upcoming:
        return NavigoColors.accentBlue;
      case DriverTripStatus.ongoing:
        return NavigoColors.primaryOrange;
      case DriverTripStatus.completed:
        return NavigoColors.accentGreen;
      case DriverTripStatus.cancelled:
        return NavigoColors.accentRed;
    }
  }

  String get _statusLabel {
    switch (trip.status) {
      case DriverTripStatus.upcoming:
        return 'Upcoming';
      case DriverTripStatus.ongoing:
        return 'Ongoing';
      case DriverTripStatus.completed:
        return 'Completed';
      case DriverTripStatus.cancelled:
        return 'Cancelled';
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
    return Container(
      decoration: NavigoDecorations.kBottomSheetDecoration,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(child: NavigoDecorations.dragHandle()),
          const SizedBox(height: 20),

          // ── Title + status badge ──────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Trip Details', style: NavigoTextStyles.titleSmall),
              NavigoDecorations.statusChip(
                label: _statusLabel,
                color: _statusColor,
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: NavigoColors.primaryOrange.withOpacity(0.3)),
          const SizedBox(height: 8),

          // ── Detail rows ───────────────────────────────────
          _row('Trip ID', trip.id),
          _row('Line', trip.line),
          _row('From', trip.from),
          _row('To', trip.to),
          _row('Date', trip.date),
          _row('Time', trip.time),
          _row('Duration', trip.duration),
          _row('Price', trip.price),
          _row('Seats', trip.seats.toString()),
          _row('Vehicle', trip.vehicleType),

          const SizedBox(height: 20),

          // ── Action button (ongoing only) ──────────────────
          if (trip.status == DriverTripStatus.ongoing)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DriverLiveTripScreen(),
                    ),
                  );
                },
                style: NavigoDecorations.kPrimaryButtonLargeStyle,
                icon: const Icon(Icons.location_on, size: 20),
                label: const Text(
                  'Open Live Trip',
                  style: NavigoTextStyles.button,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
