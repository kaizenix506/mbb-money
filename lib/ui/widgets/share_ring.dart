import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated share-of-income ring used on the overview hero.
class ShareRing extends StatelessWidget {
  const ShareRing({
    required this.fraction,
    this.size = 62,
    this.stroke = 6,
    super.key,
  });

  final double fraction;
  final double size;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final double r = (size - stroke) / 2;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: fraction.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double value, Widget? _) {
          return Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CustomPaint(
                size: Size.square(size),
                painter: _RingPainter(
                  value: value,
                  radius: r,
                  stroke: stroke,
                ),
              ),
              Text(
                '${(value * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: Color(0xFFF2F4F8),
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.radius,
    required this.stroke,
  });

  final double value;
  final double radius;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Colors.white.withValues(alpha: 0.09),
    );

    if (value <= 0) return;

    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: 0,
          endAngle: math.pi * 2,
          colors: <Color>[Color(0xFF3DE8B0), Color(0xFF2CC7FF)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.stroke != stroke;
}
