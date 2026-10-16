import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/providers/timer_provider.dart';

class TimerFormSheet extends StatefulWidget {
  final SavedTimer? timer;
  final void Function(String name, int seconds) onSave;
  final VoidCallback? onDelete;

  const TimerFormSheet({
    super.key,
    this.timer,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<TimerFormSheet> createState() => _TimerFormSheetState();
}

class _TimerFormSheetState extends State<TimerFormSheet> {
  late final TextEditingController _name;
  late Duration _duration;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.timer?.name ?? '');
    _duration = Duration(seconds: widget.timer?.seconds ?? 60);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
          color: theme.colorScheme.tertiary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: Padding(
        padding: EdgeInsets.only(
            left: 10,
            right: 10,
            top: 50,
            bottom: MediaQuery.of(context).viewInsets.bottom + 40),
        child: SingleChildScrollView(
          child: Column(
            children: [
              Text(widget.timer == null ? tr("NEW TIMER") : tr("EDIT TIMER"),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: _name,
                maxLength: 30,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                    hintText: tr("TIMER NAME"), counterText: ""),
              ),
              const SizedBox(height: 10),
              CupertinoTheme(
                data: CupertinoThemeData(brightness: theme.brightness),
                child: SizedBox(
                  height: 216,
                  child: CupertinoTimerPicker(
                    mode: CupertinoTimerPickerMode.hms,
                    initialTimerDuration: _duration,
                    onTimerDurationChanged: (d) => _duration = d,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  if (_duration.inSeconds <= 0) return;
                  widget.onSave(_name.text.trim(), _duration.inSeconds);
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(
                  backgroundColor: theme.colorScheme.onPrimary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  tr("SAVE TIMER"),
                  style: const TextStyle(
                      fontFamily: "Roboto", fontWeight: FontWeight.w500),
                ),
              ),
              if (widget.timer != null && widget.onDelete != null) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    widget.onDelete?.call();
                    Navigator.pop(context);
                  },
                  child: Text(tr("DELETE TIMER"),
                      style: const TextStyle(
                          color: Color(0xFFD71921), fontWeight: FontWeight.w500)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
