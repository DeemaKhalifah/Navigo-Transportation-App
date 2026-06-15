import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../localization/localization_x.dart';
import '../theme/app_theme.dart';

class ManualTimeDialog extends StatefulWidget {
  const ManualTimeDialog({super.key, required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<ManualTimeDialog> createState() => _ManualTimeDialogState();
}

class _ManualTimeDialogState extends State<ManualTimeDialog> {
  late final TextEditingController _hourController;
  late final TextEditingController _minuteController;
  late bool _isPm;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final hour = widget.initialTime.hourOfPeriod == 0
        ? 12
        : widget.initialTime.hourOfPeriod;
    _hourController = TextEditingController(text: '$hour');
    _minuteController = TextEditingController(
      text: widget.initialTime.minute.toString().padLeft(2, '0'),
    );
    _isPm = widget.initialTime.period == DayPeriod.pm;
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _submit() {
    final hour = int.tryParse(_hourController.text.trim());
    final minute = int.tryParse(_minuteController.text.trim());

    if (hour == null ||
        hour < 1 ||
        hour > 12 ||
        minute == null ||
        minute < 0 ||
        minute > 59) {
      setState(() => _errorText = context.texts.t('enterValidTime'));
      return;
    }

    final hour24 = (hour % 12) + (_isPm ? 12 : 0);
    Navigator.pop(context, TimeOfDay(hour: hour24, minute: minute));
  }

  @override
  Widget build(BuildContext context) {
    const inputStyle = TextStyle(
      color: Colors.black,
      fontSize: 20,
      fontWeight: FontWeight.w600,
    );

    return AlertDialog(
      title: Text(
        context.texts.t('enterTime'),
        style: const TextStyle(color: Colors.black),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hourController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: inputStyle,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: NavigoDecorations.kInputDecoration.copyWith(
                      labelText: context.texts.t('hour'),
                      hintText: '1-12',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(':', style: NavigoTextStyles.titleLarge),
                ),
                Expanded(
                  child: TextField(
                    controller: _minuteController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: inputStyle,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: NavigoDecorations.kInputDecoration.copyWith(
                      labelText: context.texts.t('minute'),
                      hintText: '00-59',
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('AM')),
                ButtonSegment(value: true, label: Text('PM')),
              ],
              selected: {_isPm},
              onSelectionChanged: (selection) {
                setState(() {
                  _isPm = selection.first;
                  _errorText = null;
                });
              },
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorText!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.texts.t('cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.texts.t('setTime')),
        ),
      ],
    );
  }
}
