import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyapari_app/widgets/board.dart';
import 'package:vyapari_core/vyapari_core.dart';

import 'helpers.dart';

void main() {
  for (final side in [300.0, 360.0, 640.0]) {
    testWidgets(
        'replaying a whole bot game on a ${side.toInt()} px board: no layout errors',
        (tester) async {
      tester.view.physicalSize = Size(side + 40, side + 40);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final start = started(n: 4, rules: const HouseRules(maxTurns: 30));
      final feed = botGameFeed(start);
      expect(feed.where((e) => e.$2.type == 'card'), isNotEmpty,
          reason: 'game should draw cards');
      final key = GlobalKey<BoardViewState>();
      Widget app(GameState s, List<(int, GameEvent)> f) => ProviderScope(
          child: MaterialApp(
              home: Scaffold(
                  body: Center(
                      child: SizedBox(
                          width: side,
                          height: side,
                          child: BoardView(
                              key: key,
                              state: s,
                              feed: f,
                              hop: const Duration(milliseconds: 10)))))));
      await tester.pumpWidget(app(start, const []));
      await tester.pumpWidget(app(start, feed));
      for (var t = 0; t < 4000 && key.currentState!.busy; t++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull,
            reason: 'layout error at step $t');
      }
      expect(key.currentState!.busy, isFalse);
      await tester.pump(const Duration(seconds: 9));
    });
  }

  testWidgets('card pop-up fits a small board, with no layout errors',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var s0 = withPlayer(started(), 'p0', (p) => p.copyWith(position: 9));
    s0 = s0.copyWith(
        decks: Decks(
            vaaippu: s0.decks.vaaippu,
            undiyal: ['u09', ...s0.decks.undiyal.where((c) => c != 'u09')]));
    final key = GlobalKey<BoardViewState>();
    Widget app(GameState s, List<(int, GameEvent)> feed) => ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: Center(
                    child: SizedBox(
                        width: 300,
                        height: 300,
                        child: BoardView(key: key, state: s, feed: feed))))));
    await tester.pumpWidget(app(s0, const []));
    final r = apply(const Roll('p0', 6, 2), s0);
    var seq = 0;
    await tester
        .pumpWidget(app(r.state, [for (final e in r.events) (++seq, e)]));
    for (var t = 0; t < 150; t++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byKey(const ValueKey('card-popup')).evaluate().isNotEmpty) break;
    }
    final f = find.byKey(const ValueKey('card-popup'));
    expect(f, findsOneWidget);
    final box = tester.renderObject<RenderBox>(f);
    final topLeft = box.localToGlobal(Offset.zero);
    final bottomRight = box.localToGlobal(box.size.bottomRight(Offset.zero));
    // Entirely inside the 300 px board, which is centred in 800 × 600.
    expect(topLeft.dx, greaterThanOrEqualTo(250));
    expect(bottomRight.dx, lessThanOrEqualTo(550));
    expect(topLeft.dy, greaterThanOrEqualTo(150));
    expect(bottomRight.dy, lessThanOrEqualTo(450));
    expect(find.textContaining('Income tax refund'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Play to the end: no layout errors at any point.
    for (var t = 0; t < 400 && key.currentState!.busy; t++) {
      await tester.pump(const Duration(milliseconds: 20));
      expect(tester.takeException(), isNull);
    }
    await tester.pump(const Duration(seconds: 9)); // font repaint timers
    expect(key.currentState!.busy, isFalse);
  });
}

/// Events of a real bot game (turn-limited), in order.
List<(int, GameEvent)> botGameFeed(GameState start, {int maxActions = 400}) {
  var s = start;
  final bots = {
    for (final p in s.players)
      p.id: MediumBot(SeededRandomSource(p.id.hashCode))
  };
  final dice = SeededRandomSource(7);
  final feed = <(int, GameEvent)>[];
  var seq = 0;
  for (var i = 0; i < maxActions && s.phase != GamePhase.gameOver; i++) {
    ApplyResult? r;
    if (s.phase == GamePhase.auction) {
      r = apply(CloseAuction(s.currentPlayer!), s);
    } else {
      final id = s.actingPlayer ?? s.currentPlayer!;
      r = botAct(
          bots[id]!, s, id, () => [dice.nextInt(6) + 1, dice.nextInt(6) + 1]);
    }
    if (r == null || !r.ok) break;
    s = r.state;
    for (final e in r.events) {
      feed.add((++seq, e));
    }
  }
  return feed;
}
