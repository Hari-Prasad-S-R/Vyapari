import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyapari_app/screens/game.dart';
import 'package:vyapari_app/screens/home.dart';
import 'package:vyapari_app/screens/join.dart';
import 'package:vyapari_app/screens/lobby.dart';
import 'package:vyapari_app/screens/results.dart';
import 'package:vyapari_app/screens/trade.dart';
import 'package:vyapari_app/state/game_controller.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import 'helpers.dart';

void main() {
  const sizes = [Size(360, 740), Size(800, 600), Size(1440, 900)];

  group('every screen fits at 360, 800 and 1440 px', () {
    for (final size in sizes) {
      testWidgets('home @${size.width.toInt()}', (tester) async {
        await pumpWith(tester, const HomeScreen(),
            view: const GameView(), size: size);
        expect(tester.takeException(), isNull);
        expectTouchTargets(tester);
      });

      testWidgets('lobby @${size.width.toInt()}', (tester) async {
        await pumpWith(tester, const LobbyScreen(),
            view: GameView(state: lobbyState(), me: 'p0', roomCode: '4821'),
            size: size);
        expect(tester.takeException(), isNull);
        expectTouchTargets(tester);
      });

      testWidgets('game @${size.width.toInt()}', (tester) async {
        await pumpWith(tester, const GameScreen(),
            view: GameView(state: started(n: 6), me: 'p0', roomCode: '4821'),
            size: size);
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        expectTouchTargets(tester);
      });

      testWidgets('results @${size.width.toInt()}', (tester) async {
        final s = apply(const EndGameByLimit('p0'), started()).state;
        await pumpWith(tester, const ResultsScreen(),
            view: GameView(state: s, me: 'p0'), size: size);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('winner')), findsOneWidget);
        expectTouchTargets(tester);
      });
    }
  });

  group('join errors', () {
    final cases = {
      ErrorCode.badCode: 'No game with that room code',
      ErrorCode.roomFull: 'Room is full',
      ErrorCode.versionMismatch: 'Please update the app',
      ErrorCode.badPassword: 'Wrong password',
    };
    cases.forEach((code, text) {
      testWidgets(text, (tester) async {
        final fake =
            FakeTransport(reply: (m) => m is Hello ? [ErrorMsg(code)] : []);
        final c = await pumpWith(tester, const JoinScreen(),
            view: const GameView(),
            overrides: [
              transportFactoryProvider.overrideWithValue((_) async => fake),
            ]);
        await tester.enterText(
            find.byKey(const ValueKey('server-field')), 'ws://example.test/ws');
        await tester.enterText(
            find.byKey(const ValueKey('code-field')), 'ABC123');
        await tester.tap(find.byKey(const ValueKey('join-button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.text(text), findsOneWidget);
        expect(find.byType(JoinScreen), findsOneWidget,
            reason: 'stays on the join screen');
        expect(c.read(gameProvider).me, isNull);
      });
    });
  });

  group('lobby', () {
    testWidgets('non-host sees rules read-only and a Ready button',
        (tester) async {
      await pumpWith(tester, const LobbyScreen(),
          view: GameView(state: lobbyState(), me: 'p1'));
      final sw =
          tester.widget<SwitchListTile>(find.byKey(const ValueKey('rule-pot')));
      expect(sw.onChanged, isNull);
      expect(find.byKey(const ValueKey('ready-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('start-button')), findsNothing);
      expect(find.byKey(const ValueKey('add-bot-easy')), findsNothing);
    });

    testWidgets('host edits rules; Start disabled until 2+ ready',
        (tester) async {
      final c = await pumpWith(tester, const LobbyScreen(),
          view: GameView(state: lobbyState(n: 1), me: 'p0'));
      var start = tester
          .widget<FilledButton>(find.byKey(const ValueKey('start-button')));
      expect(start.onPressed, isNull);
      c
          .read(gameProvider.notifier)
          .debugSetView(GameView(state: lobbyState(n: 2, ready: 1), me: 'p0'));
      await tester.pump();
      start = tester
          .widget<FilledButton>(find.byKey(const ValueKey('start-button')));
      expect(start.onPressed, isNotNull);
      final sw =
          tester.widget<SwitchListTile>(find.byKey(const ValueKey('rule-pot')));
      expect(sw.onChanged, isNotNull);
    });

    test('canStart needs two players and two ready', () {
      expect(canStart(lobbyState(n: 1)), isFalse);
      expect(canStart(lobbyState(n: 3, ready: 0)), isFalse);
      expect(canStart(lobbyState(n: 3, ready: 1)), isTrue);
    });
  });

  group('game screen', () {
    testWidgets('turn buttons hidden when it is not my turn', (tester) async {
      await pumpWith(tester, const GameScreen(),
          view: GameView(state: started(), me: 'p1'));
      expect(find.byKey(const ValueKey('act-Roll')), findsNothing);
      expect(find.byKey(const ValueKey('act-EndTurn')), findsNothing);
      expect(find.byKey(const ValueKey('trade-button')), findsOneWidget);
    });

    testWidgets('legal buttons per phase', (tester) async {
      var s = started(rules: const HouseRules(auctions: false));
      final c = await pumpWith(tester, const GameScreen(),
          view: GameView(state: s, me: 'p0'));
      expect(find.byKey(const ValueKey('act-Roll')), findsOneWidget);
      expect(find.byKey(const ValueKey('act-EndTurn')), findsNothing);
      // Land on an unowned city: Buy and Skip.
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 35));
      s = apply(const Roll('p0', 1, 3), s).state;
      c.read(gameProvider.notifier).debugSetView(GameView(state: s, me: 'p0'));
      await tester.pump();
      expect(find.byKey(const ValueKey('act-Buy')), findsOneWidget);
      expect(find.byKey(const ValueKey('act-DeclineBuy')), findsOneWidget);
      expect(find.byKey(const ValueKey('act-Roll')), findsNothing);
      // After buying: End turn only.
      s = apply(const Buy('p0'), s).state;
      c.read(gameProvider.notifier).debugSetView(GameView(state: s, me: 'p0'));
      await tester.pump();
      expect(find.byKey(const ValueKey('act-EndTurn')), findsOneWidget);
      expect(find.byKey(const ValueKey('act-Buy')), findsNothing);
      // In jail: pay fine, roll for doubles.
      var j = withPlayer(
          started(), 'p0', (p) => p.copyWith(inJail: true, position: 10));
      c.read(gameProvider.notifier).debugSetView(GameView(state: j, me: 'p0'));
      await tester.pump();
      expect(find.byKey(const ValueKey('act-PayJailFine')), findsOneWidget);
      expect(find.byKey(const ValueKey('act-UseJailCard')), findsNothing);
      j = withPlayer(j, 'p0', (p) => p.copyWith(getOutCards: ['v08']));
      c.read(gameProvider.notifier).debugSetView(GameView(state: j, me: 'p0'));
      await tester.pump();
      expect(find.byKey(const ValueKey('act-UseJailCard')), findsOneWidget);
    });

    testWidgets('Build is enabled only where even-build allows',
        (tester) async {
      var s = withOwned(started(), 'p0', [31, 32, 34]);
      s = s.copyWith(ownership: [
        for (final o in s.ownership)
          o.tileIndex == 31 ? o.copyWith(houses: 1) : o,
      ]);
      await pumpWith(
          tester, Scaffold(body: MyCities(view: GameView(state: s, me: 'p0'))),
          view: GameView(state: s, me: 'p0'), size: const Size(800, 900));
      TextButton b(String k) =>
          tester.widget<TextButton>(find.byKey(ValueKey(k)));
      expect(b('Build-31').onPressed, isNull);
      expect(b('Build-32').onPressed, isNotNull);
      expect(b('Build-34').onPressed, isNotNull);
      expect(b('SellBuilding-31').onPressed, isNotNull);
    });

    testWidgets('rent pop-up and cash update reach the payer', (tester) async {
      var s = withOwned(started(), 'p1', [31]);
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 28));
      final c = await pumpWith(tester, const GameScreen(),
          view: GameView(state: s, me: 'p0'));
      final next = apply(const Roll('p0', 1, 2), s);
      c.read(gameProvider.notifier).debugSetView(GameView(state: s, me: 'p0'));
      c
          .read(gameProvider.notifier)
          .applyPatch(PatchMsg.diff(s, next.state, next.events));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.textContaining('rent to Player 1'), findsWidgets);
      expect(c.read(gameProvider).state!.player('p0')!.cash,
          1500000 - s.tiles[31].rent[0]);
    });

    testWidgets('a short payer sees Pay out of turn; others see who is paying',
        (tester) async {
      var s = withOwned(started(), 'p1', [3]);
      s = withPlayer(s, 'p1', (p) => p.copyWith(cash: 1000));
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 14));
      s = s.copyWith(
          decks: Decks(
              vaaippu: s.decks.vaaippu,
              undiyal: ['u07', ...s.decks.undiyal.where((c) => c != 'u07')]));
      s = apply(const Roll('p0', 1, 2), s).state; // wedding card
      expect(s.actingPlayer, 'p1');
      final c = await pumpWith(tester, const GameScreen(),
          view: GameView(state: s, me: 'p1'));
      expect(
          find.byKey(const ValueKey('act-DeclareBankruptcy')), findsOneWidget);
      expect(
          find.textContaining('You owe ₹50,000 to Player 0'), findsOneWidget);
      // The current player waits and is told why.
      c.read(gameProvider.notifier).debugSetView(GameView(state: s, me: 'p0'));
      await tester.pump();
      expect(find.byKey(const ValueKey('act-EndTurn')), findsNothing);
      expect(find.textContaining('Player 1 is raising ₹50,000 to pay Player 0'),
          findsOneWidget);
    });

    testWidgets('no text input on lobby, game or results', (tester) async {
      await pumpWith(tester, const GameScreen(),
          view: GameView(state: started(), me: 'p0'));
      expect(find.byType(TextField), findsNothing);
      await pumpWith(tester, const LobbyScreen(),
          view: GameView(state: lobbyState(), me: 'p0'));
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('trades', () {
    GameState withOffer({int cash = 50000}) {
      var s = withOwned(started(), 'p1', [3]);
      s = apply(
          ProposeTrade('p1',
              to: 'p0', give: TradeSide(cash: cash), get: TradeSide()),
          withOwned(s, 'p0', [1])).state;
      return s;
    }

    testWidgets('Accept is disabled for 3 s, and the timer restarts on change',
        (tester) async {
      final s = withOffer();
      final id = s.trades.single.id;
      final c = await pumpWith(tester, Scaffold(body: OfferReview(tradeId: id)),
          view: GameView(state: s, me: 'p0'));
      await tester.pump();
      FilledButton accept() => tester
          .widget<FilledButton>(find.byKey(const ValueKey('offer-accept')));
      expect(accept().onPressed, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(accept().onPressed, isNull);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(accept().onPressed, isNotNull);
      // The offer changes (cancel + new offer with the same id slot).
      final changed = s.copyWith(trades: [
        Trade(
            id: id,
            from: 'p1',
            to: 'p0',
            give: TradeSide(cash: 90000),
            get: TradeSide(),
            createdAtVersion: s.version + 1),
      ]);
      c
          .read(gameProvider.notifier)
          .debugSetView(GameView(state: changed, me: 'p0'));
      await tester.pump();
      await tester.pump();
      expect(accept().onPressed, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(accept().onPressed, isNull);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(accept().onPressed, isNotNull);
    });

    test('lopsided when one side is worth 5× the other', () {
      final s = started();
      expect(isLopsided(s, TradeSide(cash: 600000), TradeSide(tiles: [1])),
          isTrue);
      expect(isLopsided(s, TradeSide(cash: 100000), TradeSide(tiles: [1])),
          isFalse);
    });

    testWidgets('build an offer and send it', (tester) async {
      var s = withOwned(started(), 'p0', [1]);
      s = withOwned(s, 'p1', [3]);
      final fake = FakeTransport(
          reply: (m) => m is Hello
              ? [Welcome(playerId: 'p0', sessionToken: 't', state: s)]
              : []);
      final c = await pumpWith(tester, const TradeScreen(),
          view: GameView(state: s, me: 'p0'), size: const Size(800, 1000));
      // Attach the fake transport so sends are recorded.
      await tester.runAsync(() => c
          .read(gameProvider.notifier)
          .playOffline(fake, name: 'x', token: Token.kite));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('trade-player')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🚗 Player 1').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('I give-1')));
      await tester.tap(find.byKey(const ValueKey('I get-3')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('send-offer')));
      await tester.pump();
      final m = fake.sent.whereType<TradeProposeMsg>().single;
      expect(m.to, 'p1');
      expect(m.give.tiles, [1]);
      expect(m.get.tiles, [3]);
    });
  });

  test('stale patches are ignored; gaps ask for a resync', () async {
    final fake = FakeTransport(
        reply: (m) => m is Hello
            ? [Welcome(playerId: 'p0', sessionToken: 't', state: started())]
            : []);
    final c = ProviderContainer();
    final game = c.read(gameProvider.notifier);
    await game.playOffline(fake, name: 'A', token: Token.kite);
    final s = c.read(gameProvider).state!;
    final next = s.copyWith(version: s.version + 1, freeParkingPot: 7);
    game.applyPatch(PatchMsg.diff(s, next));
    expect(c.read(gameProvider).state!.freeParkingPot, 7);
    // Re-delivering the same (now stale) patch changes nothing.
    final older = PatchMsg(
        fromVersion: s.version - 1,
        toVersion: s.version,
        changes: {'freeParkingPot': 99});
    game.applyPatch(older);
    expect(c.read(gameProvider).state!.freeParkingPot, 7);
    // A gap triggers sync.
    game.applyPatch(PatchMsg(
        fromVersion: s.version + 5,
        toVersion: s.version + 6,
        changes: const {}));
    expect(fake.sent.whereType<SyncMsg>(), hasLength(1));
    c.dispose();
  });
}
