import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nothing_clock/models/alarm.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/widgets/alarms/day_selector.dart';

/// Bottom sheet that allows the user to pick a time and days for a new alarm.
class AlarmFormBottomSheet extends StatefulWidget {
  /// Callback when a new alarm is saved
  final Function(Alarm)? onSave;
  final Alarm? alarm;
  final void Function(DateTime, Map<String, bool>, String)? onUpdate;
  final VoidCallback? onDelete;

  const AlarmFormBottomSheet({
    super.key,
    this.onSave,
    this.alarm,
    this.onUpdate,
    this.onDelete,
  });

  @override
  State<AlarmFormBottomSheet> createState() => _AlarmFormBottomSheetState();
}

/// State for [AlarmFormBottomSheet], maintains form selections.
class _AlarmFormBottomSheetState extends State<AlarmFormBottomSheet> {
  /// The currently selected time for the new alarm
  DateTime _selectedTime = DateTime.now();
  
  /// Map of days and their selection state
  Map<String, bool> _selectedDays = {
    "MON": false,
    "TUE": false,
    "WED": false,
    "THU": false,
    "FRI": false,
    "SAT": false,
    "SUN": false
  };
  
  /// Whether the alarm is scheduled for specific days
  bool _isScheduled = false;

  final TextEditingController _labelController = TextEditingController();

  Map<String, bool> get _effectiveDays => _isScheduled
      ? _selectedDays
      : {for (final k in _selectedDays.keys) k: false};

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final a = widget.alarm;
    if (a != null) {
      _selectedTime = a.time;
      _labelController.text = a.label;
      _selectedDays = {
        for (final e in _selectedDays.entries) e.key: a.days[e.key] ?? false
      };
      _isScheduled = _selectedDays.values.any((v) => v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
          color: theme.colorScheme.tertiary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: Padding(
        padding: EdgeInsets.only(
            left: 10,
            right: 10,
            top: 50,
            bottom: MediaQuery.of(context).viewInsets.bottom + 40),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Text(widget.alarm == null ? tr("ADD NEW ALARM") : tr("EDIT ALARM"), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              
              // Time picker section
              _buildTimePicker(),
              const SizedBox(height: 10),
              TextField(
                controller: _labelController,
                maxLength: 30,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(hintText: tr("ALARM NAME"), counterText: ""),
              ),
              const SizedBox(height: 10),
              
              // Days selector widget
              AlarmsDaysList(
                selectedDays: _selectedDays,
                isScheduled: _isScheduled,
                onScheduleChanged: (val) {
                  setState(() {
                    _isScheduled = val;
                  });
                },
              ),
              const SizedBox(height: 20),
              
              // Save button
              _buildSaveButton(theme),
              if (widget.alarm != null && widget.onDelete != null) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    widget.onDelete?.call();
                    Navigator.pop(context);
                  },
                  child: Text(tr("DELETE ALARM"),
                      style: TextStyle(color: Color(0xFFD71921), fontWeight: FontWeight.w500)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the time picker widget with Cupertino style
  Widget _buildTimePicker() {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SizedBox(
          height: 150,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            use24hFormat: true,
            initialDateTime: _selectedTime,
            onDateTimeChanged: (value) {
              setState(() {
                _selectedTime = value;
              });
            },
          ),
        ),
      ),
    );
  }

  /// Builds the save button with consistent styling
  Widget _buildSaveButton(ThemeData theme) {
    return TextButton(
      onPressed: _onSavePressed,
      style: TextButton.styleFrom(
        backgroundColor: theme.colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        tr("SAVE ALARM"),
        style: TextStyle(fontFamily: "Roboto", fontWeight: FontWeight.w500),
      ),
    );
  }

  /// Handles saving the new alarm using the provided callback.
  void _onSavePressed() {
    if (widget.alarm != null) {
      widget.onUpdate?.call(_selectedTime, _effectiveDays, _labelController.text.trim());
    } else {
      widget.onSave?.call(Alarm(time: _selectedTime, days: _effectiveDays, label: _labelController.text.trim()));
    }
    Navigator.pop(context);
  }
} 