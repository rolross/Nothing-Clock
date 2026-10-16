import 'package:flutter/material.dart';

class SlideToAction extends StatefulWidget {
  final String label;
  final VoidCallback onCompleted;
  final Color thumbColor;
  final IconData icon;

  const SlideToAction({
    super.key,
    required this.label,
    required this.onCompleted,
    this.thumbColor = Colors.white,
    this.icon = Icons.arrow_forward,
  });

  @override
  State<SlideToAction> createState() => _SlideToActionState();
}

class _SlideToActionState extends State<SlideToAction> {
  static const double _height = 64;
  static const double _pad = 4;
  double _dx = 0;
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      const thumb = _height - _pad * 2;
      final maxDx = constraints.maxWidth - thumb - _pad * 2;
      final progress =
          maxDx <= 0 ? 0.0 : (_dx / maxDx).clamp(0.0, 1.0).toDouble();

      return Container(
        height: _height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_height / 2),
          border: Border.all(color: Colors.white54, width: 1),
        ),
        child: Stack(
          children: [
            Center(
              child: Opacity(
                opacity: 1 - progress,
                child: Text(
                  widget.label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, letterSpacing: 2),
                ),
              ),
            ),
            Positioned(
              left: _pad + _dx,
              top: _pad,
              child: GestureDetector(
                onHorizontalDragUpdate: (d) {
                  if (_done) return;
                  setState(() =>
                      _dx = (_dx + d.delta.dx).clamp(0.0, maxDx).toDouble());
                },
                onHorizontalDragEnd: (_) {
                  if (_done) return;
                  if (progress > 0.85) {
                    _done = true;
                    setState(() => _dx = maxDx);
                    widget.onCompleted();
                  } else {
                    setState(() => _dx = 0);
                  }
                },
                child: Container(
                  width: thumb,
                  height: thumb,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: widget.thumbColor),
                  child: Icon(widget.icon, color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
