import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyapari_app/services/transport.dart';
import 'package:vyapari_app/services/voice.dart';
import 'package:vyapari_app/state/game_controller.dart';
import 'package:vyapari_app/widgets/board.dart';
import 'package:vyapari_app/widgets/talk.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import 'helpers.dart';

void main() {
  group('board', () {
    for (final side in [360.0, 768.0, 1080.0, 2160.0]) {
      test('geometry at $side px: square, fully tiled, text ≥ 10 px', () {
        final g = BoardGeometry(side);
        expect(g.fontSize, greaterThanOrEqualTo(minBoardFont));
        final full = Offset.zero & Size(side, side);
        for (var i = 0; i < 40; i++) {
          final r = g.tileRect(i);
          expect(full.contains(r.topLeft), isTrue, reason: 'tile $i');
          expect(r.right, lessThanOrEqualTo(side + 0.01));
          expect(r.bottom, lessThanOrEqualTo(side + 0.01));
          expect(g.hitTest(r.center), i);
        }
        // The four sides meet exactly at the corners.
        expect(g.corner * 2 + g.edge * 9, closeTo(side, 0.001));
      });
    }

    for (final size in const [
      Size(360, 740),
      Size(1440, 900),
      Size(3840, 2160)
    ]) {
      testWidgets('draws square and fully visible at ${size.width.toInt()} px',
          (tester) async {
        final s = withOwned(started(n: 4), 'p1', [37, 39], houses: 5);
        await pumpWith(tester, Scaffold(body: BoardView(state: s)),
            view: GameView(state: s, me: 'p0'), size: size);
        expect(tester.takeException(), isNull);
        final box = tester.renderObject<RenderBox>(find
            .descendant(
                of: find.byType(BoardView), matching: find.byType(CustomPaint))
            .first);
        expect(box.size.width, box.size.height);
        expect(box.size.width, lessThanOrEqualTo(size.shortestSide));
      });
    }

    testWidgets('golden boards at 3 sizes', (tester) async {
      var s = withOwned(started(n: 4), 'p1', [37, 39], houses: 5);
      s = withOwned(s, 'p2', [31, 32, 34], houses: 2);
      for (final size in const [360.0, 800.0, 1440.0]) {
        await pumpWith(
            tester,
            RepaintBoundary(
                key: const ValueKey('board'),
                child: SizedBox(
                    width: size, height: size, child: BoardView(state: s))),
            view: GameView(state: s, me: 'p0'),
            size: Size(size, size));
        await expectLater(find.byKey(const ValueKey('board')),
            matchesGoldenFile('goldens/board_${size.toInt()}.png'));
      }
    }, tags: ['golden']);

    /// Pumps a board for [s] whose feed holds the events of [steps].
    Future<GlobalKey<BoardViewState>> boardWith(
        WidgetTester tester, GameState s) async {
      final c = await pumpWith(tester, const SizedBox(),
          view: GameView(state: s, me: 'p0'));
      final key = GlobalKey<BoardViewState>();
      await tester.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
              home: Scaffold(body: BoardView(key: key, state: s)))));
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      return key;
    }

    Future<void> feedTo(WidgetTester tester, GlobalKey<BoardViewState> key,
        GameState s, List<(int, GameEvent)> feed) async {
      await tester.pumpWidget(UncontrolledProviderScope(
          container: ProviderContainer(),
          child: MaterialApp(
              home: Scaffold(
                  body: BoardView(
                      key: key,
                      state: s,
                      feed: feed,
                      hop: const Duration(milliseconds: 200))))));
    }

    /// Positions p0 is shown at, sampled until the replay finishes.
    Future<List<int>> track(
        WidgetTester tester, GlobalKey<BoardViewState> key, String id) async {
      final seen = <int>[key.currentState!.shown[id]!];
      for (var t = 0; t < 600 && (key.currentState?.busy ?? false); t++) {
        await tester.pump(const Duration(milliseconds: 20));
        final now = key.currentState!.shown[id]!;
        if (seen.last != now) seen.add(now);
        // Tap away card pop-ups as a player would.
      }
      return seen;
    }

    testWidgets(
        'a 7-tile move passing Start hops through each tile, one per hop',
        (tester) async {
      final s0 = withPlayer(started(), 'p0', (p) => p.copyWith(position: 36));
      final key = await boardWith(tester, s0);
      final r = apply(const Roll('p0', 3, 4), s0); // 36 → 3, passing Start
      var seq = 0;
      await feedTo(
          tester, key, r.state, [for (final e in r.events) (++seq, e)]);
      final sw = Duration.zero;
      final seen = await track(tester, key, 'p0');
      expect(seen, [36, 37, 38, 39, 0, 1, 2, 3]);
      expect(sw, Duration.zero);
      expect(key.currentState!.busy, isFalse);
    });

    testWidgets(
        'a card move is shown after the dice move, never as one long jump',
        (tester) async {
      // p0 on 39 rolls 1+2 → Undiyal (2), draws "Advance to Start" → 0.
      var s0 = withPlayer(started(), 'p0', (p) => p.copyWith(position: 39));
      s0 = s0.copyWith(
          decks: Decks(
              vaaippu: s0.decks.vaaippu,
              undiyal: ['u01', ...s0.decks.undiyal.where((c) => c != 'u01')]));
      final key = await boardWith(tester, s0);
      final r = apply(const Roll('p0', 1, 2), s0);
      expect(r.state.player('p0')!.position, 0);
      var seq = 0;
      await feedTo(
          tester, key, r.state, [for (final e in r.events) (++seq, e)]);
      final seen = <int>[39];
      var sawCard = false;
      for (var t = 0; t < 800 && key.currentState!.busy; t++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byKey(const ValueKey('card-popup')).evaluate().isNotEmpty) {
          sawCard = true;
          expect(find.textContaining('Advance to Start'), findsOneWidget);
          expect(seen.last, 2,
              reason: 'card shows once the token reached Undiyal');
        }
        final now = key.currentState!.shown['p0']!;
        if (seen.last != now) seen.add(now);
      }
      expect(sawCard, isTrue);
      // Dice move 39 → 0 → 1 → 2, card, then the card's move 2 → … → 0.
      expect(seen.sublist(0, 4), [39, 0, 1, 2]);
      expect(seen.last, 0);
      expect(seen.length, 4 + 38,
          reason: 'the card move hops every tile to Start');
    });

    testWidgets('go back 3 hops backwards; jail jumps straight there',
        (tester) async {
      var s0 = withPlayer(started(), 'p0', (p) => p.copyWith(position: 4));
      s0 = s0.copyWith(
          decks: Decks(
              vaaippu: ['v09', ...s0.decks.vaaippu.where((c) => c != 'v09')],
              undiyal: s0.decks.undiyal));
      final key = await boardWith(tester, s0);
      final r = apply(const Roll('p0', 1, 2), s0); // → 7 Vaaippu, back 3 → 4
      var seq = 0;
      await feedTo(
          tester, key, r.state, [for (final e in r.events) (++seq, e)]);
      final seen = await track(tester, key, 'p0');
      expect(seen, [4, 5, 6, 7, 6, 5, 4]);
    });
  });

  group('voice', () {
    testWidgets('picking 2 players makes them exactly the recipients',
        (tester) async {
      final c = await pumpWith(
          tester, const Scaffold(floatingActionButton: TalkButton()),
          view: GameView(state: started(n: 4), me: 'p0'));
      await tester.tap(find.byKey(const ValueKey('talk-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('recipient-p1')));
      await tester.tap(find.byKey(const ValueKey('recipient-p3')));
      await tester.pump();
      expect(c.read(voiceProvider).recipients, unorderedEquals(['p1', 'p3']));
      await tester.tap(find.byKey(const ValueKey('recipient-broadcast')));
      await tester.pump();
      expect(c.read(voiceProvider).recipients, isEmpty);
    });

    test('holding 20 s stops at 15 s and sends to the chosen players', () {
      fakeAsync((fa) {
        final rec = FakeRecorder();
        final fake = FakeTransport(
            reply: (m) => m is Hello
                ? [
                    Welcome(
                        playerId: 'p0', sessionToken: 't', state: started(n: 4))
                  ]
                : []);
        final c = ProviderContainer(overrides: [
          clipRecorderProvider.overrideWithValue(rec),
          clipPlayerProvider.overrideWithValue(FakePlayer()),
        ]);
        withClock(Clock(() => DateTime(2026).add(fa.elapsed)), () {
          c
              .read(gameProvider.notifier)
              .playOffline(fake, name: 'A', token: Token.kite);
          fa.flushMicrotasks();
          final voice = c.read(voiceProvider.notifier);
          voice.setRecipients(['p1', 'p2']);
          voice.startTalking();
          fa.flushMicrotasks();
          expect(rec.recording, isTrue);
          fa.elapse(const Duration(seconds: 20)); // still "holding"
          expect(rec.recording, isFalse);
          expect(rec.stops, 1);
          expect(fake.voice, hasLength(1));
          final frame = VoiceFrame.decode(fake.voice.single)!;
          expect(frame.header.to, ['p1', 'p2']);
          expect(frame.header.durationMs, 15000);
          voice.stopAndSend(); // the late release does nothing more
          fa.flushMicrotasks();
          expect(fake.voice, hasLength(1));
        });
        c.dispose();
      });
    });

    VoiceFrame clip(String id, String from, {int ms = 500}) => VoiceFrame(
        VoiceHeader(clipId: id, from: from, codec: 'opus-ogg', durationMs: ms),
        Uint8List(10));

    test(
        'clips arriving together play in order without overlap; muted are skipped',
        () async {
      final player = FakePlayer();
      final c = ProviderContainer(
          overrides: [clipPlayerProvider.overrideWithValue(player)]);
      final voice = c.read(voiceProvider.notifier);
      voice.toggleMute('p9');
      voice.receive(clip('a', 'p1', ms: 60));
      voice.receive(clip('muted', 'p9', ms: 60));
      voice.receive(clip('b', 'p2', ms: 60));
      voice.receive(clip('c', 'p3', ms: 60));
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(player.timeline,
          ['start a', 'end a', 'start b', 'end b', 'start c', 'end c']);
      expect(c.read(voiceProvider).recent.map((f) => f.header.clipId),
          ['a', 'b', 'c']);
      // Replay a missed clip.
      voice.replay(c.read(voiceProvider).recent.first);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(player.timeline.last, 'end a');
      c.dispose();
    });

    test('only the last 5 clips are kept for replay', () async {
      final c = ProviderContainer(
          overrides: [clipPlayerProvider.overrideWithValue(FakePlayer())]);
      final voice = c.read(voiceProvider.notifier);
      for (var i = 0; i < 8; i++) {
        voice.receive(clip('c$i', 'p1', ms: 1));
      }
      expect(c.read(voiceProvider).recent.map((f) => f.header.clipId),
          ['c3', 'c4', 'c5', 'c6', 'c7']);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      c.dispose();
    });
  });

  test('a full offline game against bots plays to the end, then rematch',
      () async {
    final c = ProviderContainer();
    final game = c.read(gameProvider.notifier);
    final t = OfflineTransport(india(), botDelay: Duration.zero, pace: false);
    await game.playOffline(t, name: 'Me', token: Token.kite);
    game.send(const SetRulesMsg(HouseRules(maxTurns: 40, auctions: false)));
    for (var i = 0; i < 3; i++) {
      game.send(const AddBotMsg(level: BotLevel.medium));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.read(gameProvider).state!.players, hasLength(4));
    game.send(const SimpleIntent('start'));
    final me = MediumBot(SeededRandomSource(1));
    var guard = 0;
    while (c.read(gameProvider).state!.phase != GamePhase.gameOver &&
        guard++ < 20000) {
      final v = c.read(gameProvider);
      final s = v.state!;
      for (final a in me.candidates(s, v.me!)) {
        if (legalForTest(s, a)) {
          game.act(a);
          break;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final end = c.read(gameProvider).state!;
    expect(end.phase, GamePhase.gameOver);
    expect(end.totalMoney, end.startingTotal);
    final ids = end.players.map((p) => p.id).toSet();
    game.send(const SimpleIntent('rematch'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final again = c.read(gameProvider).state!;
    expect(again.phase, GamePhase.lobby);
    expect(again.players.map((p) => p.id).toSet(), ids);
    c.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('bundled board files match assets/boards/india', () {
    for (final f in ['board.json', 'cards.json']) {
      expect(File('assets/boards/india/$f').readAsStringSync(),
          File('../../assets/boards/india/$f').readAsStringSync(),
          reason: 'run tool/sync_assets.sh after editing the board');
    }
  });
}

/// Whether the engine accepts [a] (fake dice for roll intents).
bool legalForTest(GameState s, GameAction a) =>
    apply(a is Roll && !a.hasDice ? Roll(a.playerId, 1, 2) : a, s).ok;
