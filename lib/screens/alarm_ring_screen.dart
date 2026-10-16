import 'package:flutter/material.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/services/native_alarms.dart';
import 'package:nothing_clock/services/timer_service.dart';
import 'package:nothing_clock/widgets/dual_slide_action.dart';

class AlarmRingScreen extends StatelessWidget {
  final int notificationId;
  final String time;
  final String label;
  final bool isTimer;

  const AlarmRingScreen({
    super.key,
    required this.notificationId,
    required this.time,
    this.label = '',
    this.isTimer = false,
  });

  String get _kind => isTimer ? 'timer' : 'alarm';

  Future<void> _stop(BuildContext context) async {
    await NativeAlarms.stopRing(notificationId, _kind);
    if (isTimer) TimerService.changes.value++;
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze(BuildContext context) async {
    await NativeAlarms.snoozeRing(notificationId, _kind, label);
    if (isTimer) TimerService.changes.value++;
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
            child: Column(
              children: [
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.circle, color: Color(0xFFD71921), size: 8),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label.isEmpty
                            ? (isTimer ? tr("TIMER") : tr("ALARM"))
                            : label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFFA3A3A3),
                            letterSpacing: 4,
                            fontSize: 14),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        time,
                        style: const TextStyle(
                            fontFamily: "NDot",
                            fontSize: 110,
                            color: Colors.white),
                      ),
                    ),
                  ),
                ),
                DualSlideAction(
                  leftLabel: isTimer ? tr("SNOOZE 1 MIN") : tr("SNOOZE 10 MIN"),
                  rightLabel: tr("STOP"),
                  rightColor: Color(0xFFD71921),
                  onLeft: () => _snooze(context),
                  onRight: () => _stop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
