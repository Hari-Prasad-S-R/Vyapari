import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import '../ui.dart';

/// Smallest font used on the board.
const minBoardFont = 10.0;

/// Board geometry for a square of side [size].
class BoardGeometry {
  /// Creates geometry.
  BoardGeometry(this.size)
      : corner = size * 0.13,
        edge = (size - 2 * size * 0.13) / 9;

  /// Side length.
  final double size;

  /// Corner tile side.
  final double corner;

  /// Short side of an edge tile.
  final double edge;

  /// Rectangle of tile [i] (0 = Start, bottom-right, then clockwise).
  Rect tileRect(int i) {
    final c = corner, w = edge, s = size;
    if (i == 0) return Rect.fromLTWH(s - c, s - c, c, c);
    if (i < 10) return Rect.fromLTWH(s - c - i * w, s - c, w, c);
    if (i == 10) return Rect.fromLTWH(0, s - c, c, c);
    if (i < 20) return Rect.fromLTWH(0, s - c - (i - 10) * w, c, w);
    if (i == 20) return const Offset(0, 0) & Size(c, c);
    if (i < 30) return Rect.fromLTWH(c + (i - 21) * w, 0, w, c);
    if (i == 30) return Rect.fromLTWH(s - c, 0, c, c);
    return Rect.fromLTWH(s - c, c + (i - 31) * w, c, w);
  }

  /// Side of the board tile [i] sits on: 0 bottom, 1 left, 2 top, 3 right.
  int side(int i) => i <= 10
      ? 0
      : i <= 20
          ? 1
          : i <= 30
              ? 2
              : 3;

  /// Colour band on the inner edge of tile [i].
  Rect bandRect(int i) {
    final r = tileRect(i);
    final t = corner * 0.22;
    return switch (side(i)) {
      0 => Rect.fromLTWH(r.left, r.top, r.width, t),
      1 => Rect.fromLTWH(r.right - t, r.top, t, r.height),
      2 => Rect.fromLTWH(r.left, r.bottom - t, r.width, t),
      _ => Rect.fromLTWH(r.left, r.top, t, r.height),
    };
  }

  /// Label font size (never below [minBoardFont]).
  double get fontSize => max(minBoardFont, edge * 0.2);

  /// Tile index at [p], or `null` for the centre.
  int? hitTest(Offset p) {
    for (var i = 0; i < 40; i++) {
      if (tileRect(i).contains(p)) return i;
    }
    return null;
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.s, this.dark);
  final GameState s;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final g = BoardGeometry(size.width);
    final bg = Paint()
      ..color = dark ? const Color(0xFF2B2418) : const Color(0xFFF6EBD3);
    canvas.drawRect(Offset.zero & size, bg);
    final line = Paint()
      ..color = dark ? Colors.white24 : Colors.brown.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final textColor = dark ? Colors.white : const Color(0xFF3E2723);
    for (final t in s.tiles) {
      final r = g.tileRect(t.index);
      canvas.drawRect(
          r,
          Paint()
            ..color = dark ? const Color(0xFF3A3122) : const Color(0xFFFFF8E7));
      canvas.drawRect(r, line);
      final o = s.ownershipOf(t.index);
      var label = r;
      if (t.type == TileType.city ||
          t.type == TileType.transport ||
          t.type == TileType.utility) {
        final band = g.bandRect(t.index);
        canvas.drawRect(band, Paint()..color = hexColor(t.color));
        label = _shrink(r, band, g.side(t.index));
        if (o != null && o.houses > 0) _drawBuildings(canvas, band, o.houses);
      }
      final icon = switch (t.type) {
        TileType.card => t.deck == Deck.vaaippu ? '❓ ' : '🪙 ',
        TileType.tax => '💸 ',
        TileType.transport => switch (t.name) {
            'Railways' => '🚆 ',
            'Airline' => '✈️ ',
            'Metro' => '🚇 ',
            _ => '🚢 ',
          },
        TileType.utility => t.name.contains('Water') ? '💧 ' : '⚡ ',
        TileType.corner => switch (t.corner!) {
            CornerKind.start => '➡️ ',
            CornerKind.jail => '🔒 ',
            CornerKind.freeParking => '☕ ',
            CornerKind.goToJail => '👮 ',
          },
        TileType.city => '',
      };
      final showPrice = t.price > 0 && g.edge >= 48;
      _text(canvas, label.deflate(1.5), '$icon${t.name}',
          showPrice ? formatRupees(t.price) : null, g.fontSize, textColor);
      if (o != null) {
        final c = playerColor(s, o.ownerId);
        final dot = _ownerDot(r, g.side(t.index), g.fontSize * 0.5);
        canvas.drawCircle(dot, g.fontSize * 0.45, Paint()..color = c);
        canvas.drawCircle(
            dot,
            g.fontSize * 0.45,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
        if (o.mortgaged) {
          canvas.drawRect(
              r, Paint()..color = Colors.grey.withValues(alpha: 0.55));
          _text(canvas, r, 'M', null, g.fontSize * 1.4, Colors.white,
              center: true);
        }
      }
    }
    // Centre title.
    final centre = Rect.fromLTWH(g.corner, g.corner, size.width - 2 * g.corner,
        size.width - 2 * g.corner);
    _text(canvas, centre.translate(0, -centre.height * 0.3), 'VYAPARI', null,
        max(minBoardFont, size.width * 0.06), saffron.withValues(alpha: 0.85),
        center: true, bold: true);
  }

  Rect _shrink(Rect r, Rect band, int side) => switch (side) {
        0 => Rect.fromLTRB(r.left, band.bottom, r.right, r.bottom),
        1 => Rect.fromLTRB(r.left, r.top, band.left, r.bottom),
        2 => Rect.fromLTRB(r.left, r.top, r.right, band.top),
        _ => Rect.fromLTRB(band.right, r.top, r.right, r.bottom),
      };

  Offset _ownerDot(Rect r, int side, double m) => switch (side) {
        0 => Offset(r.right - m - 2, r.bottom - m - 2),
        1 => Offset(r.left + m + 2, r.bottom - m - 2),
        2 => Offset(r.left + m + 2, r.top + m + 2),
        _ => Offset(r.right - m - 2, r.top + m + 2),
      };

  void _drawBuildings(Canvas canvas, Rect band, int houses) {
    final vertical = band.height > band.width;
    final len = vertical ? band.height : band.width;
    final thick = vertical ? band.width : band.height;
    if (houses == 5) {
      final hotel = vertical
          ? Rect.fromCenter(
              center: band.center, width: thick * 0.8, height: len * 0.5)
          : Rect.fromCenter(
              center: band.center, width: len * 0.5, height: thick * 0.8);
      canvas.drawRect(hotel, Paint()..color = const Color(0xFFC62828));
      return;
    }
    final sq = min(thick * 0.75, len / 5);
    for (var k = 0; k < houses; k++) {
      final pos = (k + 0.5) * len / 4;
      final c = vertical
          ? Offset(band.center.dx, band.top + pos)
          : Offset(band.left + pos, band.center.dy);
      canvas.drawRect(Rect.fromCenter(center: c, width: sq, height: sq),
          Paint()..color = const Color(0xFF2E7D32));
    }
  }

  void _text(
      Canvas canvas, Rect r, String text, String? sub, double size, Color color,
      {bool center = false, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(children: [
        TextSpan(
            text: text,
            style: TextStyle(
                fontSize: size,
                color: color,
                height: 1.05,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
        if (sub != null)
          TextSpan(
              text: '\n$sub',
              style: TextStyle(
                  fontSize: size, color: color.withValues(alpha: 0.8))),
      ]),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: max(1, (r.height / (size * 1.1)).floor()),
      ellipsis: '…',
    )..layout(maxWidth: max(1, r.width));
    final dy = center
        ? r.center.dy - tp.height / 2
        : r.top + (r.height - tp.height) / 2;
    tp.paint(canvas, Offset(r.left + (r.width - tp.width) / 2, dy));
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.s.version != s.version || old.dark != dark;
}

/// Square board with tokens, tap-for-details and emote bubbles.
class BoardView extends StatefulWidget {
  /// Creates the board.
  const BoardView({
    super.key,
    required this.state,
    this.emotes = const {},
    this.center,
    this.stepDuration = const Duration(milliseconds: 150),
  });

  /// Game state to draw.
  final GameState state;

  /// Emotes to show over tokens (emote, time shown in ms).
  final Map<String, (Emote, int)> emotes;

  /// Widget drawn in the middle of the board (dice, pop-ups).
  final Widget? center;

  /// Time per tile when a token moves.
  final Duration stepDuration;

  @override
  State<BoardView> createState() => BoardViewState();
}

/// State of [BoardView]; exposes shown token positions for tests.
class BoardViewState extends State<BoardView> {
  /// Position each token is drawn at (lags the real one while animating).
  final Map<String, int> shown = {};
  Timer? _timer;
  Timer? _emoteTimer;

  @override
  void initState() {
    super.initState();
    for (final p in widget.state.players) {
      shown[p.id] = p.position;
    }
    _emoteTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (widget.emotes.values.any((e) => now - e.$2 < 2600) && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(BoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    var moving = false;
    for (final p in widget.state.players) {
      final from = shown[p.id];
      if (from == null || p.inJail || p.bankrupt) {
        shown[p.id] = p.position;
      } else if (from != p.position) {
        final back = (from - p.position + 40) % 40;
        if (back <= 3) {
          shown[p.id] = p.position; // short backward move: jump
        } else {
          moving = true;
        }
      }
    }
    if (moving) _startStepping();
  }

  void _startStepping() {
    _timer?.cancel();
    // Keep any move under 2 s: long moves step faster.
    var maxSteps = 1;
    for (final p in widget.state.players) {
      final steps = ((p.position - (shown[p.id] ?? p.position)) + 40) % 40;
      maxSteps = max(maxSteps, steps);
    }
    final ms = min(widget.stepDuration.inMilliseconds, 1800 ~/ maxSteps);
    _timer = Timer.periodic(Duration(milliseconds: max(16, ms)), (t) {
      var still = false;
      setState(() {
        for (final p in widget.state.players) {
          final cur = shown[p.id] ?? p.position;
          if (cur != p.position) {
            shown[p.id] = (cur + 1) % 40;
            still = still || shown[p.id] != p.position;
          }
        }
      });
      if (!still) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emoteTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(builder: (context, c) {
      final side = min(c.maxWidth, c.maxHeight);
      final g = BoardGeometry(side);
      final s = widget.state;
      final now = DateTime.now().millisecondsSinceEpoch;
      final tokenSize = max(18.0, g.edge * 0.55);
      final children = <Widget>[
        Positioned.fill(
          child: GestureDetector(
            onTapUp: (d) {
              final i = g.hitTest(d.localPosition);
              if (i != null) showTileDetails(context, s, i);
            },
            child: CustomPaint(painter: _BoardPainter(s, dark)),
          ),
        ),
        if (widget.center != null)
          Positioned.fromRect(
            rect: Rect.fromLTWH(g.corner, g.corner, side - 2 * g.corner,
                    side - 2 * g.corner)
                .deflate(8),
            child: widget.center!,
          ),
      ];
      final active = s.players.where((p) => !p.bankrupt).toList();
      for (var k = 0; k < active.length; k++) {
        final p = active[k];
        final pos = shown[p.id] ?? p.position;
        final r = g.tileRect(pos);
        final ox = (k % 3 - 1) * tokenSize * 0.45;
        final oy = (k ~/ 3 - 1) * tokenSize * 0.45;
        final at = r.center.translate(ox - tokenSize / 2, oy - tokenSize / 2);
        children.add(Positioned(
          key: ValueKey('token-${p.id}'),
          left: at.dx,
          top: at.dy,
          width: tokenSize,
          height: tokenSize,
          child:
              _Token(player: p, color: playerColor(s, p.id), size: tokenSize),
        ));
        final e = widget.emotes[p.id];
        if (e != null && now - e.$2 < 2000) {
          children.add(Positioned(
            left: at.dx - tokenSize * 0.5,
            top: max(0, at.dy - tokenSize * 1.3),
            child: _Bubble(e.$1.label),
          ));
        }
      }
      return Center(
        child: SizedBox(
          width: side,
          height: side,
          child: Stack(clipBehavior: Clip.none, children: children),
        ),
      );
    });
  }
}

class _Token extends StatelessWidget {
  const _Token({required this.player, required this.color, required this.size});
  final Player player;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: player.name,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
          ),
          alignment: Alignment.center,
          child: Text(tokenEmoji(player.token),
              style: TextStyle(fontSize: size * 0.55, height: 1)),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(text,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black)),
        ),
      );
}

/// Shows price, rent table and owner of tile [i].
Future<void> showTileDetails(BuildContext context, GameState s, int i) {
  final t = s.tiles[i];
  final o = s.ownershipOf(i);
  final owner = s.player(o?.ownerId);
  List<Widget> rentRows() {
    switch (t.type) {
      case TileType.city:
        const labels = [
          'Rent',
          '1 house',
          '2 houses',
          '3 houses',
          '4 houses',
          'Hotel'
        ];
        return [
          for (var k = 0; k < 6; k++) _row(labels[k], formatRupees(t.rent[k])),
          _row('Full set (no houses)', formatRupees(t.rent[0] * 2)),
          _row('House cost', formatRupees(t.houseCost)),
        ];
      case TileType.transport:
        return [
          for (var k = 0; k < t.rent.length; k++)
            _row('${k + 1} owned', formatRupees(t.rent[k])),
        ];
      case TileType.utility:
        return [
          _row('One owned',
              'dice × ${t.rent[0]} × ${formatRupees(s.config.utilityUnit)}'),
          _row('Both owned',
              'dice × ${t.rent[1]} × ${formatRupees(s.config.utilityUnit)}'),
        ];
      case TileType.tax:
        return [_row('Pay', formatRupees(t.amount))];
      case TileType.card || TileType.corner:
        return const [];
    }
  }

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(children: [
        if (t.color != null)
          Container(
              width: 16,
              height: 16,
              color: hexColor(t.color),
              margin: const EdgeInsets.only(right: 8)),
        Expanded(child: Text(t.name)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (t.price > 0) _row('Price', formatRupees(t.price)),
        ...rentRows(),
        if (t.price > 0) _row('Mortgage value', formatRupees(t.mortgageValue)),
        if (o != null)
          _row('Owner',
              '${owner?.name ?? '?'}${o.mortgaged ? ' (mortgaged)' : ''}'),
        if (o != null && o.houses > 0)
          _row('Buildings', o.houses == 5 ? 'Hotel' : '${o.houses} house(s)'),
        if (t.type == TileType.card)
          Text(t.deck == Deck.vaaippu
              ? 'Vaaippu: take a chance card.'
              : 'Undiyal: open the community box.'),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Close'))
      ],
    ),
  );
}

Widget _row(String a, String b) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(a)),
        Text(b, style: const TextStyle(fontWeight: FontWeight.w600))
      ]),
    );
