import 'package:flutter/material.dart';

import '../../models/schedule_slot.dart';
import '../../services/local_storage_service.dart';
import '../../services/passenger_schedule_service.dart';
import '../../theme/app_theme.dart';
import 'PassengerBottomNavBar.dart';
import 'passengerHomeScreen.dart';

class ScheduleScreen extends StatefulWidget {
  final String? selectedLine;

  const ScheduleScreen({super.key, this.selectedLine});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final PassengerScheduleService _scheduleService = PassengerScheduleService();

  String? _selectedLine;
  String? _vehicleType;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int _seatCount = 1;
  bool _isLoading = false;
  bool _lineFilterFromNavigation = false;
  List<ScheduleSlot> _schedules = [];

  final List<String> _vehicles = ['Bus', 'Micro Bus'];

  @override
  void initState() {
    super.initState();
    _bootstrapFromWidgetOrStorage();
  }

  Future<void> _bootstrapFromWidgetOrStorage() async {
    String? line = widget.selectedLine?.trim();
    _lineFilterFromNavigation = line != null && line.isNotEmpty;
    if (line == null || line.isEmpty) {
      final saved = await LocalStorageService.getSelectedLine();
      line = saved?.trim();
    }
    if (!mounted) return;
    setState(() => _selectedLine = line);
    await _loadSchedules();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now,
      lastDate: DateTime(2100),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => _selectedDate = picked);
      await _loadSchedules();
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() => _selectedTime = picked);
      await _loadSchedules();
    }
  }

  void _incrementSeat() {
    if (_seatCount < 10) setState(() => _seatCount++);
  }

  void _decrementSeat() {
    if (_seatCount > 1) setState(() => _seatCount--);
  }

  String _formatDate() {
    if (_selectedDate == null) return 'Any date';
    return '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}';
  }

  String _formatTime() {
    if (_selectedTime == null) return 'Any time';
    return '${_selectedTime!.hour}:${_selectedTime!.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _loadSchedules() async {
    try {
      setState(() => _isLoading = true);
      final selectedLineForQuery = _lineFilterFromNavigation
          ? _selectedLine
          : null;

      final schedules = await _scheduleService.findAvailableSchedules(
        selectedLine: selectedLineForQuery,
        vehicleType: _vehicleType,
        selectedDate: _selectedDate,
        selectedTime: _selectedTime,
      );

      if (!mounted) return;
      setState(() => _schedules = schedules);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load schedules: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openTripDetails(ScheduleSlot slot) async {
    int sheetSeatCount = _seatCount;
    bool isConfirming = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: NavigoColors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final availableSeats = _scheduleService.availableSeatsOf(slot);
            return Container(
              decoration: NavigoDecorations.kBottomSheetDecoration,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: NavigoDecorations.dragHandle()),
                    const SizedBox(height: 14),
                    Text(
                      _scheduleService.lineOf(slot),
                      style: NavigoTextStyles.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_scheduleService.fromOf(slot)} → ${_scheduleService.toOf(slot)}',
                      style: NavigoTextStyles.bodySmall.copyWith(
                        color: NavigoColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Date: ${PassengerScheduleService.formatDate(slot.departureAt)}',
                      style: NavigoTextStyles.bodyMedium,
                    ),
                    Text(
                      'Time: ${PassengerScheduleService.formatTime(slot.departureAt)}',
                      style: NavigoTextStyles.bodyMedium,
                    ),
                    Text(
                      'Price: ${_scheduleService.priceTextOf(slot)}',
                      style: NavigoTextStyles.bodyMedium,
                    ),
                    Text(
                      'Available seats: $availableSeats',
                      style: NavigoTextStyles.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 14,
                      ),
                      decoration: NavigoDecorations.kCardDecoration,
                      child: Row(
                        children: [
                          Text(
                            'Seats:',
                            style: NavigoTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$sheetSeatCount',
                            style: NavigoTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: sheetSeatCount > 1
                                ? () => setSheetState(() => sheetSeatCount--)
                                : null,
                            icon: const Icon(Icons.remove_circle_outline),
                            color: NavigoColors.accentGreen,
                          ),
                          IconButton(
                            onPressed: sheetSeatCount < 10
                                ? () => setSheetState(() => sheetSeatCount++)
                                : null,
                            icon: const Icon(Icons.add_circle_outline),
                            color: NavigoColors.accentGreen,
                          ),
                        ],
                      ),
                    ),
                    if (sheetSeatCount > availableSeats)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Only $availableSeats seat(s) are available for this trip.',
                          style: NavigoTextStyles.bodySmall.copyWith(
                            color: NavigoColors.accentRed,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: NavigoSizes.buttonHeightLarge,
                      child: ElevatedButton(
                        onPressed: isConfirming
                            ? null
                            : () async {
                                if (sheetSeatCount > availableSeats) return;
                                setSheetState(() => isConfirming = true);
                                try {
                                  await _scheduleService.confirmSchedule(
                                    slot: slot,
                                    seatsToBook: sheetSeatCount,
                                  );
                                  final updated = _scheduleService
                                      .applyLocalBooking(
                                        slot: slot,
                                        seatsBooked: sheetSeatCount,
                                        userId: _scheduleService.currentUserId,
                                      );
                                  if (!mounted) return;
                                  setState(() {
                                    _seatCount = sheetSeatCount;
                                    final index = _schedules.indexWhere(
                                      (s) =>
                                          s.slotId == updated.slotId &&
                                          s.routeId == updated.routeId,
                                    );
                                    if (index != -1)
                                      _schedules[index] = updated;
                                    _schedules = _schedules
                                        .where(
                                          (s) =>
                                              _scheduleService.availableSeatsOf(
                                                s,
                                              ) >
                                              0,
                                        )
                                        .toList();
                                  });
                                  if (!sheetContext.mounted) return;
                                  Navigator.pop(sheetContext);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Schedule confirmed for $sheetSeatCount seat(s).',
                                      ),
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        e.toString().replaceFirst(
                                          'Exception: ',
                                          '',
                                        ),
                                      ),
                                    ),
                                  );
                                } finally {
                                  if (sheetContext.mounted)
                                    setSheetState(() => isConfirming = false);
                                }
                              },
                        style: NavigoDecorations.kPrimaryButtonLargeStyle,
                        child: isConfirming
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Confirm schedule',
                                style: NavigoTextStyles.button,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      bottomNavigationBar: const PassengerBottomNavBar(currentIndex: 1),
      body: SafeArea(
        child: Column(
          children: [
            NavigoDecorations.topBar(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const PassengerHomeScreen()),
              ),
              context: context,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Schedule Ride', style: NavigoTextStyles.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      'Line',
                      style: NavigoTextStyles.label.copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedLine ?? 'All lines',
                      style: NavigoTextStyles.bodySmall.copyWith(
                        color: NavigoColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Vehicle Type', style: NavigoTextStyles.label),
                    const SizedBox(height: 8),
                    Row(
                      children: _vehicles.map((v) {
                        final selected = _vehicleType == v;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: GestureDetector(
                              onTap: () async {
                                setState(() {
                                  _vehicleType = _vehicleType == v ? null : v;
                                });
                                await _loadSchedules();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration:
                                    NavigoDecorations.selectorDecoration(
                                      selected: selected,
                                    ),
                                child: Center(
                                  child: Text(
                                    v,
                                    style: NavigoTextStyles.chip.copyWith(
                                      color: selected
                                          ? NavigoColors.textLight
                                          : NavigoColors.primaryOrange,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // ── Date & Time on the same row ──────────────────────────
                    Text('Date & Time', style: NavigoTextStyles.label),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickDate,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 12,
                              ),
                              decoration: NavigoDecorations.kCardDecoration,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.calendar_today,
                                    color: NavigoColors.accentGreen,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _formatDate(),
                                      style: NavigoTextStyles.bodyMedium
                                          .copyWith(fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickTime,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 12,
                              ),
                              decoration: NavigoDecorations.kCardDecoration,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.access_time,
                                    color: NavigoColors.accentGreen,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _formatTime(),
                                      style: NavigoTextStyles.bodyMedium
                                          .copyWith(fontSize: 14),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // ────────────────────────────────────────────────────────
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Text('Available Trips', style: NavigoTextStyles.label),
                        const Spacer(),
                        IconButton(
                          onPressed: _isLoading ? null : _loadSchedules,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (_schedules.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: NavigoDecorations.kCardDecoration,
                        child: Text(
                          'No available schedules found.',
                          style: NavigoTextStyles.bodySmall,
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _schedules.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final slot = _schedules[index];
                          final available = _scheduleService.availableSeatsOf(
                            slot,
                          );
                          return InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _openTripDetails(slot),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: NavigoDecorations.kCardDecoration,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _scheduleService.lineOf(slot),
                                    style: NavigoTextStyles.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: NavigoColors.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_scheduleService.fromOf(slot)} → ${_scheduleService.toOf(slot)}',
                                    style: NavigoTextStyles.bodySmall.copyWith(
                                      color: NavigoColors.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    children: [
                                      Text(
                                        '${PassengerScheduleService.formatDate(slot.departureAt)} • ${PassengerScheduleService.formatTime(slot.departureAt)}',
                                        style: NavigoTextStyles.bodySmall,
                                      ),
                                      Text(
                                        'Seats: $available',
                                        style: NavigoTextStyles.bodySmall,
                                      ),
                                      Text(
                                        'Price: ${_scheduleService.priceTextOf(slot)}',
                                        style: NavigoTextStyles.bodySmall,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
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
