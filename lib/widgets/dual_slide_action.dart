import 'package:flutter/material.dart';

class DualSlideAction extends StatefulWidget {
  final String leftLabel;
  final String rightLabel;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final Color leftColor;
  final Color rightColor;

  const DualSlideAction({
    super.key,
    required this.leftLabel,
    required this.rightLabel,
    required this.onLeft,
    required this.onRight,
    this.leftColor = Colors.white,
    this.rightColor = const Color(0xFFD71921),
  });

  @override
  State<DualSlideAction> createState() => _DualSlideActionState();
}

class _DualSlideActionState extends State<DualSlideAction> {
  static const double _height = 72;
  static const double _pad = 6;
  double _dx = 0;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const thumb = _height - _pad * 2;
      final maxDx = (constraints.maxWidth - thumb - _pad * 2) / 2;
      final progress =
          maxDx <= 0 ? 0.0 : (_dx.abs() / maxDx).clamp(0.0, 1.0).toDouble();
      final active = _dx >= 0 ? widget.rightColor : widget.leftColor;

      return Container(
        height: _height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_height / 2),
          border: Border.all(color: Colors.white54, width: 1),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 24,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(widget.leftLabel,
                    style: TextStyle(
                        color: _dx < 0 ? Colors.white : Colors.white54,
                        fontSize: 11,
                        letterSpacing: 1.5)),
              ),
            ),
            Positioned(
              right: 24,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(widget.rightLabel,
                    style: TextStyle(
                        color: _dx > 0 ? Colors.white : Colors.white54,
                        fontSize: 11,
                        letterSpacing: 1.5)),
              ),
            ),
            Positioned(
              left: _pad + maxDx + _dx,
              top: _pad,
              child: GestureDetector(
                onHorizontalDragUpdate: (d) {
                  if (_done) return;
                  setState(() => _dx =
                      (_dx + d.delta.dx).clamp(-maxDx, maxDx).toDouble());
                },
                onHorizontalDragEnd: (_) {
                  if (_done) return;
                  final p = maxDx <= 0 ? 0.0 : _dx.abs() / maxDx;
                  if (p > 0.85) {
                    _done = true;
                    final goRight = _dx > 0;
                    setState(() => _dx = goRight ? maxDx : -maxDx);
                    if (goRight) {
                      widget.onRight();
                    } else {
                      widget.onLeft();
                    }
                  } else {
                    setState(() => _dx = 0);
                  }
                },
                child: Container(
                  width: thumb,
                  height: thumb,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(Colors.white, active, progress),
                  ),
                  child: const Icon(Icons.swap_horiz, color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
