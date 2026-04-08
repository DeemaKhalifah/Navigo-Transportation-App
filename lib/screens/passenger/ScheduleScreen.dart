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

  final List<String> _vehicles = ['Bus', 'Micro Bus'];

  @override
  void initState() {
    super.initState();
    _bootstrapFromWidgetOrStorage();
  }

  Future<void> _bootstrapFromWidgetOrStorage() async {
    String? line = widget.selectedLine?.trim();
    if (line == null || line.isEmpty) {
      final saved = await LocalStorageService.getSelectedLine();
      line = saved?.trim();
    }
    if (!mounted) return;
    setState(() => _selectedLine = line);
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
    }
  }

  void _incrementSeat() {
    if (_seatCount < 10) {
      setState(() => _seatCount++);
    }
  }

  void _decrementSeat() {
    if (_seatCount > 1) {
      setState(() => _seatCount--);
    }
  }

  String _formatDate() {
    if (_selectedDate == null) return 'Any date';
    return '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}';
  }

  String _formatTime() {
    if (_selectedTime == null) return 'Any time';
    return '${_selectedTime!.hour}:${_selectedTime!.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _showSchedulesAvailable() async {
    try {
      setState(() => _isLoading = true);

      final schedules = await _scheduleService.findAvailableSchedules(
        selectedLine: _selectedLine,
        vehicleType: _vehicleType,
        selectedDate: _selectedDate,
        selectedTime: _selectedTime,
      );

      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: NavigoColors.transparent,
        builder: (_) => _AvailableSchedulesSheet(
          schedules: schedules,
          seatCount: _seatCount,
          scheduleService: _scheduleService,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load schedules: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
                              onTap: () => setState(() => _vehicleType = v),
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
                    Text('Date', style: NavigoTextStyles.label),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        decoration: NavigoDecorations.kCardDecoration,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              color: NavigoColors.accentGreen,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatDate(),
                              style: NavigoTextStyles.bodyMedium.copyWith(
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text('Time', style: NavigoTextStyles.label),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _pickTime,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 16,
                        ),
                        decoration: NavigoDecorations.kCardDecoration,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              color: NavigoColors.accentGreen,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _formatTime(),
                              style: NavigoTextStyles.bodyMedium.copyWith(
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                      decoration: NavigoDecorations.kCardDecoration,
                      child: Row(
                        children: [
                          Text(
                            'Seats:',
                            style: NavigoTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$_seatCount',
                            style: NavigoTextStyles.bodySmall.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: NavigoColors.textDark,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _decrementSeat,
                            icon: const Icon(Icons.remove_circle_outline),
                            color: NavigoColors.accentGreen,
                          ),
                          IconButton(
                            onPressed: _incrementSeat,
                            icon: const Icon(Icons.add_circle_outline),
                            color: NavigoColors.accentGreen,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: NavigoSizes.buttonHeightLarge,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _showSchedulesAvailable,
                        style: NavigoDecorations.kPrimaryButtonLargeStyle,
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Show schedules available',
                                style: NavigoTextStyles.button,
                              ),
                      ),
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

class _AvailableSchedulesSheet extends StatefulWidget {
  const _AvailableSchedulesSheet({
    required this.schedules,
    required this.seatCount,
    required this.scheduleService,
  });

  final List<ScheduleSlot> schedules;
  final int seatCount;
  final PassengerScheduleService scheduleService;

  @override
  State<_AvailableSchedulesSheet> createState() =>
      _AvailableSchedulesSheetState();
}

class _AvailableSchedulesSheetState extends State<_AvailableSchedulesSheet> {
  ScheduleSlot? _selectedSlot;
  late int _seatCount;
  late List<ScheduleSlot> _schedules;
  bool _isConfirming = false;

  @override
  void initState() {
    super.initState();
    _seatCount = widget.seatCount;
    _schedules = List<ScheduleSlot>.from(widget.schedules);
  }

  void _increaseSeat() {
    setState(() => _seatCount++);
  }

  void _decreaseSeat() {
    if (_seatCount > 1) {
      setState(() => _seatCount--);
    }
  }

  int _availableForSelected() {
    if (_selectedSlot == null) return 0;
    return widget.scheduleService.availableSeatsOf(_selectedSlot!);
  }

  Future<void> _confirm() async {
    if (_selectedSlot == null) {
      _showPrompt('Please select a schedule first.');
      return;
    }

    final available = _availableForSelected();

    if (_seatCount > available) {
      _showPrompt('Only $available seat(s) are available for this schedule.');
      return;
    }

    try {
      setState(() => _isConfirming = true);

      await widget.scheduleService.confirmSchedule(
        slot: _selectedSlot!,
        seatsToBook: _seatCount,
      );

      final updatedSlot = widget.scheduleService.applyLocalBooking(
        slot: _selectedSlot!,
        seatsBooked: _seatCount,
        userId: widget.scheduleService.currentUserId,
      );

      final index = _schedules.indexWhere(
        (s) => s.slotId == updatedSlot.slotId,
      );
      if (index != -1) {
        _schedules[index] = updatedSlot;
      }

      setState(() {
        _selectedSlot = updatedSlot;
        _schedules = _schedules
            .where((slot) => widget.scheduleService.availableSeatsOf(slot) > 0)
            .toList();
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Schedule confirmed for $_seatCount seat(s).')),
      );
    } catch (e) {
      if (!mounted) return;
      _showPrompt(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isConfirming = false);
      }
    }
  }

  void _showPrompt(String message) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Notice'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedAvailable = _availableForSelected();

    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: NavigoDecorations.kBottomSheetDecoration,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Center(child: NavigoDecorations.dragHandle()),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('Available Schedules', style: NavigoTextStyles.titleSmall),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: NavigoDecorations.kCardDecoration,
              child: Row(
                children: [
                  Text(
                    'Seats:',
                    style: NavigoTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$_seatCount',
                    style: NavigoTextStyles.bodySmall.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: NavigoColors.textDark,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _decreaseSeat,
                    icon: const Icon(Icons.remove_circle_outline),
                    color: NavigoColors.accentGreen,
                  ),
                  IconButton(
                    onPressed: _increaseSeat,
                    icon: const Icon(Icons.add_circle_outline),
                    color: NavigoColors.accentGreen,
                  ),
                ],
              ),
            ),
          ),
          if (_selectedSlot != null && _seatCount > selectedAvailable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Only $selectedAvailable seat(s) available for the selected trip.',
                  style: NavigoTextStyles.bodySmall.copyWith(
                    color: NavigoColors.accentRed,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: _schedules.isEmpty
                ? Center(
                    child: Text(
                      'No available schedules found.',
                      style: NavigoTextStyles.bodySmall,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _schedules.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final slot = _schedules[index];
                      final selected = _selectedSlot?.slotId == slot.slotId;
                      final available = widget.scheduleService.availableSeatsOf(
                        slot,
                      );

                      return GestureDetector(
                        onTap: () => setState(() => _selectedSlot = slot),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected
                                  ? NavigoColors.primaryOrange
                                  : Colors.transparent,
                              width: 1.6,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: selected
                                    ? NavigoColors.primaryOrange
                                    : NavigoColors.textMuted,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.scheduleService.lineOf(slot),
                                      style: NavigoTextStyles.bodyMedium
                                          .copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: NavigoColors.textDark,
                                            fontSize: 14,
                                          ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${widget.scheduleService.fromOf(slot)} → ${widget.scheduleService.toOf(slot)}',
                                      style: NavigoTextStyles.bodySmall
                                          .copyWith(
                                            fontSize: 12,
                                            color: NavigoColors.textMuted,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        Text(
                                          '${PassengerScheduleService.formatDate(slot.departureAt)} • ${PassengerScheduleService.formatTime(slot.departureAt)}',
                                          style: NavigoTextStyles.bodySmall
                                              .copyWith(fontSize: 12),
                                        ),
                                        Text(
                                          'Seats: $available',
                                          style: NavigoTextStyles.bodySmall
                                              .copyWith(fontSize: 12),
                                        ),
                                        Text(
                                          'Price: ${widget.scheduleService.priceTextOf(slot)}',
                                          style: NavigoTextStyles.bodySmall
                                              .copyWith(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: NavigoSizes.buttonHeightLarge,
                child: ElevatedButton(
                  onPressed: _isConfirming ? null : _confirm,
                  style: NavigoDecorations.kPrimaryButtonLargeStyle,
                  child: _isConfirming
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Confirm schedule',
                          style: NavigoTextStyles.button,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
