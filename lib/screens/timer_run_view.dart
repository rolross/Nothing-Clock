import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nothing_clock/l10n/app_locale.dart';
import 'package:nothing_clock/providers/timer_provider.dart';
import 'package:nothing_clock/widgets/dual_slide_action.dart';
import 'package:provider/provider.dart';

class TimerRunView extends StatefulWidget {
  const TimerRunView({super.key});

  @override
  State<TimerRunView> createState() => _TimerRunViewState();
}

class _TimerRunViewState extends State<TimerRunView>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _completedPulseController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _completedPulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _completedPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _completedPulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(
          parent: _completedPulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _completedPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Consumer<TimerProvider>(
          builder: (context, p, child) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (p.isCompleted && !_completedPulseController.isAnimating) {
                _completedPulseController.repeat(reverse: true);
              } else if (!p.isCompleted &&
                  _completedPulseController.isAnimating) {
                _completedPulseController.stop();
                _completedPulseController.value = 0;
              }
            });

            return Column(
              children: [
                _buildHeader(p),
                Expanded(flex: 5, child: Center(child: _buildTimerDisplay(p))),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _buildControls(p),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(TimerProvider p) {
    final name = p.activeTimer?.name ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: p.closeView,
          ),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTap: () => _renameDialog(p),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name.isEmpty ? tr("TIMER") : name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFFA3A3A3),
                            letterSpacing: 4,
                            fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit, color: Color(0xFFA3A3A3), size: 14),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Future<void> _renameDialog(TimerProvider p) async {
    final controller = TextEditingController(text: p.activeTimer?.name ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr("TIMER NAME")),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr("CANCEL"))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(tr("SAVE"))),
        ],
      ),
    );
    if (result != null) await p.renameActive(result);
  }

  Widget _pill(String text, VoidCallback? onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF333333),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }

  Widget _circleButton({
    required Color color,
    required bool glow,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 65,
      height: 65,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: glow ? 12 : 0,
            spreadRadius: glow ? 2 : 0,
          ),
        ],
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 30),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildControls(TimerProvider p) {
    if (p.isCompleted) {
      return DualSlideAction(
        leftLabel: tr("SNOOZE 1 MIN"),
        rightLabel: tr("STOP"),
        onLeft: p.snoozeActive,
        onRight: p.stopActive,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        p.isPickerMode
            ? _pill(tr("CANCEL"), p.cancelPicker)
            : _pill("- 1:00", () => p.adjust(-60)),
        p.isPickerMode
            ? _circleButton(
                color: Colors.green,
                glow: false,
                icon: Icons.check,
                onTap: p.confirmPicker)
            : _circleButton(
                color: Color(0xFFD71921),
                glow: p.isRunning,
                icon: p.isRunning ? Icons.pause : Icons.play_arrow,
                onTap: p.toggle),
        p.isPickerMode
            ? const SizedBox(width: 90)
            : _pill("+ 1:00", () => p.adjust(60)),
      ],
    );
  }

  Widget _buildTimerDisplay(TimerProvider p) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _completedPulseAnimation]),
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(320, 320),
              painter: TimerPainter(
                progress: p.progress,
                baseColor: const Color.fromARGB(255, 232, 228, 228),
                progressColor: Color(0xFFD71921),
                dotCount: 64,
                pulseAnimation: _pulseAnimation.value,
                isRunning: p.isRunning,
                dotRadius: 2.0,
              ),
            ),
            AnimatedScale(
              scale: p.isCompleted ? _completedPulseAnimation.value : 1.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.isCompleted
                      ? Color(0xFFD71921).withOpacity(0.9)
                      : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: p.isCompleted
                          ? Color(0xFFD71921).withOpacity(0.5)
                          : Colors.white.withOpacity(0.1),
                      blurRadius: p.isCompleted ? 16 : 8,
                      spreadRadius: p.isCompleted ? 4 : 2,
                    ),
                  ],
                ),
                child: p.isPickerMode
                    ? _InlineTimerPicker(provider: p)
                    : _buildTimeDisplay(p),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTimeDisplay(TimerProvider p) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!p.isCompleted) p.openPicker();
      },
      child: Center(
        child: Text(
          formatTimerSeconds(p.remainingSeconds),
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w300,
            fontFamily: 'Roboto',
            color: p.isCompleted ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }
}

class _InlineTimerPicker extends StatefulWidget {
  final TimerProvider provider;

  const _InlineTimerPicker({required this.provider});

  @override
  State<_InlineTimerPicker> createState() => _InlineTimerPickerState();
}

class _InlineTimerPickerState extends State<_InlineTimerPicker> {
  late int _h;
  late int _m;
  late int _s;
  late final FixedExtentScrollController _hc;
  late final FixedExtentScrollController _mc;
  late final FixedExtentScrollController _sc;

  @override
  void initState() {
    super.initState();
    final d = widget.provider.pickerDuration;
    _h = d.inHours.remainder(24);
    _m = d.inMinutes.remainder(60);
    _s = d.inSeconds.remainder(60);
    _hc = FixedExtentScrollController(initialItem: _h);
    _mc = FixedExtentScrollController(initialItem: _m);
    _sc = FixedExtentScrollController(initialItem: _s);
  }

  @override
  void dispose() {
    _hc.dispose();
    _mc.dispose();
    _sc.dispose();
    super.dispose();
  }

  void _emit() {
    widget.provider
        .updatePickerDuration(Duration(hours: _h, minutes: _m, seconds: _s));
  }

  Widget _col(int count, FixedExtentScrollController c, ValueChanged<int> onSel) {
    return SizedBox(
      width: 46,
      height: 150,
      child: CupertinoPicker(
        scrollController: c,
        itemExtent: 32,
        magnification: 1.1,
        useMagnifier: false,
        onSelectedItemChanged: onSel,
        children: List.generate(
          count,
          (i) => Center(child: Text(i.toString().padLeft(2, '0'))),
          growable: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 200,
        height: 180,
        child: CupertinoTheme(
          data: const CupertinoThemeData(
            brightness: Brightness.light,
            textTheme: CupertinoTextThemeData(
              pickerTextStyle: TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w400),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _col(24, _hc, (i) {
                _h = i;
                _emit();
              }),
              const SizedBox(width: 4),
              _col(60, _mc, (i) {
                _m = i;
                _emit();
              }),
              const SizedBox(width: 4),
              _col(60, _sc, (i) {
                _s = i;
                _emit();
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class TimerPainter extends CustomPainter {
  final double progress;
  final Color baseColor;
  final Color progressColor;
  final int dotCount;
  final double pulseAnimation;
  final double dotRadius;
  final bool isRunning;

  TimerPainter({
    required this.progress,
    required this.baseColor,
    required this.progressColor,
    required this.dotCount,
    required this.pulseAnimation,
    required this.isRunning,
    required this.dotRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 * 0.95;

    final safeProgress = min(1.0, max(0.0, progress));
    final exactFilledDots = safeProgress * dotCount;
    final completelyFilledDots = exactFilledDots.floor();
    final transitionProgress = exactFilledDots - completelyFilledDots;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 3.0;

    for (int i = 0; i < dotCount; i++) {
      final angle = 2 * pi * (i / dotCount) - (pi / 2);

      if (i < completelyFilledDots) {
        paint.color = progressColor;
      } else if (i == completelyFilledDots) {
        paint.color =
            Color.lerp(baseColor, progressColor, transitionProgress) ?? baseColor;
      } else {
        paint.color = baseColor;
      }

      double dotRadiusFinal = dotRadius;
      if (i == completelyFilledDots && isRunning && transitionProgress > 0) {
        dotRadiusFinal *= pulseAnimation;
      }

      final dotCenter = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );

      canvas.drawCircle(dotCenter, dotRadiusFinal, paint);
    }
  }

  @override
  bool shouldRepaint(TimerPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.pulseAnimation != pulseAnimation ||
        oldDelegate.isRunning != isRunning;
  }
}
