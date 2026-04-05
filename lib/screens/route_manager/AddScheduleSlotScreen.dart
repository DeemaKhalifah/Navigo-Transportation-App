import 'package:flutter/material.dart';
import 'package:navigo/models/schedule_slot.dart';
import 'package:navigo/services/schedule_slot_repository.dart';
import 'package:navigo/services/slot_driver_assignment_service.dart';
import 'package:navigo/theme/app_theme.dart';

class AddScheduleSlotScreen extends StatefulWidget {
  const AddScheduleSlotScreen({
    super.key,
    required this.routeId,
    this.existingSlot,
  });

  final String routeId;

  /// When set, the screen saves with merge into this document.
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
      _selectedDate =
          DateTime(e.serviceDate.year, e.serviceDate.month, e.serviceDate.day);
      _fromTime = TimeOfDay.fromDateTime(e.departureAt);
      _toTime = TimeOfDay.fromDateTime(e.arrivalAt);
      _capacity = e.capacity.toString();
      if (_selectedType == 'micro' && _capacity == '14') {
        _capacity = '7';
      }
      final p = e.price;
      if (p != null) {
        _priceController.text =
            p.toStringAsFixed(p == p.roundToDouble() ? 0 : 2);
      }
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool isFrom) async {
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

  Future<void> _save() async {
    if (_selectedDate == null || _fromTime == null || _toTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose date and both times')),
      );
      return;
    }

    final cap = int.tryParse(_capacity ?? '');
    if (cap == null || cap <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select capacity')),
      );
      return;
    }

    final departure = _combine(_selectedDate!, _fromTime!);
    final arrival = _combine(_selectedDate!, _toTime!);
    if (!arrival.isAfter(departure)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }

    double? price;
    final priceText = _priceController.text.trim();
    if (priceText.isNotEmpty) {
      price = double.tryParse(priceText.replaceAll(',', '.'));
      if (price == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid price')),
        );
        return;
      }
    }

    final slot = ScheduleSlot(
      slotId: widget.existingSlot?.slotId ?? '',
      routeId: widget.routeId,
      departureAt: departure,
      arrivalAt: arrival,
      price: price,
      capacity: cap,
      vehicleType: _selectedType,
    );

    setState(() => _saving = true);
    try {
      if (widget.isEditing) {
        await _repo.upsertSlot(slot);
      } else {
        final slotId = await _repo.addSlot(slot);
        final assign = await _assignment.tryAssignDriverForNewSlot(
          routeId: widget.routeId,
          slotId: slotId,
          departureAt: departure,
          arrivalAt: arrival,
        );
        if (!mounted) return;
        if (assign.outcome == SlotAssignmentOutcome.noDriversInQueue) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Slot saved. No drivers in queue — assign manually later.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Slot saved. Driver assigned. Trip: ${assign.tripId}',
              ),
            ),
          );
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NavigoColors.backgroundLight,
      body: SafeArea(
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
                    widget.isEditing ? 'Edit schedule slot' : 'Add schedule slot',
                    style: NavigoTextStyles.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Departure window and capacity (slot ID is assigned by Firestore)',
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
                          Row(
                            children: [
                              Expanded(
                                child: _buildPickerBox(
                                  label: 'From',
                                  value: _formatTime(_fromTime),
                                  icon: Icons.access_time,
                                  onTap: () => _pickTime(true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildPickerBox(
                                  label: 'To',
                                  value: _formatTime(_toTime),
                                  icon: Icons.access_time_filled,
                                  onTap: () => _pickTime(false),
                                ),
                              ),
                            ],
                          ),

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

                          Text('Capacity (seats)', style: NavigoTextStyles.label),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _capacity,
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
                                widget.isEditing ? 'Save changes' : 'Save slot',
                                style: NavigoTextStyles.button,
                              ),
                      ),
                    ),

                    const SizedBox(height: NavigoSizes.itemGap),

                    SizedBox(
                      width: double.infinity,
                      height: NavigoSizes.buttonHeight,
                      child: ElevatedButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
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
