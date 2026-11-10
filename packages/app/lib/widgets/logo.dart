import 'dart:math';

import 'package:flutter/material.dart';

/// Brand colours of the Rooftop V logo.
abstract final class LogoColors {
  /// Deep teal tile.
  static const teal = Color(0xFF0B6E5F);

  /// Gold roof line and window.
  static const gold = Color(0xFFF2B33D);

  /// Cream V.
  static const cream = Color(0xFFFFFBF2);
}

/// Paints the Rooftop V mark: a gold roof over a bold cream V on teal.
///
/// [art] is the size of the artwork relative to the canvas (1 = the
/// original 100-unit design fills the canvas). Platform icon masks need
/// smaller art: Android adaptive icons keep it inside the central 66%.
/// With [mono] set, everything is drawn in that one colour on a clear
/// background (Android themed icons, one-colour print).
void paintRooftopV(Canvas canvas, Size size,
    {bool background = true, double art = 1, Color? mono, double radius = 0}) {
  final side = min(size.width, size.height);
  if (background && mono == null) {
    final rect = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        Paint()..color = LogoColors.teal);
  }
  final unit = side * art / 100;
  // Centre the 100-unit design on the canvas.
  canvas.save();
  canvas.translate(size.width / 2 - 50 * unit, size.height / 2 - 50 * unit);
  Paint stroke(Color c, double w) => Paint()
    ..color = mono ?? c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * unit
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final roof = Path()
    ..moveTo(18 * unit, 40 * unit)
    ..lineTo(50 * unit, 18 * unit)
    ..lineTo(82 * unit, 40 * unit);
  canvas.drawPath(roof, stroke(LogoColors.gold, 8.5));
  final v = Path()
    ..moveTo(32 * unit, 49 * unit)
    ..lineTo(50 * unit, 82 * unit)
    ..lineTo(68 * unit, 49 * unit);
  canvas.drawPath(v, stroke(LogoColors.cream, 11));
  canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(45 * unit, 28 * unit, 10 * unit, 10 * unit),
          Radius.circular(2 * unit)),
      Paint()..color = mono ?? LogoColors.gold);
  canvas.restore();
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({required this.radius, this.mono});
  final double radius;
  final Color? mono;

  @override
  void paint(Canvas canvas, Size size) =>
      paintRooftopV(canvas, size, radius: radius, mono: mono);

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.radius != radius || old.mono != mono;
}

/// The app icon as a widget (rounded teal tile).
class VyapariLogo extends StatelessWidget {
  /// Creates the logo.
  const VyapariLogo({super.key, this.size = 48, this.mono});

  /// Side length.
  final double size;

  /// One-colour version in this colour.
  final Color? mono;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Vyapari',
        image: true,
        child: CustomPaint(
          size: Size.square(size),
          painter: _LogoPainter(radius: size * 0.22, mono: mono),
        ),
      );
}

/// Logo plus the VYAPARI wordmark, for headers and splash.
class VyapariWordmark extends StatelessWidget {
  /// Creates the wordmark.
  const VyapariWordmark(
      {super.key, this.height = 40, this.color = LogoColors.cream});

  /// Height of the logo tile; text scales with it.
  final double height;

  /// Wordmark text colour.
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        VyapariLogo(size: height),
        SizedBox(width: height * 0.3),
        Text('VYAPARI',
            style: TextStyle(
                color: color,
                fontSize: height * 0.62,
                fontWeight: FontWeight.w900,
                letterSpacing: height * 0.09)),
      ]);
}
