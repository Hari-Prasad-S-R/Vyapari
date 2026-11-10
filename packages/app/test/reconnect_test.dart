import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyapari_app/services/transport.dart';
import 'package:vyapari_app/state/game_controller.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import 'helpers.dart';

void main() {
  test('a dropped connection reconnects with the seat token and resyncs',
      () async {
    final s = started();
    final opened = <FakeTransport>[];
    FakeTransport make() => FakeTransport(
        reply: (m) => m is Hello
            ? [Welcome(playerId: 'p1', sessionToken: 'seat-p1', state: s)]
            : []);
    final c = ProviderContainer(overrides: [
      transportFactoryProvider.overrideWithValue((_) async {
        final t = make();
        opened.add(t);
        return t;
      }),
    ]);
    addTearDown(c.dispose);
    final game = c.read(gameProvider.notifier);
    expect(
        await game.connect(Uri.parse('ws://host/ws'),
            code: '4821', name: 'B', token: Token.kite),
        isTrue);
    expect(c.read(gameProvider).status, ConnStatus.connected);
    expect((opened.single.sent.first as Hello).sessionToken, isNull);

    // Wi-Fi blip: the socket closes.
    opened.single.drop();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(gameProvider).status, ConnStatus.reconnecting);
    // First retry comes after 0.5 s.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(opened, hasLength(2));
    final hello = opened.last.sent.first as Hello;
    expect(hello.sessionToken, 'seat-p1', reason: 'rejoins the same seat');
    expect(hello.lastVersion, s.version);
    await Future<void>.delayed(Duration.zero);
    expect(c.read(gameProvider).status, ConnStatus.connected);
    expect(c.read(gameProvider).me, 'p1');
  });

  test('Reconnect now opens a fresh connection at once', () async {
    final s = started();
    var opens = 0;
    final c = ProviderContainer(overrides: [
      transportFactoryProvider.overrideWithValue((_) async {
        opens++;
        return FakeTransport(
            reply: (m) => m is Hello
                ? [Welcome(playerId: 'p1', sessionToken: 'seat-p1', state: s)]
                : []);
      }),
    ]);
    addTearDown(c.dispose);
    final game = c.read(gameProvider.notifier);
    await game.connect(Uri.parse('ws://host/ws'),
        code: '4821', name: 'B', token: Token.kite);
    game.forceReconnect();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(opens, 2);
    expect(c.read(gameProvider).status, ConnStatus.connected);
  });

  test('saved session survives an app restart (round trip)', () {
    const last = LastSession(
        url: 'ws://192.168.43.1:47800/ws',
        code: '4821',
        name: 'Hari',
        token: Token.elephant,
        sessionToken: 'abc',
        hosting: true);
    final back = LastSession.fromJson(last.toJson())!;
    expect(back.url, last.url);
    expect(back.token, Token.elephant);
    expect(back.hosting, isTrue);
    expect(LastSession.fromJson({'url': 1}), isNull);
  });

  test('offline games never try to reconnect', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final t = OfflineTransport(india(), botDelay: Duration.zero, pace: false);
    await c
        .read(gameProvider.notifier)
        .playOffline(t, name: 'A', token: Token.kite);
    c.read(gameProvider.notifier).forceReconnect();
    expect(c.read(gameProvider).status, ConnStatus.connected);
  });

  test('a created room remembers the code the server gave it', () async {
    final s = started(); // roomId 4821
    final opened = <FakeTransport>[];
    final c = ProviderContainer(overrides: [
      transportFactoryProvider.overrideWithValue((_) async {
        final t = FakeTransport(
            reply: (m) => m is Hello
                ? [Welcome(playerId: 'p0', sessionToken: 'seat-p0', state: s)]
                : []);
        opened.add(t);
        return t;
      }),
    ]);
    addTearDown(c.dispose);
    final game = c.read(gameProvider.notifier);
    await game.connect(Uri.parse('ws://host/ws'),
        code: '', name: 'A', token: Token.kite, create: true);
    expect(c.read(gameProvider).roomCode, '4821');
    opened.single.drop();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final hello = opened.last.sent.first as Hello;
    expect(hello.create, isFalse, reason: 'rejoins, does not create again');
    expect(hello.sessionToken, 'seat-p0');
  });
}
