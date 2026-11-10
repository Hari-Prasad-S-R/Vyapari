import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Two dice. They tumble while [tumbling], glow and pulse when tappable.
class DicePair extends StatefulWidget {
  /// Creates the dice.
  const DicePair({
    super.key,
    required this.d1,
    required this.d2,
    this.size = 48,
    this.tumbling = false,
    this.glow = false,
    this.onTap,
  });

  /// First die face 1–6.
  final int d1;

  /// Second die face 1–6.
  final int d2;

  /// Side of one die.
  final double size;

  /// Spin through random faces.
  final bool tumbling;

  /// Highlight: it is your turn to roll.
  final bool glow;

  /// Tap to roll.
  final VoidCallback? onTap;

  @override
  State<DicePair> createState() => _DicePairState();
}

class _DicePairState extends State<DicePair>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  final _rng = Random();
  Timer? _spin;
  int _f1 = 1, _f2 = 1;
  double _a1 = 0, _a2 = 0;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(DicePair old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.glow) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
    if (widget.tumbling) {
      _spin ??= Timer.periodic(const Duration(milliseconds: 70), (_) {
        if (!mounted) return;
        setState(() {
          _f1 = _rng.nextInt(6) + 1;
          _f2 = _rng.nextInt(6) + 1;
          _a1 = (_rng.nextDouble() - 0.5) * 0.9;
          _a2 = (_rng.nextDouble() - 0.5) * 0.9;
        });
      });
    } else {
      _spin?.cancel();
      _spin = null;
      _f1 = widget.d1;
      _f2 = widget.d2;
      _a1 = -0.08;
      _a2 = 0.1;
    }
  }

  @override
  void dispose() {
    _spin?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: widget.onTap != null,
        label: widget.onTap != null
            ? 'Tap the dice to roll'
            : 'Dice showing ${widget.d1} and ${widget.d2}',
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = _pulse.value;
              return Transform.scale(
                scale: 1 + t * 0.06,
                child: Container(
                  padding: EdgeInsets.all(widget.size * 0.14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.size * 0.3),
                    boxShadow: widget.glow
                        ? [
                            BoxShadow(
                                color: const Color(0xFFF2B33D)
                                    .withValues(alpha: 0.35 + t * 0.4),
                                blurRadius: 14 + t * 12,
                                spreadRadius: 1 + t * 3),
                          ]
                        : null,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Transform.rotate(
                        angle: _a1, child: Die(face: _f1, size: widget.size)),
                    SizedBox(width: widget.size * 0.28),
                    Transform.rotate(
                        angle: _a2, child: Die(face: _f2, size: widget.size)),
                  ]),
                ),
              );
            },
          ),
        ),
      );
}

/// One die with pips.
class Die extends StatelessWidget {
  /// Creates a die.
  const Die({super.key, required this.face, this.size = 48});

  /// Face 1–6.
  final int face;

  /// Side length.
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.square(size), painter: _DiePainter(face.clamp(1, 6)));
}

class _DiePainter extends CustomPainter {
  _DiePainter(this.face);
  final int face;

  static const _pips = {
    1: [(0.5, 0.5)],
    2: [(0.27, 0.27), (0.73, 0.73)],
    3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
    4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
    5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
    6: [
      (0.27, 0.24),
      (0.73, 0.24),
      (0.27, 0.5),
      (0.73, 0.5),
      (0.27, 0.76),
      (0.73, 0.76)
    ],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final r =
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.2));
    canvas.drawRRect(
        r.shift(Offset(0, s * 0.06)), Paint()..color = Colors.black38);
    canvas.drawRRect(
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFE6E0D4)],
          ).createShader(Offset.zero & size));
    canvas.drawRRect(
        r,
        Paint()
          ..color = const Color(0xFFBDB4A2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1, s * 0.02));
    final pip = Paint()
      ..color = face == 1 ? const Color(0xFFC62828) : const Color(0xFF26201A);
    for (final (x, y) in _pips[face]!) {
      canvas.drawCircle(
          Offset(x * s, y * s), s * (face == 1 ? 0.12 : 0.09), pip);
    }
  }

  @override
  bool shouldRepaint(_DiePainter old) => old.face != face;
}
