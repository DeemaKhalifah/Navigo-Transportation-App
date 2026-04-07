import 'package:flutter/material.dart';
import 'dart:async';

import '../../theme/app_theme.dart';
import '../../models/schedule_slot.dart';
import '../../services/passenger_trip_repository.dart';
import 'PassengerBottomNavBar.dart';
import 'passengerHomeScreen.dart';

class ScheduleScreen extends StatefulWidget {
  final String? selectedLine;

  const ScheduleScreen({super.key, this.selectedLine});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final PassengerTripRepository _tripRepository = PassengerTripRepository();

  String? _selectedLine;
  String? _vehicleType;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int _seatCount = 1;
  String? _routeId;
  List<ScheduleSlot> _slots = [];
  bool _isLoadingSlots = false;
  StreamSubscription<List<ScheduleSlot>>? _slotsSubscription;

  final List<String> _vehicles = ['Bus', 'Micro Bus'];

  @override
  void initState() {
    super.initState();
    _selectedLine = widget.selectedLine;
    _loadRouteAndSlots();
  }

  Future<void> _loadRouteAndSlots() async {
    final selected = _selectedLine?.trim();
    if (selected == null || selected.isEmpty) return;

    setState(() => _isLoadingSlots = true);
    try {
      final route = await _tripRepository.getRouteForLine(selected);
      if (!mounted) return;
      if (route == null) {
        setState(() {
          _routeId = null;
          _slots = [];
        });
        return;
      }

      setState(() => _routeId = route.routeId);

      _slotsSubscription?.cancel();
      _slotsSubscription = _tripRepository.watchSlotsForRoute(route.routeId).listen((slots) {
        if (!mounted) return;
        setState(() => _slots = slots);
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load route schedule')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingSlots = false);
      }
    }
  }

  Future<void> _pickDate() async {
    DateTime now = DateTime.now();
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(2100),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _selectedTime = picked);
  }

  String _formatDate() => _selectedDate == null
      ? "Select date"
      : "${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}";

  String _formatTime() => _selectedTime == null
      ? "Select time"
      : "${_selectedTime!.hour}:${_selectedTime!.minute.toString().padLeft(2, '0')}";

  @override
  void dispose() {
    _slotsSubscription?.cancel();
    super.dispose();
  }

  void _incrementSeat() {
    if (_seatCount < 10) setState(() => _seatCount++);
  }

  void _decrementSeat() {
    if (_seatCount > 1) setState(() => _seatCount--);
  }

  void _confirmSchedule() {
    if (_selectedLine == null ||
        _vehicleType == null ||
        _selectedDate == null ||
        _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please complete all fields")),
      );
      return;
    }
    if (_routeId == null || _routeId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This line is not linked to a route yet")),
      );
      return;
    }

    final selectedDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    final matchingSlot = _slots.where((slot) {
      final dep = slot.departureAt;
      final sameDate = dep.year == selectedDateTime.year &&
          dep.month == selectedDateTime.month &&
          dep.day == selectedDateTime.day;
      final sameTime =
          dep.hour == selectedDateTime.hour && dep.minute == selectedDateTime.minute;
      if (!sameDate || !sameTime) return false;
      if (_vehicleType == 'Bus') {
        return slot.vehicleType.toLowerCase().contains('bus');
      }
      return slot.vehicleType.toLowerCase().contains('micro');
    }).toList();

    if (matchingSlot.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No trip found for selected date/time on this line"),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Ride Scheduled: $_seatCount seat(s) 🚀")),
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
            // ── TOP BAR ──────────────────────────────────
            NavigoDecorations.topBar(
              onBack: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const PassengerHomeScreen()),
              ),
              context: context,
            ),
            // ── CONTENT ──────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── TITLE ──────────────────────────────
                    Text("Schedule Ride", style: NavigoTextStyles.titleLarge),

                    const SizedBox(height: 20),
                    if (_isLoadingSlots)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(),
                      ),

                    // ── VEHICLE TYPE ───────────────────────
                    Text("Vehicle Type", style: NavigoTextStyles.label),
                    const SizedBox(height: 8),
                    Row(
                      children: _vehicles
                          .map(
                            (v) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: GestureDetector(
                                  onTap: () => setState(() => _vehicleType = v),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration:
                                        NavigoDecorations.selectorDecoration(
                                          selected: _vehicleType == v,
                                        ),
                                    child: Center(
                                      child: Text(
                                        v,
                                        style: NavigoTextStyles.chip.copyWith(
                                          color: _vehicleType == v
                                              ? NavigoColors.textLight
                                              : NavigoColors.primaryOrange,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),

                    const SizedBox(height: 20),

                    // ── SELECTED LINE ──────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 16,
                      ),
                      decoration: NavigoDecorations.kCardDecoration,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.directions_bus,
                            color: NavigoColors.accentGreen,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            "Line: ${_selectedLine ?? 'None'}",
                            style: NavigoTextStyles.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── SEAT SELECTOR ──────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 20,
                      ),
                      decoration: NavigoDecorations.kCardDecoration,
                      child: Column(
                        children: [
                          Text(
                            "Number of Seats",
                            style: NavigoTextStyles.titleSmall,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                onPressed: _decrementSeat,
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 32,
                                ),
                                color: NavigoColors.accentGreen,
                              ),
                              const SizedBox(width: 20),
                              Text(
                                '$_seatCount',
                                style: NavigoTextStyles.titleLarge,
                              ),
                              const SizedBox(width: 20),
                              IconButton(
                                onPressed: _incrementSeat,
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 32,
                                ),
                                color: NavigoColors.accentGreen,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── DATE PICKER ────────────────────────
                    Text("Date", style: NavigoTextStyles.label),
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

                    // ── TIME PICKER ────────────────────────
                    Text("Time", style: NavigoTextStyles.label),
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

                    const SizedBox(height: 30),

                    // ── CONFIRM BUTTON ─────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: NavigoSizes.buttonHeightLarge,
                      child: ElevatedButton(
                        onPressed: _confirmSchedule,
                        style: NavigoDecorations.kPrimaryButtonLargeStyle,
                        child: const Text(
                          "Confirm Schedule",
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
