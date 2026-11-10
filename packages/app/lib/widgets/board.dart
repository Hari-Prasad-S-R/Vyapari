import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import '../ui.dart';
import 'dice.dart';

/// Smallest font used on the board.
const minBoardFont = 10.0;

/// Time a token takes to hop one tile.
const hopTime = Duration(milliseconds: 200);

/// How long a drawn card stays up (tap to skip).
const cardTime = Duration(milliseconds: 2800);

/// How long a money message stays up.
const toastTime = Duration(milliseconds: 1300);

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
    final t = corner * 0.24;
    return switch (side(i)) {
      0 => Rect.fromLTWH(r.left, r.top, r.width, t),
      1 => Rect.fromLTWH(r.right - t, r.top, t, r.height),
      2 => Rect.fromLTWH(r.left, r.bottom - t, r.width, t),
      _ => Rect.fromLTWH(r.left, r.top, t, r.height),
    };
  }

  /// Owner stripe on the outer edge of tile [i].
  Rect ownerRect(int i) {
    final r = tileRect(i);
    final t = max(3.0, corner * 0.07);
    return switch (side(i)) {
      0 => Rect.fromLTWH(r.left, r.bottom - t, r.width, t),
      1 => Rect.fromLTWH(r.left, r.top, t, r.height),
      2 => Rect.fromLTWH(r.left, r.top, r.width, t),
      _ => Rect.fromLTWH(r.right - t, r.top, t, r.height),
    };
  }

  /// The middle of the board.
  Rect get centre =>
      Rect.fromLTWH(corner, corner, size - 2 * corner, size - 2 * corner);

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

/// Board palette (the board looks the same in light and dark mode, like a
/// real board on a table).
abstract final class BoardColors {
  /// Tile face.
  static const tile = Color(0xFFFFFBF2);

  /// Tile outline.
  static const line = Color(0xFFCFC3A8);

  /// Tile text.
  static const ink = Color(0xFF2B2118);

  /// Centre gradient.
  static const feltLight = Color(0xFF0F7A64);

  /// Centre gradient edge.
  static const feltDark = Color(0xFF07423A);

  /// Gold trim and logo.
  static const gold = Color(0xFFF2B33D);
}

Color _cornerColor(CornerKind k) => switch (k) {
      CornerKind.start => const Color(0xFF2E7D32),
      CornerKind.jail => const Color(0xFFEF6C00),
      CornerKind.freeParking => const Color(0xFF00838F),
      CornerKind.goToJail => const Color(0xFFC62828),
    };

String _icon(Tile t) => switch (t.type) {
      TileType.card => t.deck == Deck.vaaippu ? '❓' : '🪙',
      TileType.tax => '💸',
      TileType.transport => switch (t.name) {
          'Railways' => '🚆',
          'Airline' => '✈️',
          'Metro' => '🚇',
          _ => '🚢',
        },
      TileType.utility => t.name.contains('Water') ? '💧' : '⚡',
      TileType.corner => switch (t.corner!) {
          CornerKind.start => '🏁',
          CornerKind.jail => '🔒',
          CornerKind.freeParking => '☕',
          CornerKind.goToJail => '👮',
        },
      TileType.city => '',
    };

class _BoardPainter extends CustomPainter {
  _BoardPainter(this.s, this.fontTick);
  final GameState s;

  /// Bumped when web fonts (emoji) finish loading, to repaint.
  final int fontTick;

  @override
  void paint(Canvas canvas, Size size) {
    final g = BoardGeometry(size.width);
    final full = Offset.zero & size;
    // Board base and the felt centre.
    canvas.drawRRect(RRect.fromRectAndRadius(full, const Radius.circular(6)),
        Paint()..color = BoardColors.line);
    final c = g.centre;
    canvas.drawRect(
        c,
        Paint()
          ..shader = const RadialGradient(
            colors: [BoardColors.feltLight, BoardColors.feltDark],
            radius: 0.75,
          ).createShader(c));
    canvas.drawRect(
        c.deflate(c.width * 0.035),
        Paint()
          ..color = BoardColors.gold.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.0, c.width * 0.006));

    final line = Paint()
      ..color = BoardColors.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final t in s.tiles) {
      final r = g.tileRect(t.index);
      final o = s.ownershipOf(t.index);
      if (t.type == TileType.corner) {
        _corner(canvas, g, t, r);
        continue;
      }
      canvas.drawRect(r, Paint()..color = BoardColors.tile);
      var label = r;
      if (t.type == TileType.city ||
          t.type == TileType.transport ||
          t.type == TileType.utility) {
        final band = g.bandRect(t.index);
        final base = t.type == TileType.city
            ? hexColor(t.color)
            : const Color(0xFF546E7A);
        canvas.drawRect(
            band,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(base, Colors.white, 0.25)!, base],
              ).createShader(band));
        label = _below(r, band, g.side(t.index));
        if (o != null && o.houses > 0) _buildings(canvas, band, o.houses);
      }
      if (o != null) {
        canvas.drawRect(
            g.ownerRect(t.index), Paint()..color = playerColor(s, o.ownerId));
      }
      final icon = _icon(t);
      final showPrice = t.price > 0 && g.edge >= 44;
      final price = t.type == TileType.tax
          ? formatRupees(t.amount)
          : formatRupees(t.price);
      final inner = label.deflate(2);
      _text(canvas, inner, [
        if (icon.isNotEmpty) (icon, g.fontSize * 1.25, FontWeight.normal),
        (
          _fitWords(t.name, inner.width, g.fontSize),
          g.fontSize,
          FontWeight.w700
        ),
        if (showPrice || (t.type == TileType.tax && g.edge >= 44))
          (price, g.fontSize * 0.9, FontWeight.w500),
      ]);
      if (o != null && o.mortgaged) {
        canvas.drawRect(r, Paint()..color = const Color(0xAA7A7A7A));
        _text(
            canvas,
            r,
            [
              (
                'MORTGAGED',
                max(minBoardFont * 0.8, g.fontSize * 0.75),
                FontWeight.w800
              )
            ],
            color: Colors.white);
      }
      canvas.drawRect(r, line);
    }
    // Centre logo.
    _text(
        canvas,
        Rect.fromLTWH(c.left, c.top + c.height * 0.06, c.width, c.height * 0.2),
        [
          ('VYAPARI', max(minBoardFont, size.width * 0.07), FontWeight.w900),
        ],
        color: BoardColors.gold,
        shadow: true);
  }

  void _corner(Canvas canvas, BoardGeometry g, Tile t, Rect r) {
    final col = _cornerColor(t.corner!);
    canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(col, Colors.white, 0.18)!, col],
          ).createShader(r));
    final sub = switch (t.corner!) {
      CornerKind.start => 'Collect ${formatRupees(s.config.salary)}',
      CornerKind.jail => 'Just visiting',
      CornerKind.freeParking => s.rules.freeParkingPot && s.freeParkingPot > 0
          ? 'Pot ${formatRupees(s.freeParkingPot)}'
          : 'Relax',
      CornerKind.goToJail => 'Go to Jail',
    };
    _text(
        canvas,
        r.deflate(3),
        [
          (_icon(t), g.fontSize * 2.2, FontWeight.normal),
          (
            switch (t.corner!) {
              CornerKind.start => 'START',
              CornerKind.jail => 'JAIL',
              _ => t.name,
            },
            g.fontSize * 1.05,
            FontWeight.w900
          ),
          if (g.corner >= 60) (sub, g.fontSize * 0.85, FontWeight.w500),
        ],
        color: Colors.white);
    canvas.drawRect(
        r,
        Paint()
          ..color = BoardColors.line
          ..style = PaintingStyle.stroke);
  }

  /// Keeps words whole: each word that does not fit [width] is cut to the
  /// letters that do, plus a dot ("Visakhapatnam" → "Visak."). Tap a tile
  /// for its full name.
  String _fitWords(String name, double width, double size) {
    double w(String t) => (TextPainter(
          text: TextSpan(
              text: t,
              style: TextStyle(fontSize: size, fontWeight: FontWeight.w700)),
          textDirection: TextDirection.ltr,
        )..layout())
            .width;
    return name.split(' ').map((word) {
      if (w(word) <= width) return word;
      for (var n = word.length - 1; n >= 2; n--) {
        final cut = '${word.substring(0, n)}.';
        if (w(cut) <= width) return cut;
      }
      return '${word.substring(0, min(2, word.length))}.';
    }).join(' ');
  }

  Rect _below(Rect r, Rect band, int side) => switch (side) {
        0 => Rect.fromLTRB(r.left, band.bottom, r.right, r.bottom),
        1 => Rect.fromLTRB(r.left, r.top, band.left, r.bottom),
        2 => Rect.fromLTRB(r.left, r.top, r.right, band.top),
        _ => Rect.fromLTRB(band.right, r.top, r.right, r.bottom),
      };

  /// Little green houses, or a red hotel, on the colour band.
  void _buildings(Canvas canvas, Rect band, int houses) {
    final vertical = band.height > band.width;
    final len = vertical ? band.height : band.width;
    final thick = vertical ? band.width : band.height;
    void house(Offset c, double w, Color col) {
      final h = w;
      final path = Path()
        ..moveTo(c.dx - w / 2, c.dy + h / 2)
        ..lineTo(c.dx - w / 2, c.dy - h * 0.05)
        ..lineTo(c.dx, c.dy - h / 2)
        ..lineTo(c.dx + w / 2, c.dy - h * 0.05)
        ..lineTo(c.dx + w / 2, c.dy + h / 2)
        ..close();
      canvas.drawPath(path, Paint()..color = col);
      canvas.drawPath(
          path,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
    }

    if (houses == 5) {
      house(
          band.center, min(thick * 0.85, len * 0.45), const Color(0xFFC62828));
      return;
    }
    final w = min(thick * 0.72, len / 4.6);
    for (var k = 0; k < houses; k++) {
      final pos = (k + 0.5) * len / 4;
      final c = vertical
          ? Offset(band.center.dx, band.top + pos)
          : Offset(band.left + pos, band.center.dy);
      house(c, w, const Color(0xFF2E7D32));
    }
  }

  void _text(Canvas canvas, Rect r, List<(String, double, FontWeight)> lines,
      {Color color = BoardColors.ink, bool shadow = false}) {
    final spans = <TextSpan>[];
    for (var k = 0; k < lines.length; k++) {
      final (text, size, weight) = lines[k];
      spans.add(TextSpan(
        text: k == 0 ? text : '\n$text',
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: 1.08,
          letterSpacing: weight == FontWeight.w900 ? 1.2 : 0,
          shadows: shadow
              ? const [
                  Shadow(
                      blurRadius: 6,
                      color: Colors.black54,
                      offset: Offset(0, 2))
                ]
              : null,
        ),
      ));
    }
    final tp = TextPainter(
      text: TextSpan(children: spans),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: max(1, (r.height / (minBoardFont * 1.1)).floor()),
      ellipsis: '…',
    )..layout(maxWidth: max(1, r.width));
    tp.paint(
        canvas,
        Offset(r.left + (r.width - tp.width) / 2,
            r.top + (r.height - tp.height) / 2));
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.s.version != s.version || old.fontTick != fontTick;
}

/// One thing the board shows, in order, while replaying events.
sealed class _Beat {
  const _Beat();
}

class _DiceBeat extends _Beat {
  const _DiceBeat(this.playerId, this.d1, this.d2);
  final String? playerId;
  final int d1;
  final int d2;
}

class _MoveBeat extends _Beat {
  const _MoveBeat(this.playerId, this.from, this.steps);
  final String playerId;
  final int from;
  final int steps;
}

class _JumpBeat extends _Beat {
  const _JumpBeat(this.playerId, this.to);
  final String playerId;
  final int to;
}

class _CardBeat extends _Beat {
  const _CardBeat(this.playerId, this.deck, this.text);
  final String? playerId;
  final Deck deck;
  final String text;
}

class _ToastBeat extends _Beat {
  const _ToastBeat(this.text);
  final String text;
}

/// Turns server events into beats the board can play one after another.
List<_Beat> _beatsFor(GameState s, GameEvent e) {
  final id = e.playerId;
  switch (e.type) {
    case 'rolled':
      return [
        _DiceBeat(id, e.data['d1'] as int? ?? 1, e.data['d2'] as int? ?? 1)
      ];
    case 'moved':
      if (id == null) return const [];
      return [
        _MoveBeat(id, e.data['from'] as int? ?? 0, e.data['steps'] as int? ?? 0)
      ];
    case 'jailed':
      if (id == null) return const [];
      return [_JumpBeat(id, s.jailIndex), _ToastBeat(e.text)];
    case 'card':
      final cardId = e.data['card'] as String?;
      final deck = (e.data['deck'] as String?) == 'undiyal'
          ? Deck.undiyal
          : Deck.vaaippu;
      final text = cardId == null
          ? e.text
          : s.cards
              .firstWhere((c) => c.id == cardId,
                  orElse: () => GameCard(
                      id: '',
                      deck: deck,
                      text: e.text,
                      effect: const CardEffect(type: CardEffectType.collect)))
              .text;
      return [_CardBeat(id, deck, text)];
    case 'rent' ||
          'tax' ||
          'bought' ||
          'salary' ||
          'auction_won' ||
          'auction_none' ||
          'pot' ||
          'bankrupt' ||
          'debt' ||
          'debt_paid' ||
          'jail_free' ||
          'jail_fine' ||
          'jail_paid' ||
          'jail_card' ||
          'speeding' ||
          'trade_accepted' ||
          'game_over':
      return [_ToastBeat(e.text)];
    default:
      return const [];
  }
}

/// Square board with tokens that hop tile by tile, tap-to-roll dice, card
/// pop-ups and money messages. Server events are replayed one at a time so
/// every move matches its dice.
class BoardView extends StatefulWidget {
  /// Creates the board.
  const BoardView({
    super.key,
    required this.state,
    this.feed = const [],
    this.emotes = const {},
    this.canRoll = false,
    this.onRoll,
    this.rollHint,
    this.centreExtra,
    this.onBusy,
    this.hop = hopTime,
  });

  /// Told when replay starts (true) and ends (false).
  final ValueChanged<bool>? onBusy;

  /// Game state to draw.
  final GameState state;

  /// Ordered game events with sequence numbers (newest last).
  final List<(int, GameEvent)> feed;

  /// Emotes to show over tokens (emote, time shown in ms).
  final Map<String, (Emote, int)> emotes;

  /// Whether tapping the dice rolls now.
  final bool canRoll;

  /// Called when the player taps the dice to roll.
  final VoidCallback? onRoll;

  /// Text under the dice when rolling is possible.
  final String? rollHint;

  /// Extra widget in the centre under the dice (auction status).
  final Widget? centreExtra;

  /// Time per tile hop.
  final Duration hop;

  @override
  State<BoardView> createState() => BoardViewState();
}

/// State of [BoardView]; exposes shown token positions for tests.
class BoardViewState extends State<BoardView> {
  /// Position each token is drawn at (lags the real one while replaying).
  final Map<String, int> shown = {};
  final List<_Beat> _queue = [];
  int _lastSeq = 0;
  bool _playing = false;
  String? _hopping;
  List<int> _dice = const [1, 1];
  bool _tumbling = false;
  bool _waitingRoll = false;
  Timer? _rollTimeout;
  _CardBeat? _card;
  Completer<void>? _cardDone;
  String? _toast;
  Timer? _emoteTimer;
  bool _disposed = false;
  int _fontTick = 0;
  final List<Timer> _fontTimers = [];

  /// Whether the board is still replaying moves.
  bool get busy => _playing || _queue.isNotEmpty;

  @override
  void initState() {
    super.initState();
    for (final p in widget.state.players) {
      shown[p.id] = p.position;
    }
    if (widget.state.lastDice.length == 2) _dice = widget.state.lastDice;
    _lastSeq = widget.feed.isEmpty ? 0 : widget.feed.last.$1;
    // On the web, emoji fonts arrive after the first paint; repaint a few
    // times so tile icons never stay as empty boxes.
    for (final ms in [600, 1500, 3500, 8000]) {
      _fontTimers.add(Timer(Duration(milliseconds: ms), () {
        if (mounted) setState(() => _fontTick++);
      }));
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
    var added = false;
    for (final (seq, e) in widget.feed) {
      if (seq <= _lastSeq) continue;
      _lastSeq = seq;
      _queue.addAll(_beatsFor(widget.state, e));
      added = true;
    }
    if (added) {
      unawaited(_play());
    } else if (!busy) {
      _syncToState();
    }
  }

  /// Snaps tokens to the real positions (joins, resyncs, rematch).
  void _syncToState() {
    for (final p in widget.state.players) {
      shown[p.id] = p.position;
    }
    shown.removeWhere((id, _) => widget.state.player(id) == null);
  }

  Future<void> _wait(Duration d) => Future<void>.delayed(d);

  Future<void> _play() async {
    if (_playing) return;
    _playing = true;
    _notifyBusy(true);
    while (_queue.isNotEmpty && !_disposed) {
      final beat = _queue.removeAt(0);
      switch (beat) {
        case _DiceBeat():
          _rollTimeout?.cancel();
          setState(() => _tumbling = true);
          await _wait(const Duration(milliseconds: 650));
          if (_disposed) break;
          setState(() {
            _tumbling = false;
            _waitingRoll = false;
            _dice = [beat.d1, beat.d2];
          });
          await _wait(const Duration(milliseconds: 250));
        case _MoveBeat():
          final dir = beat.steps >= 0 ? 1 : -1;
          var at = beat.from;
          setState(() {
            shown[beat.playerId] = at;
            _hopping = beat.playerId;
          });
          for (var k = 0; k < beat.steps.abs() && !_disposed; k++) {
            at = (at + dir + 40) % 40;
            setState(() => shown[beat.playerId] = at);
            await _wait(widget.hop);
          }
          if (_disposed) break;
          setState(() => _hopping = null);
          await _wait(const Duration(milliseconds: 150));
        case _JumpBeat():
          setState(() => shown[beat.playerId] = beat.to);
          await _wait(const Duration(milliseconds: 400));
        case _CardBeat():
          final done = Completer<void>();
          _cardDone = done;
          setState(() => _card = beat);
          await Future.any([done.future, _wait(cardTime)]);
          if (_disposed) break;
          setState(() => _card = null);
          await _wait(const Duration(milliseconds: 200));
        case _ToastBeat():
          setState(() => _toast = beat.text);
          await _wait(toastTime);
          if (_disposed) break;
          setState(() => _toast = null);
      }
    }
    _playing = false;
    if (!_disposed) {
      setState(_syncToState);
      _notifyBusy(false);
    }
  }

  void _notifyBusy(bool b) {
    final cb = widget.onBusy;
    if (cb == null) return;
    // Providers may not change during build; report after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed || !b) cb(b);
    });
  }

  void _tapDice() {
    if (!widget.canRoll || _waitingRoll || busy) return;
    setState(() {
      _waitingRoll = true;
      _tumbling = true;
    });
    widget.onRoll?.call();
    // If the server refuses, stop spinning.
    _rollTimeout?.cancel();
    _rollTimeout = Timer(const Duration(seconds: 4), () {
      if (mounted && _waitingRoll) {
        setState(() {
          _waitingRoll = false;
          _tumbling = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    if (_playing) _notifyBusy(false);
    _emoteTimer?.cancel();
    _rollTimeout?.cancel();
    for (final t in _fontTimers) {
      t.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final side = min(c.maxWidth, c.maxHeight);
      final g = BoardGeometry(side);
      final s = widget.state;
      final now = DateTime.now().millisecondsSinceEpoch;
      final tokenSize = max(20.0, g.edge * 0.62);
      final centre = g.centre;
      final rollable = widget.canRoll && !busy && !_waitingRoll;
      final children = <Widget>[
        Positioned.fill(
          child: GestureDetector(
            onTapUp: (d) {
              final i = g.hitTest(d.localPosition);
              if (i != null) showTileDetails(context, s, i);
            },
            child: CustomPaint(painter: _BoardPainter(s, _fontTick)),
          ),
        ),
        Positioned.fromRect(
          rect: Rect.fromLTWH(centre.left, centre.top + centre.height * 0.26,
              centre.width, centre.height * 0.7),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DicePair(
              key: const ValueKey('dice'),
              d1: _dice[0],
              d2: _dice[1],
              size: max(30, centre.width * 0.17),
              tumbling: _tumbling,
              glow: rollable,
              onTap: rollable ? _tapDice : null,
            ),
            const SizedBox(height: 6),
            if (rollable && widget.rollHint != null)
              _Pill(widget.rollHint!,
                  key: const ValueKey('roll-hint'), strong: true),
            if (_toast != null)
              _Pill(_toast!, key: const ValueKey('board-toast')),
            if (widget.centreExtra != null && _toast == null)
              widget.centreExtra!,
          ]),
        ),
      ];
      final active = s.players.where((p) => !p.bankrupt).toList();
      for (var k = 0; k < active.length; k++) {
        final p = active[k];
        final pos = shown[p.id] ?? p.position;
        final r = g.tileRect(pos);
        final ox = (k % 3 - 1) * tokenSize * 0.42;
        final oy = (k ~/ 3 - 0.5) * tokenSize * 0.42;
        final at = r.center.translate(ox - tokenSize / 2, oy - tokenSize / 2);
        final hopping = _hopping == p.id;
        children.add(AnimatedPositioned(
          key: ValueKey('token-${p.id}'),
          duration: widget.hop * 0.8,
          curve: Curves.easeOut,
          left: at.dx,
          top: at.dy - (hopping ? tokenSize * 0.15 : 0),
          width: tokenSize,
          height: tokenSize,
          child: AnimatedScale(
            scale: hopping ? 1.18 : 1,
            duration: const Duration(milliseconds: 150),
            child: _Token(
                player: p,
                color: playerColor(s, p.id),
                size: tokenSize,
                current: p.id == s.currentPlayer),
          ),
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
      if (_card != null) {
        // The card scales down to fit any board size, so it is always whole.
        children.add(Positioned.fromRect(
          rect: centre.deflate(centre.width * 0.04),
          child: GestureDetector(
            onTap: () => _cardDone?.complete(),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: 280,
                  child: CardPopup(
                      key: const ValueKey('card-popup'),
                      deck: _card!.deck,
                      text: _card!.text,
                      who: s.player(_card!.playerId)?.name),
                ),
              ),
            ),
          ),
        ));
      }
      return Center(
        child: SizedBox(
          width: side,
          height: side,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(
                    blurRadius: 18, color: Colors.black38, offset: Offset(0, 6))
              ],
            ),
            child: Stack(clipBehavior: Clip.none, children: children),
          ),
        ),
      );
    });
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {super.key, this.strong = false});
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              strong ? BoardColors.gold : Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: strong ? BoardColors.ink : Colors.white,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                fontSize: 13)),
      );
}

/// A drawn Vaaippu or Undiyal card.
class CardPopup extends StatelessWidget {
  /// Creates the card.
  const CardPopup(
      {super.key, required this.deck, required this.text, this.who});

  /// Deck.
  final Deck deck;

  /// Card text.
  final String text;

  /// Who drew it.
  final String? who;

  @override
  Widget build(BuildContext context) {
    final vaaippu = deck == Deck.vaaippu;
    final col = vaaippu ? const Color(0xFFEF6C00) : const Color(0xFF2E7D32);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        color: BoardColors.tile,
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            color: col,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
                '${vaaippu ? '❓ VAAIPPU' : '🪙 UNDIYAL'}${who == null ? '' : ' · $who'}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: BoardColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('tap to continue',
                style: TextStyle(color: Colors.black45, fontSize: 11)),
          ),
        ]),
      ),
    );
  }
}

class _Token extends StatelessWidget {
  const _Token(
      {required this.player,
      required this.color,
      required this.size,
      required this.current});
  final Player player;
  final Color color;
  final double size;
  final bool current;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: player.name,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: max(2.5, size * 0.12)),
            boxShadow: [
              const BoxShadow(
                  blurRadius: 4, color: Colors.black45, offset: Offset(0, 2)),
              if (current)
                BoxShadow(
                    blurRadius: 10,
                    spreadRadius: 1,
                    color: color.withValues(alpha: 0.8)),
            ],
          ),
          alignment: Alignment.center,
          child: Text(tokenEmoji(player.token),
              style: TextStyle(fontSize: size * 0.5, height: 1)),
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
        Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
