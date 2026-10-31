import 'dart:math' as math;

import 'package:flutter/material.dart';

enum OrderPinKind { pickup, dropoff }

/// Vector pin artwork shared by the demo and the optional live-map adapter.
void paintOrderPin(Canvas canvas, Size size, OrderPinKind kind) {
  canvas.save();
  canvas.scale(size.width / 48, size.height / 66);
  final outline = Path()
    ..moveTo(24, 65)
    ..cubicTo(20, 51, 1, 36, 1, 24)
    ..cubicTo(1, -7, 47, -7, 47, 24)
    ..cubicTo(47, 36, 28, 51, 24, 65)
    ..close();
  canvas.drawPath(outline, Paint()..color = const Color(0xFF191919));
  canvas.drawPath(
    outline,
    Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1,
  );
  final white = Paint()..color = Colors.white;
  if (kind == OrderPinKind.dropoff) {
    final house = Path()
      ..moveTo(11, 23)
      ..lineTo(24, 12)
      ..lineTo(37, 23)
      ..lineTo(34, 26)
      ..lineTo(33, 25)
      ..lineTo(33, 35)
      ..quadraticBezierTo(33, 37, 31, 37)
      ..lineTo(27, 37)
      ..lineTo(27, 28)
      ..lineTo(21, 28)
      ..lineTo(21, 37)
      ..lineTo(17, 37)
      ..quadraticBezierTo(15, 37, 15, 35)
      ..lineTo(15, 25)
      ..lineTo(14, 26)
      ..close();
    canvas.drawPath(house, white);
  } else {
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(14, 20, 20, 19), const Radius.circular(3)),
        white);
    canvas.drawArc(
      const Rect.fromLTWH(20, 15, 8, 12),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawLine(
        const Offset(15, 35),
        const Offset(33, 35),
        Paint()
          ..color = const Color(0xFF191919)
          ..strokeWidth = 1);
  }
  canvas.restore();
}

/// An original illustrative map. No API key or network is required.
/// Replace this with your existing map or GoogleOrderMap in a real app.
class DemoOrderMap extends StatelessWidget {
  const DemoOrderMap({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Illustrated demo map with rider, pickup, and delivery markers',
        child: const ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _DemoMapPainter()),
              Positioned(
                left: 10,
                bottom: 26,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xDEFFFFFF)),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text('Illustrated map · demo',
                        style:
                            TextStyle(fontSize: 10, color: Color(0xFF555555))),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _DemoMapPainter extends CustomPainter {
  const _DemoMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Frame the 393x496 map art so both the top drop-off pin and bottom pickup
    // pin sit comfortably inside a square-like viewport above the offer sheet.
    canvas.scale(size.width / 393, size.height / 496);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 393, 496),
        Paint()..color = const Color(0xFFF1F0E6));
    canvas.save();
    canvas.translate(0, 18);
    canvas.scale(1.0, 0.86);
    final park = Paint()..color = const Color(0xFFBEDC9D);
    for (final rect in const [
      Rect.fromLTWH(69, 72, 48, 61),
      Rect.fromLTWH(14, 143, 23, 26),
      Rect.fromLTWH(254, 27, 35, 26),
      Rect.fromLTWH(236, 159, 37, 27),
      Rect.fromLTWH(244, 263, 41, 98),
      Rect.fromLTWH(94, 292, 28, 20),
      Rect.fromLTWH(201, 344, 85, 80),
      Rect.fromLTWH(311, 440, 27, 46),
      Rect.fromLTWH(28, 379, 23, 50),
      Rect.fromLTWH(105, 451, 24, 40),
    ]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)), park);
    }
    // Quiet residential blocks, with arterial roads over the top.
    final minor = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 21; i++) {
      final x = i * 20.0 - 8;
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + (i % 3) * 3, 170)
        ..lineTo(x - 3, 350)
        ..lineTo(x + 5, 496);
      canvas.drawPath(
          path,
          minor
            ..color = const Color(0xFFDEDED8)
            ..strokeWidth = 4);
      canvas.drawPath(
          path,
          minor
            ..color = const Color(0xFFFAFAF5)
            ..strokeWidth = 2);
    }
    for (int i = 0; i < 29; i++) {
      final y = i * 18.0;
      final path = Path()
        ..moveTo(0, y)
        ..lineTo(125, y + (i % 2) * 4)
        ..lineTo(270, y)
        ..lineTo(393, y + 2);
      canvas.drawPath(
          path,
          minor
            ..color = const Color(0xFFDEDED8)
            ..strokeWidth = 4);
      canvas.drawPath(
          path,
          minor
            ..color = const Color(0xFFFAFAF5)
            ..strokeWidth = 2);
    }
    final creek = Path()
      ..moveTo(393, 212)
      ..cubicTo(305, 239, 338, 320, 291, 351)
      ..cubicTo(279, 382, 332, 393, 271, 432)
      ..lineTo(263, 496);
    canvas.drawPath(
        creek,
        minor
          ..color = const Color(0xFFAAD9E4)
          ..strokeWidth = 3);
    final roads = [
      Path()
        ..moveTo(46, 0)
        ..lineTo(169, 155)
        ..lineTo(393, 155),
      Path()
        ..moveTo(0, 155)
        ..lineTo(393, 155),
      Path()
        ..moveTo(0, 310)
        ..lineTo(393, 307),
      Path()
        ..moveTo(0, 340)
        ..lineTo(126, 340)
        ..lineTo(393, 496),
      Path()
        ..moveTo(44, 0)
        ..lineTo(44, 496),
      Path()
        ..moveTo(193, 0)
        ..lineTo(193, 496),
      Path()
        ..moveTo(0, 462)
        ..lineTo(393, 462),
    ];
    for (final road in roads) {
      canvas.drawPath(
          road,
          minor
            ..color = const Color(0xFFBFC1C1)
            ..strokeWidth = 6);
      canvas.drawPath(
          road,
          minor
            ..color = const Color(0xFFF9F8F1)
            ..strokeWidth = 3);
    }
    _label(canvas, 'Fremont\nHigh School', const Offset(45, 133), 12,
        const Color(0xFF9F7857));
    _label(canvas, 'PONDEROSA', const Offset(292, 111), 11);
    _label(canvas, 'RAYNOR PARK', const Offset(201, 167), 11);
    _label(canvas, 'BIRDLAND', const Offset(179, 275), 11);
    _label(canvas, 'APPLE PARK', const Offset(206, 347), 10);
    _label(canvas, 'RANCHO\nRINCONADA', const Offset(200, 470), 10);
    final route = Path()
      ..moveTo(164, 134)
      ..lineTo(151, 134)
      ..lineTo(151, 149)
      ..lineTo(140, 149)
      ..lineTo(140, 155)
      ..lineTo(195, 155)
      ..lineTo(195, 462)
      ..lineTo(307, 462)
      ..lineTo(201, 383);
    canvas.drawPath(
        route,
        Paint()
          ..color = const Color(0xFF202020)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
    _pin(canvas, const Offset(164, 134), OrderPinKind.dropoff);
    _pin(canvas, const Offset(230, 462), OrderPinKind.pickup);
    canvas.drawCircle(
        const Offset(202, 374), 11, Paint()..color = Colors.white);
    canvas.drawCircle(
        const Offset(202, 374), 7.5, Paint()..color = const Color(0xFF008BFF));
    canvas.restore();
    canvas.restore();
  }

  void _pin(Canvas canvas, Offset tip, OrderPinKind kind) {
    canvas.save();
    canvas.translate(tip.dx - 22, tip.dy - 62);
    paintOrderPin(canvas, const Size(44, 62), kind);
    canvas.restore();
  }

  void _label(Canvas canvas, String text, Offset position, double fontSize,
      [Color color = const Color(0xFF61615D)]) {
    final painter = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
              color: color, fontSize: fontSize, fontWeight: FontWeight.w500)),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, position);
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _DemoMapPainter oldDelegate) => false;
}
