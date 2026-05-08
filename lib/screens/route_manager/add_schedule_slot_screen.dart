import 'package:flutter/material.dart';
import 'package:navigo/models/schedule_slot.dart';
import 'package:navigo/services/schedule_slot_repository.dart';
import 'package:navigo/services/slot_driver_assignment_service.dart';
import 'package:navigo/theme/app_theme.dart';
import '../../localization/localization_x.dart';
import 'route_manager_notification_compose.dart';
import 'route_manager_nav_bar.dart';

class AddScheduleSlotScreen extends StatefulWidget {
  const AddScheduleSlotScreen({
    super.key,
    required this.routeId,
    this.existingSlot,
  });

  final String routeId;
  final ScheduleSlot? existingSlot;

  bool get isEditing => existingSlot != null;

  @override
  State<AddScheduleSlotScreen> createState() => _AddScheduleSlotScreenState();
}

class _AddScheduleSlotScreenState extends State<AddScheduleSlotScreen> {
  final ScheduleSlotRepository _repo = ScheduleSlotRepository();
  final SlotDriverAssignmentService _assignment = SlotDriverAssignmentService();

  String _selectedType = 'bus';

  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _frequencyController = TextEditingController();
  final TextEditingController _tripLengthController = TextEditingController(
    text: '60',
  );

  String? _capacity;

  TimeOfDay? _fromTime;
  TimeOfDay? _toTime;
  DateTime? _selectedDate;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existingSlot;
    if (e != null) {
      _selectedType = e.vehicleType;
      _selectedDate = DateTime(
        e.serviceDate.year,
        e.serviceDate.month,
        e.serviceDate.day,
      );
      _fromTime = TimeOfDay.fromDateTime(e.departureAt);
      if (e.vehicleType == 'micro') {
        _toTime = null;
      } else {
        _toTime = TimeOfDay.fromDateTime(e.arrivalAt);
        if (e.frequencyMinutes != null && e.frequencyMinutes! > 0) {
          _frequencyController.text = e.frequencyMinutes!.toString();
          final mins = e.arrivalAt.difference(e.departureAt).inMinutes;
          if (mins > 0) {
            _tripLengthController.text = mins.toString();
          }
        }
      }
      _capacity = e.capacity.toString();
      if (_selectedType == 'micro' && _capacity == '14') {
        _capacity = '7';
      }
      final p = e.price;
      if (p != null) {
        _priceController.text = p.toStringAsFixed(
          p == p.roundToDouble() ? 0 : 2,
        );
      }
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    _frequencyController.dispose();
    _tripLengthController.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isFrom}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromTime = picked;
        } else {
          _toTime = picked;
        }
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
      initialDate: _selectedDate ?? DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return context.texts.t('select');
    return time.format(context);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return context.texts.t('selectDate');
    return '${date.day}/${date.month}/${date.year}';
  }

  DateTime _combine(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  List<ScheduleSlot> _buildSlotsToCreate({
    required int capacity,
    required double? price,
    required int? frequencyMinutes,
    required int tripLengthMinutes,
  }) {
    if (widget.isEditing && widget.existingSlot != null) {
      final e = widget.existingSlot!;
      final dep = _combine(_selectedDate!, _fromTime!);
      final arr = _selectedType == 'micro'
          ? dep.add(e.arrivalAt.difference(e.departureAt))
          : _combine(_selectedDate!, _toTime!);
      return [
        ScheduleSlot(
          slotId: e.slotId,
          routeId: widget.routeId,
          departureAt: dep,
          arrivalAt: arr,
          price: price,
          capacity: capacity,
          vehicleType: _selectedType,
          driverId: e.driverId,
          passengersIds: List<String>.from(e.passengersIds),
          frequencyMinutes: _selectedType == 'bus' ? frequencyMinutes : null,
          etaMinutes: e.etaMinutes,
          etaText: e.etaText,
          distanceMeters: e.distanceMeters,
          distanceKm: e.distanceKm,
          distanceText: e.distanceText,
          routePolyline: e.routePolyline,
          routePath: e.routePath,
          routeModule: e.routeModule,
        ),
      ];
    }

    if (_selectedType == 'micro') {
      final dep = _combine(_selectedDate!, _fromTime!);
      final arr = dep.add(const Duration(minutes: 45));
      return [
        ScheduleSlot(
          slotId: '',
          routeId: widget.routeId,
          departureAt: dep,
          arrivalAt: arr,
          price: price,
          capacity: capacity,
          vehicleType: _selectedType,
          frequencyMinutes: null,
        ),
      ];
    }

    // Bus
    final freq = frequencyMinutes ?? 0;
    if (freq <= 0) {
      final dep = _combine(_selectedDate!, _fromTime!);
      final arr = _combine(_selectedDate!, _toTime!);
      return [
        ScheduleSlot(
          slotId: '',
          routeId: widget.routeId,
          departureAt: dep,
          arrivalAt: arr,
          price: price,
          capacity: capacity,
          vehicleType: _selectedType,
          frequencyMinutes: null,
        ),
      ];
    }

    final firstDep = _combine(_selectedDate!, _fromTime!);
    final lastStart = _combine(_selectedDate!, _toTime!);
    if (lastStart.isBefore(firstDep)) {
      return [];
    }

    final tripLen = Duration(minutes: tripLengthMinutes);
    final out = <ScheduleSlot>[];
    var dep = firstDep;
    while (!dep.isAfter(lastStart)) {
      out.add(
        ScheduleSlot(
          slotId: '',
          routeId: widget.routeId,
          departureAt: dep,
          arrivalAt: dep.add(tripLen),
          price: price,
          capacity: capacity,
          vehicleType: _selectedType,
          frequencyMinutes: freq,
        ),
      );
      dep = dep.add(Duration(minutes: freq));
    }
    return out;
  }

  Future<void> _save() async {
    if (_selectedDate == null || _fromTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.texts.t('chooseDateAndTime'))),
      );
      return;
    }

    if (_selectedType == 'bus' && _toTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.texts.t('chooseEndTime')),
        ),
      );
      return;
    }

    final cap = int.tryParse(_capacity ?? '');
    if (cap == null || cap <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.texts.t('selectCapacity'))));
      return;
    }

    int? frequencyMinutes;
    if (_selectedType == 'bus' && _frequencyController.text.trim().isNotEmpty) {
      frequencyMinutes = int.tryParse(_frequencyController.text.trim());
      if (frequencyMinutes != null && frequencyMinutes <= 0) {
        frequencyMinutes = null;
      }
    }

    int tripLengthMinutes = 60;
    if (_selectedType == 'bus' &&
        frequencyMinutes != null &&
        frequencyMinutes > 0) {
      final t = int.tryParse(_tripLengthController.text.trim());
      if (t == null || t <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.texts.t('enterTripLength')),
          ),
        );
        return;
      }
      tripLengthMinutes = t;
    } else if (_selectedType == 'bus' &&
        (frequencyMinutes == null || frequencyMinutes <= 0)) {
      final dep = _combine(_selectedDate!, _fromTime!);
      final arr = _combine(_selectedDate!, _toTime!);
      if (!arr.isAfter(dep)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.texts.t('endTimeAfterStart'))),
        );
        return;
      }
    }

    double? price;
    final priceText = _priceController.text.trim();
    if (priceText.isNotEmpty) {
      price = double.tryParse(priceText.replaceAll(',', '.'));
      if (price == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.texts.t('invalidPrice'))));
        return;
      }
    }

    final slots = _buildSlotsToCreate(
      capacity: cap,
      price: price,
      frequencyMinutes: frequencyMinutes,
      tripLengthMinutes: tripLengthMinutes,
    );

    if (slots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.texts.t('checkDepartureTimes')),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (widget.isEditing) {
        await _repo.upsertSlot(slots.first);
      } else {
        var assigned = 0;
        var noQueue = 0;
        for (final slot in slots) {
          final slotId = await _repo.addSlot(slot);
          final assign = await _assignment.tryAssignDriverForNewSlot(
            routeId: widget.routeId,
            slotId: slotId,
          );
          if (assign.outcome == SlotAssignmentOutcome.assigned) {
            assigned++;
          } else {
            noQueue++;
          }
        }
        if (!mounted) return;
        if (noQueue > 0 && assigned == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                slots.length > 1
                    ? '${context.texts.t('savedTrips')} ${slots.length} ${context.texts.t('tripsLabel')}. ${context.texts.t('noDriversQueue')}'
                    : '${context.texts.t('tripSaved')} ${context.texts.t('noDriversQueue')}',
              ),
            ),
          );
        } else if (noQueue > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${context.texts.t('savedTrips')} ${slots.length} ${context.texts.t('tripsLabel')}. $assigned ${context.texts.t('autoAssigned')}; '
                '$noQueue ${context.texts.t('withoutQueueDriver')}.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                slots.length > 1
                    ? '${context.texts.t('savedTrips')} ${slots.length} ${context.texts.t('tripsLabel')}. ${context.texts.t('driversAssignedQueue')}'
                    : '${context.texts.t('tripSaved')} ${context.texts.t('driverAssignedQueue')}',
              ),
            ),
          );
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${context.texts.t('couldNotSave')}: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMicro = _selectedType == 'micro';
    final busRepeat =
        !isMicro &&
        int.tryParse(_frequencyController.text.trim()) != null &&
        (int.tryParse(_frequencyController.text.trim()) ?? 0) > 0;

    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      // ✅ Fix: bottomNavigationBar is correctly at the Scaffold root,
      // completely outside SafeArea so it always renders.
      bottomNavigationBar: const RouteManagerNavBar(currentIndex: 0),
      body: SafeArea(
        // ✅ Fix: bottom: false so SafeArea doesn't consume the nav bar's space,
        // preventing layout conflicts that caused the nav bar to not appear.
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NavigoDecorations.topBar3(
              onBack: () => Navigator.pop(context),
              onNotification: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RouteManagerNotificationCompose(),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NavigoSizes.screenPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isEditing ? context.texts.t('editTrip') : context.texts.t('scheduleATrip'),
                    style: NavigoTextStyles.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isMicro
                        ? context.texts.t('microSubtitle')
                        : busRepeat
                        ? context.texts.t('busRepeatSubtitle')
                        : context.texts.t('busSubtitle'),
                    style: NavigoTextStyles.bodySmall,
                  ),
                ],
              ),
            ),

            const SizedBox(height: NavigoSizes.sectionGap),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: NavigoSizes.screenPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        NavigoDecorations.selectorChip(
                          label: context.texts.t('bus'),
                          selected: _selectedType == 'bus',
                          onTap: () => setState(() {
                            _selectedType = 'bus';
                            // Ensure dropdown value exists in items (prevents assertion).
                            _capacity =
                                (_capacity != null &&
                                        const {'45', '14'}.contains(_capacity))
                                    ? _capacity
                                    : '45';
                          }),
                        ),
                        const SizedBox(width: 10),
                        NavigoDecorations.selectorChip(
                          label: context.texts.t('microBus'),
                          selected: _selectedType == 'micro',
                          onTap: () => setState(() {
                            _selectedType = 'micro';
                            // Ensure dropdown value exists in items (prevents assertion).
                            _capacity = '7';
                          }),
                        ),
                      ],
                    ),

                    const SizedBox(height: NavigoSizes.sectionGap),

                    Container(
                      padding: const EdgeInsets.all(NavigoSizes.cardPadding),
                      decoration: NavigoDecorations.kCardDecoration,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isMicro) ...[
                            _buildPickerBox(
                              label: context.texts.t('startTripTime'),
                              value: _formatTime(_fromTime),
                              icon: Icons.access_time,
                              onTap: () => _pickTime(isFrom: true),
                            ),
                          ] else if (!busRepeat &&
                              (int.tryParse(_frequencyController.text.trim()) ??
                                      0) <=
                                  0) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: _buildPickerBox(
                                    label: context.texts.t('from'),
                                    value: _formatTime(_fromTime),
                                    icon: Icons.access_time,
                                    onTap: () => _pickTime(isFrom: true),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildPickerBox(
                                    label: context.texts.t('to'),
                                    value: _formatTime(_toTime),
                                    icon: Icons.access_time_filled,
                                    onTap: () => _pickTime(isFrom: false),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            _buildPickerBox(
                              label: context.texts.t('firstDeparture'),
                              value: _formatTime(_fromTime),
                              icon: Icons.access_time,
                              onTap: () => _pickTime(isFrom: true),
                            ),
                            const SizedBox(height: NavigoSizes.itemGap),
                            _buildPickerBox(
                              label: context.texts.t('lastDeparture'),
                              value: _formatTime(_toTime),
                              icon: Icons.access_time_filled,
                              onTap: () => _pickTime(isFrom: false),
                            ),
                            const SizedBox(height: NavigoSizes.itemGap),
                            Text(
                              context.texts.t('tripLengthMinutes'),
                              style: NavigoTextStyles.label,
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _tripLengthController,
                              keyboardType: TextInputType.number,
                              style: NavigoTextStyles.fieldText,
                              decoration: NavigoDecorations.kInputDecoration,
                              onChanged: (_) => setState(() {}),
                            ),
                          ],

                          if (!isMicro) ...[
                            const SizedBox(height: NavigoSizes.itemGap),
                            Text(
                              context.texts.t('repeatEvery'),
                              style: NavigoTextStyles.label,
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _frequencyController,
                              keyboardType: TextInputType.number,
                              style: NavigoTextStyles.fieldText,
                              decoration: NavigoDecorations.kInputDecoration
                                  .copyWith(
                                    hintText: context.texts.t('leaveEmptySingle'),
                                  ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],

                          const SizedBox(height: NavigoSizes.itemGap),

                          Text(context.texts.t('date'), style: NavigoTextStyles.label),
                          const SizedBox(height: 6),
                          _buildPickerBox(
                            label: '',
                            value: _formatDate(_selectedDate),
                            icon: Icons.calendar_today,
                            onTap: _pickDate,
                          ),

                          const SizedBox(height: NavigoSizes.itemGap),

                          Text(
                            context.texts.t('capacitySeats'),
                            style: NavigoTextStyles.label,
                          ),
                          const SizedBox(height: 6),
                          Builder(
                            builder: (context) {
                              final capacityItems = _selectedType == 'bus'
                                  ? const [
                                      DropdownMenuItem(
                                        value: '45',
                                        child: Text('45 seats'),
                                      ),
                                      DropdownMenuItem(
                                        value: '14',
                                        child: Text('14 seats'),
                                      ),
                                    ]
                                  : const [
                                      DropdownMenuItem(
                                        value: '7',
                                        child: Text('7 seats'),
                                      ),
                                    ];
                              final selectedCapacity = capacityItems
                                      .any((i) => i.value == _capacity)
                                  ? _capacity
                                  : null;

                              return DropdownButtonFormField<String>(
                                value: selectedCapacity,
                                decoration: NavigoDecorations.kInputDecoration,
                                style: NavigoTextStyles.fieldText,
                                items: capacityItems,
                                onChanged: (value) =>
                                    setState(() => _capacity = value),
                              );
                            },
                          ),

                          const SizedBox(height: NavigoSizes.itemGap),

                          Text(
                            context.texts.t('priceOverride'),
                            style: NavigoTextStyles.label,
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _priceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: NavigoTextStyles.fieldText,
                            decoration: NavigoDecorations.kInputDecoration
                                .copyWith(
                                    hintText: context.texts.t('leaveEmptyDefault'),
                                ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: NavigoSizes.sectionGap),

                    SizedBox(
                      width: double.infinity,
                      height: NavigoSizes.buttonHeight,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: NavigoDecorations.kPrimaryButtonLargeStyle,
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: NavigoColors.textLight,
                                ),
                              )
                            : Text(
                                widget.isEditing ? context.texts.t('saveChanges') : context.texts.t('saveTrip'),
                                style: NavigoTextStyles.button,
                              ),
                      ),
                    ),

                    const SizedBox(height: NavigoSizes.itemGap),

                    SizedBox(
                      width: double.infinity,
                      height: NavigoSizes.buttonHeight,
                      child: ElevatedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        style: NavigoDecorations.kPrimaryButtonLargeStyle
                            .copyWith(
                              backgroundColor: const WidgetStatePropertyAll(
                                NavigoColors.accentRed,
                              ),
                            ),
                        child: Text(
                          context.texts.t('cancel'),
                          style: NavigoTextStyles.button,
                        ),
                      ),
                    ),

                    const SizedBox(height: NavigoSizes.sectionGap),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerBox({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(label, style: NavigoTextStyles.label),
          const SizedBox(height: 6),
        ],
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: NavigoDecorations.surfaceDecoration(
              radius: NavigoSizes.inputRadius,
              color: NavigoColors.inputFill,
              bordered: false,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: NavigoColors.accentGreen),
                const SizedBox(width: 8),
                Expanded(child: Text(value, style: NavigoTextStyles.fieldText)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
