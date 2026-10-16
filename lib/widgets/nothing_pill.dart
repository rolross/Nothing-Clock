import 'package:flutter/material.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/models/alarm.dart';
import 'package:nothing_clock/services/alarms_service.dart';

const Color nothingRed = Color(0xFFD71921);

void showNothingPill(BuildContext context, String text,
    {Duration hold = const Duration(milliseconds: 2400)}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) =>
        _PillToast(text: text, hold: hold, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

void showRingsInPill(BuildContext context, Alarm alarm) {
  if (!alarm.isEnabled) return;
  final next = AlarmsService().nextTrigger(alarm);
  if (next == null) return;
  final totalMinutes = (next.difference(DateTime.now()).inSeconds + 59) ~/ 60;
  final d = totalMinutes ~/ 1440;
  final h = (totalMinutes % 1440) ~/ 60;
  final m = totalMinutes % 60;
  final parts = <String>[
    if (d > 0) '$d d',
    if (h > 0) '$h h',
    if (m > 0 || (d == 0 && h == 0)) '$m min',
  ];
  showNothingPill(context, '${tr("Rings in")} ${parts.join(" ")}');
}

class _PillToast extends StatefulWidget {
  final String text;
  final Duration hold;
  final VoidCallback onDone;

  const _PillToast(
      {required this.text, required this.hold, required this.onDone});

  @override
  State<_PillToast> createState() => _PillToastState();
}

class _PillToastState extends State<_PillToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 260),
  );

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    await _c.forward();
    await Future.delayed(widget.hold);
    if (!mounted) return;
    await _c.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, 0.78),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_c.value);
            return Opacity(
              opacity: t,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: Align(widthFactor: t, heightFactor: 1, child: child),
              ),
            );
          },
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              decoration: BoxDecoration(
                color: nothingRed,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(
                widget.text.toUpperCase(),
                softWrap: false,
                style: const TextStyle(
                  fontFamily: 'NDot',
                  fontSize: 18,
                  letterSpacing: 1,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
