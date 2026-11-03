import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyapari_app/services/transport.dart';
import 'package:vyapari_app/services/voice.dart';
import 'package:vyapari_app/state/game_controller.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

/// The bundled India board.
BoardData india() => BoardData.parse(
      File('assets/boards/india/board.json').readAsStringSync(),
      File('assets/boards/india/cards.json').readAsStringSync(),
    );

/// A started game with [n] players p0..; p0 is host and moves first.
GameState started({int n = 3, HouseRules rules = const HouseRules()}) {
  var s = newLobby(roomId: '4821', board: india(), rules: rules);
  for (var i = 0; i < n; i++) {
    s = apply(JoinGame('p$i', name: 'Player $i', token: Token.values[i % 6]), s).state;
    s = apply(SetReady('p$i', ready: true), s).state;
  }
  return apply(StartGame('p0', seed: 1, openingRolls: {for (var i = 0; i < n; i++) 'p$i': 12 - i}), s)
      .state;
}

/// A lobby with [n] players p0.. (p0 host), [ready] of the others ready.
GameState lobbyState({int n = 3, int ready = 0}) {
  var s = newLobby(roomId: '4821', board: india());
  for (var i = 0; i < n; i++) {
    s = apply(JoinGame('p$i', name: 'Player $i', token: Token.values[i % 6]), s).state;
    if (i > 0 && i <= ready) s = apply(SetReady('p$i', ready: true), s).state;
  }
  return s;
}

/// Replaces player [id].
GameState withPlayer(GameState s, String id, Player Function(Player) f) =>
    s.copyWith(players: [for (final p in s.players) p.id == id ? f(p) : p]);

/// Gives [id] the [tiles].
GameState withOwned(GameState s, String id, List<int> tiles, {int houses = 0}) => s.copyWith(
      ownership: [
        ...s.ownership.where((o) => !tiles.contains(o.tileIndex)),
        for (final t in tiles) Ownership(tileIndex: t, ownerId: id, houses: houses),
      ],
    );

/// Records every message sent; replies via [reply].
class FakeTransport implements GameTransport {
  /// Creates a fake.
  FakeTransport({this.reply});

  /// Called for each sent message; return messages to deliver back.
  final List<ServerMessage> Function(ClientMessage m)? reply;

  /// Messages sent.
  final List<ClientMessage> sent = [];

  /// Voice frames sent.
  final List<Uint8List> voice = [];
  final _c = StreamController<Incoming>.broadcast();

  /// Pushes a server message.
  void push(ServerMessage m) => _c.add(IncomingMessage(m));

  @override
  Stream<Incoming> get incoming => _c.stream;

  @override
  void send(ClientMessage m, {String room = ''}) {
    sent.add(m);
    for (final r in reply?.call(m) ?? const <ServerMessage>[]) {
      scheduleMicrotask(() => _c.add(IncomingMessage(r)));
    }
  }

  @override
  void sendVoice(Uint8List bytes) => voice.add(bytes);

  @override
  Future<void> close() async {}
}

/// Recorder that returns fixed bytes.
class FakeRecorder implements ClipRecorder {
  /// Whether recording.
  bool recording = false;

  /// Stops seen.
  int stops = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start() async => recording = true;

  @override
  Future<Uint8List?> stop() async {
    recording = false;
    stops++;
    return Uint8List(1200);
  }
}

/// Player that records the order clips were played in.
class FakePlayer implements ClipPlayer {
  /// Played clip ids with start/end markers.
  final List<String> timeline = [];

  @override
  Future<void> play(VoiceFrame frame, num volume) async {
    timeline.add('start ${frame.header.clipId}');
    await Future<void>.delayed(Duration(milliseconds: frame.header.durationMs));
    timeline.add('end ${frame.header.clipId}');
  }
}

/// Pumps [child] at [size] inside a ProviderScope with [view] preset.
Future<ProviderContainer> pumpWith(
  WidgetTester tester,
  Widget child, {
  required GameView view,
  Size size = const Size(360, 740),
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    clipRecorderProvider.overrideWithValue(FakeRecorder()),
    clipPlayerProvider.overrideWithValue(FakePlayer()),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  container.read(gameProvider.notifier).debugSetView(view);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: child),
  ));
  await tester.pump();
  return container;
}

/// Every tappable button on screen is at least 44 × 44 logical pixels.
void expectTouchTargets(WidgetTester tester) {
  final finders = [
    find.byType(FilledButton),
    find.byType(OutlinedButton),
    find.byType(TextButton),
    find.byType(IconButton),
  ];
  for (final f in finders) {
    for (final e in f.evaluate()) {
      final box = e.renderObject as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      expect(box.size.height, greaterThanOrEqualTo(44), reason: '${e.widget}');
      expect(box.size.width, greaterThanOrEqualTo(44), reason: '${e.widget}');
    }
  }
}
