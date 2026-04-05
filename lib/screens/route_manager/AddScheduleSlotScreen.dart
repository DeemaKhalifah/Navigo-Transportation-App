import 'package:flutter/material.dart';
import 'package:navigo/models/schedule_slot.dart';
import 'package:navigo/services/schedule_slot_repository.dart';
import 'package:navigo/services/slot_driver_assignment_service.dart';
import 'package:navigo/theme/app_theme.dart';
import 'RouteManagerNavBar.dart';

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
    if (time == null) return 'Select';
    return time.format(context);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Select date';
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
        const SnackBar(content: Text('Please choose date and time')),
      );
      return;
    }

    if (_selectedType == 'bus' && _toTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose end time / last departure'),
        ),
      );
      return;
    }

    final cap = int.tryParse(_capacity ?? '');
    if (cap == null || cap <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select capacity')));
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
          const SnackBar(
            content: Text('Enter trip length in minutes (e.g. 60)'),
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
          const SnackBar(content: Text('End time must be after start time')),
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
        ).showSnackBar(const SnackBar(content: Text('Invalid price')));
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
        const SnackBar(
          content: Text('Check departure times for repeating bus trips'),
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
                    ? 'Saved ${slots.length} trips. No drivers in queue — assign manually.'
                    : 'Trip saved. No drivers in queue — assign manually.',
              ),
            ),
          );
        } else if (noQueue > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Saved ${slots.length} trips. $assigned auto-assigned; '
                '$noQueue without queue driver.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                slots.length > 1
                    ? 'Saved ${slots.length} trips. Drivers assigned from queue.'
                    : 'Trip saved. Driver assigned from queue.',
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
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
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
            NavigoDecorations.topBar(onBack: () => Navigator.pop(context)),

            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NavigoSizes.screenPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isEditing ? 'Edit trip' : 'Schedule a trip',
                    style: NavigoTextStyles.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isMicro
                        ? 'Start time, date, and capacity'
                        : busRepeat
                        ? 'First departure, last departure start, trip length, repeat interval'
                        : 'Departure window, date, and capacity',
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
                          label: 'Bus',
                          selected: _selectedType == 'bus',
                          onTap: () => setState(() => _selectedType = 'bus'),
                        ),
                        const SizedBox(width: 10),
                        NavigoDecorations.selectorChip(
                          label: 'Micro Bus',
                          selected: _selectedType == 'micro',
                          onTap: () => setState(() => _selectedType = 'micro'),
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
                              label: 'Start trip time',
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
                                    label: 'From',
                                    value: _formatTime(_fromTime),
                                    icon: Icons.access_time,
                                    onTap: () => _pickTime(isFrom: true),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildPickerBox(
                                    label: 'To',
                                    value: _formatTime(_toTime),
                                    icon: Icons.access_time_filled,
                                    onTap: () => _pickTime(isFrom: false),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            _buildPickerBox(
                              label: 'First departure',
                              value: _formatTime(_fromTime),
                              icon: Icons.access_time,
                              onTap: () => _pickTime(isFrom: true),
                            ),
                            const SizedBox(height: NavigoSizes.itemGap),
                            _buildPickerBox(
                              label: 'Last departure (start time)',
                              value: _formatTime(_toTime),
                              icon: Icons.access_time_filled,
                              onTap: () => _pickTime(isFrom: false),
                            ),
                            const SizedBox(height: NavigoSizes.itemGap),
                            Text(
                              'Trip length (minutes)',
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
                              'Repeat every (minutes, optional)',
                              style: NavigoTextStyles.label,
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _frequencyController,
                              keyboardType: TextInputType.number,
                              style: NavigoTextStyles.fieldText,
                              decoration: NavigoDecorations.kInputDecoration
                                  .copyWith(
                                    hintText: 'Leave empty for a single trip',
                                  ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],

                          const SizedBox(height: NavigoSizes.itemGap),

                          Text('Date', style: NavigoTextStyles.label),
                          const SizedBox(height: 6),
                          _buildPickerBox(
                            label: '',
                            value: _formatDate(_selectedDate),
                            icon: Icons.calendar_today,
                            onTap: _pickDate,
                          ),

                          const SizedBox(height: NavigoSizes.itemGap),

                          Text(
                            'Capacity (seats)',
                            style: NavigoTextStyles.label,
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _capacity,
                            decoration: NavigoDecorations.kInputDecoration,
                            style: NavigoTextStyles.fieldText,
                            items: _selectedType == 'bus'
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
                                  ],
                            onChanged: (value) =>
                                setState(() => _capacity = value),
                          ),

                          const SizedBox(height: NavigoSizes.itemGap),

                          Text(
                            'Price override (optional)',
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
                                  hintText: 'Leave empty to use route default',
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
                                widget.isEditing ? 'Save changes' : 'Save trip',
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
                        child: const Text(
                          'Cancel',
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
