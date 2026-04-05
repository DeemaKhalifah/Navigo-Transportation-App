import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import 'PassengerBottomNavBar.dart';
import '../passenger/PassengerHomeScreen.dart';

// ── TRIP MODEL ────────────────────────────────────────────────────────────────
enum TripStatus { completed, cancelled, ongoing }

class Trip {
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
  final TripStatus status;

  const Trip({
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

// ── DUMMY DATA ────────────────────────────────────────────────────────────────
const List<Trip> _trips = [
  Trip(
    id: 'T001',
    line: 'Birzeit ↔ Ramallah (Line 12)',
    from: 'Birzeit – Main Gate',
    to: 'Ramallah – Al-Manara',
    date: '01 Apr 2026',
    time: '09:50',
    duration: '20 min',
    price: '6.00 NIS',
    seats: 1,
    vehicleType: 'Bus',
    status: TripStatus.ongoing,
  ),
  Trip(
    id: 'T002',
    line: 'Birzeit ↔ Ramallah (Line 12)',
    from: 'Ramallah – Bus Station',
    to: 'Birzeit – Main Gate',
    date: '31 Mar 2026',
    time: '14:30',
    duration: '22 min',
    price: '6.00 NIS',
    seats: 2,
    vehicleType: 'Mini Bus',
    status: TripStatus.completed,
  ),
  Trip(
    id: 'T003',
    line: 'Birzeit ↔ Ramallah (Line 12)',
    from: 'Birzeit – Main Gate',
    to: 'Ramallah – Bus Station',
    date: '29 Mar 2026',
    time: '08:15',
    duration: '20 min',
    price: '6.00 NIS',
    seats: 1,
    vehicleType: 'Bus',
    status: TripStatus.cancelled,
  ),
  Trip(
    id: 'T004',
    line: 'Birzeit ↔ Ramallah (Line 12)',
    from: 'Al-Bireh – Roundabout',
    to: 'Birzeit – Main Gate',
    date: '27 Mar 2026',
    time: '17:00',
    duration: '18 min',
    price: '6.00 NIS',
    seats: 1,
    vehicleType: 'Bus',
    status: TripStatus.completed,
  ),
  Trip(
    id: 'T005',
    line: 'Birzeit ↔ Ramallah (Line 12)',
    from: 'Birzeit – Main Gate',
    to: 'Ramallah – Al-Manara',
    date: '25 Mar 2026',
    time: '11:00',
    duration: '20 min',
    price: '6.00 NIS',
    seats: 3,
    vehicleType: 'Mini Bus',
    status: TripStatus.completed,
  ),
];

// ── SCREEN ────────────────────────────────────────────────────────────────────
class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  TripStatus? _filterStatus; // null = show all

  List<Trip> get _filtered => _filterStatus == null
      ? _trips
      : _trips.where((t) => t.status == _filterStatus).toList();

  // ── STATUS HELPERS ────────────────────────────────────────────────────────
  Color _statusColor(TripStatus s) {
    switch (s) {
      case TripStatus.completed:
        return NavigoColors.accentGreen;
      case TripStatus.cancelled:
        return NavigoColors.accentRed;
      case TripStatus.ongoing:
        return NavigoColors.primaryOrange;
    }
  }

  String _statusLabel(TripStatus s) {
    switch (s) {
      case TripStatus.completed:
        return 'Completed';
      case TripStatus.cancelled:
        return 'Cancelled';
      case TripStatus.ongoing:
        return 'Ongoing';
    }
  }

  IconData _statusIcon(TripStatus s) {
    switch (s) {
      case TripStatus.completed:
        return Icons.check_circle_outline;
      case TripStatus.cancelled:
        return Icons.cancel_outlined;
      case TripStatus.ongoing:
        return Icons.directions_bus;
    }
  }

  // ── BOTTOM SHEET ──────────────────────────────────────────────────────────
  void _showDetails(Trip trip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NavigoColors.transparent,
      builder: (_) => _TripDetailSheet(trip: trip),
    );
  }

  // ── FILTER CHIP ───────────────────────────────────────────────────────────
  Widget _filterChip({required String label, required TripStatus? value}) {
    final selected = _filterStatus == value;
    return NavigoDecorations.selectorChip(
      label: label,
      selected: selected,
      onTap: () => setState(() => _filterStatus = value),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const PassengerBottomNavBar(currentIndex: 2),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── HEADER ──────────────────────────────────────
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

            // ── FILTER CHIPS ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(label: 'All', value: null),
                    const SizedBox(width: 7),
                    _filterChip(label: 'Ongoing', value: TripStatus.ongoing),
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

            // ── TRIP LIST ────────────────────────────────────
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
                          onTap: () => _showDetails(trip),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: NavigoDecorations.kCardDecoration,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Status icon circle
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

                                // Trip info
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

                                // Status badge
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
class _TripDetailSheet extends StatelessWidget {
  final Trip trip;

  const _TripDetailSheet({required this.trip});

  Color get _statusColor {
    switch (trip.status) {
      case TripStatus.completed:
        return NavigoColors.accentGreen;
      case TripStatus.cancelled:
        return NavigoColors.accentRed;
      case TripStatus.ongoing:
        return NavigoColors.primaryOrange;
    }
  }

  String get _statusLabel {
    switch (trip.status) {
      case TripStatus.completed:
        return 'Completed';
      case TripStatus.cancelled:
        return 'Cancelled';
      case TripStatus.ongoing:
        return 'Ongoing';
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

          // Title + status badge
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

          // Divider
          Divider(color: NavigoColors.primaryOrange.withOpacity(0.3)),

          const SizedBox(height: 8),

          // Details rows
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

          // Track button — only for ongoing trips
          if (trip.status == TripStatus.ongoing)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PassengerHomeScreen(),
                    ),
                  );
                },
                style: NavigoDecorations.kPrimaryButtonLargeStyle,
                icon: const Icon(Icons.location_on, size: 20),
                label: const Text('Track Live', style: NavigoTextStyles.button),
              ),
            ),
        ],
      ),
    );
  }
}
