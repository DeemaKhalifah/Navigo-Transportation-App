import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/schedule_slot.dart';
import '../../models/waiting_trip_request.dart';
import '../../services/geocoding_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/passenger_schedule_service.dart';
import '../../services/passenger_trip_repository.dart';
import '../../services/waiting_trip_request_service.dart';
import '../../localization/localization_x.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_message.dart';
import 'passenger_bottom_nav_bar.dart';
import 'passenger_home_screen.dart';

class ScheduleScreen extends StatefulWidget {
  final String? selectedLine;

  const ScheduleScreen({super.key, this.selectedLine});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final PassengerScheduleService _scheduleService = PassengerScheduleService();
  final PassengerTripRepository _tripRepository = PassengerTripRepository();
  final WaitingTripRequestService _waitingRequestService =
      WaitingTripRequestService();
  final TextEditingController _manualPickupController = TextEditingController();

  String? _selectedLine;
  String? _vehicleType;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  int _seatCount = 1;
  bool _isLoading = false;
  bool _isSubmittingWaitingRequest = false;
  bool _lineFilterFromNavigation = false;
  List<ScheduleSlot> _schedules = [];

  final List<String> _vehicles = ['Bus', 'Micro Bus'];

  @override
  void initState() {
    super.initState();
    _bootstrapFromWidgetOrStorage();
  }

  @override
  void dispose() {
    _manualPickupController.dispose();
    super.dispose();
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
    await _prefillPickupFromSavedMap();
  }

  Future<void> _prefillPickupFromSavedMap() async {
    try {
      final saved = await _tripRepository.getSavedPassengerLocation();
      if (!mounted || saved == null) return;
      final label = await GeocodingService.reverseGeocodeLabel(saved);
      if (!mounted) return;
      if (_manualPickupController.text.trim().isEmpty) {
        setState(() => _manualPickupController.text = label);
      }
    } catch (_) {}
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

  String _formatDate() {
    if (_selectedDate == null) return context.texts.t('anyDate');
    return '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}';
  }

  String _formatTime() {
    if (_selectedTime == null) return context.texts.t('anyTime');
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
      AppMessage.showError(context, 'Failed to load schedules: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitWaitingTripRequest({int? seatsOverride}) async {
    if (_isSubmittingWaitingRequest) return;

    final line = _selectedLine?.trim() ?? '';
    if (line.isEmpty) {
      AppMessage.showError(context, context.texts.t('selectLineFirst'));
      return;
    }
    if (_selectedDate == null || _selectedTime == null) {
      AppMessage.showError(context, context.texts.t('chooseDateAndTime'));
      return;
    }

    setState(() => _isSubmittingWaitingRequest = true);
    try {
      final result = await _waitingRequestService.submitRequest(
        selectedLine: line,
        selectedDate: _selectedDate!,
        hour: _selectedTime!.hour,
        minute: _selectedTime!.minute,
        vehicleType: _vehicleType,
        seatsRequested: seatsOverride ?? _seatCount,
        pickupLocationDescription: _manualPickupController.text,
      );

      if (!mounted) return;
      AppMessage.showSuccess(
        context,
        result.routeManagerNotified
            ? context.texts.t('waitingTripManagerNotified')
            : '${context.texts.t('waitingTripRequested')} ${result.waitingSeatCount}/4',
      );
      await _loadSchedules();
    } catch (e) {
      if (!mounted) return;
      AppMessage.showError(context, _waitingListErrorText(e));
    } finally {
      if (mounted) setState(() => _isSubmittingWaitingRequest = false);
    }
  }

  String _waitingListErrorText(Object error) {
    if (error is WaitingTripRequestException) {
      return context.texts.t(error.messageKey);
    }
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    const knownKeys = {
      'waitingListLoginRequired',
      'selectLineFirst',
      'waitingListSelectSeat',
      'waitingListFutureDateTime',
      'waitingListRouteNotFound',
    };
    if (knownKeys.contains(raw)) return context.texts.t(raw);
    return raw;
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
                      '${context.texts.t('date')}: ${PassengerScheduleService.formatDate(slot.departureAt)}',
                      style: NavigoTextStyles.bodyMedium,
                    ),
                    Text(
                      '${context.texts.t('time')}: ${PassengerScheduleService.formatTime(slot.departureAt)}',
                      style: NavigoTextStyles.bodyMedium,
                    ),
                    Text(
                      '${context.texts.t('price')}: ${_scheduleService.priceTextOf(slot)}',
                      style: NavigoTextStyles.bodyMedium,
                    ),
                    Text(
                      '${context.texts.t('availableSeats')}: $availableSeats',
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
                            '${context.texts.t('seats')}:',
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
                          'Only $availableSeats ${context.texts.t('seatsAvailableForTrip')}',
                          style: NavigoTextStyles.bodySmall.copyWith(
                            color: NavigoColors.accentRed,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (sheetSeatCount > availableSeats &&
                        _schedules.length == 1) ...[
                      SizedBox(
                        width: double.infinity,
                        height: NavigoSizes.buttonHeightLarge,
                        child: OutlinedButton.icon(
                          onPressed: _isSubmittingWaitingRequest
                              ? null
                              : () async {
                                  Navigator.pop(sheetContext);
                                  await _submitWaitingTripRequest(
                                    seatsOverride: sheetSeatCount,
                                  );
                                },
                          icon: const Icon(Icons.group_add_outlined),
                          label: Text(
                            _isSubmittingWaitingRequest
                                ? context.texts.t('sending')
                                : context.texts.t('joinWaitingList'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
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
                                  final setPickupFirst = context.texts.t(
                                    'setPickupFirst',
                                  );
                                  final LatLng? pickupLatLng =
                                      await _tripRepository
                                          .getSavedPassengerLocation();
                                  if (pickupLatLng == null) {
                                    throw Exception(setPickupFirst);
                                  }

                                  await _scheduleService.confirmSchedule(
                                    slot: slot,
                                    seatsToBook: sheetSeatCount,
                                    pickupLocationDescription:
                                        _manualPickupController.text,
                                  );

                                  final updated = _scheduleService
                                      .applyLocalBooking(
                                        slot: slot,
                                        seatsBooked: sheetSeatCount,
                                        userId: _scheduleService.currentUserId,
                                        pickupLocationDescription:
                                            _manualPickupController.text,
                                      );
                                  if (!mounted) return;
                                  setState(() {
                                    _seatCount = sheetSeatCount;
                                    final index = _schedules.indexWhere(
                                      (s) =>
                                          s.slotId == updated.slotId &&
                                          s.routeId == updated.routeId,
                                    );
                                    if (index != -1) {
                                      _schedules[index] = updated;
                                    }
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
                                  AppMessage.showSuccess(
                                    context,
                                    '${context.texts.t('scheduleConfirmed')} $sheetSeatCount ${context.texts.t('seats')}.',
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  AppMessage.showError(
                                    context,
                                    e.toString().replaceFirst(
                                      'Exception: ',
                                      '',
                                    ),
                                  );
                                } finally {
                                  if (sheetContext.mounted) {
                                    setSheetState(() => isConfirming = false);
                                  }
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
                            : Text(
                                context.texts.t('confirmSchedule'),
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
                    Text(
                      context.texts.t('searchSchedule'),
                      style: NavigoTextStyles.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.texts.t('line'),
                      style: NavigoTextStyles.label.copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedLine ?? context.texts.t('allLines'),
                      style: NavigoTextStyles.bodySmall.copyWith(
                        color: NavigoColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      context.texts.t('vehicleTypeLabel'),
                      style: NavigoTextStyles.label,
                    ),
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
                    Text(
                      context.texts.t('pickupLocation'),
                      style: NavigoTextStyles.label,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.texts.t('pickupHint'),
                      style: NavigoTextStyles.bodySmall.copyWith(
                        color: NavigoColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _manualPickupController,
                      maxLines: 2,
                      style: const TextStyle(color: NavigoColors.textDark),
                      decoration: NavigoDecorations.kInputDecoration.copyWith(
                        hintText: context.texts.t('enterPickup'),
                        filled: true,
                        fillColor: NavigoColors.surfaceWhite,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Date & Time on the same row ──────────────────────────
                    Text(
                      context.texts.t('dateAndTime'),
                      style: NavigoTextStyles.label,
                    ),
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
                    const SizedBox(height: 14),
                    _buildSeatSelector(),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Text(
                          context.texts.t('availableTrips'),
                          style: NavigoTextStyles.label,
                        ),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.texts.t('noSchedulesFound'),
                              style: NavigoTextStyles.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed:
                                    (_isSubmittingWaitingRequest ||
                                        _selectedDate == null ||
                                        _selectedTime == null)
                                    ? null
                                    : _submitWaitingTripRequest,
                                icon: const Icon(Icons.group_add_outlined),
                                label: Text(
                                  _isSubmittingWaitingRequest
                                      ? context.texts.t('sending')
                                      : context.texts.t('joinWaitingList'),
                                ),
                              ),
                            ),
                            if (_selectedDate == null ||
                                _selectedTime == null) ...[
                              const SizedBox(height: 8),
                              Text(
                                context.texts.t('waitingListChooseDateTime'),
                                style: NavigoTextStyles.bodySmall.copyWith(
                                  color: NavigoColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
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
                                        '${context.texts.t('seats')}: $available',
                                        style: NavigoTextStyles.bodySmall,
                                      ),
                                      Text(
                                        '${context.texts.t('price')}: ${_scheduleService.priceTextOf(slot)}',
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

  Widget _buildSeatSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: NavigoDecorations.kCardDecoration,
      child: Row(
        children: [
          const Icon(
            Icons.event_seat_outlined,
            color: NavigoColors.accentGreen,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.texts.t('numberOfSeats'),
              style: NavigoTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            onPressed: _seatCount > 1
                ? () => setState(() => _seatCount--)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
            color: NavigoColors.accentGreen,
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$_seatCount',
              textAlign: TextAlign.center,
              style: NavigoTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: _seatCount < 10
                ? () => setState(() => _seatCount++)
                : null,
            icon: const Icon(Icons.add_circle_outline),
            color: NavigoColors.accentGreen,
          ),
        ],
      ),
    );
  }
}
