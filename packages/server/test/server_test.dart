import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';
import 'package:vyapari_server/vyapari_server.dart';

import 'support.dart';

void main() {
  late GameServer server;
  late int port;
  late Room room;
  final board = india();

  Future<void> boot(
      {ServerConfig config = testConfig, GameStore? store}) async {
    server = GameServer(board: board, config: config, store: store);
    port = await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    room = server.hub.createRoom();
  }

  tearDown(() async => server.stop());

  Future<List<TestClient>> lobby(int n) async {
    final clients = <TestClient>[];
    for (var i = 0; i < n; i++) {
      final c = await TestClient.connect(port, 'P$i');
      await c.hello(room.code, token: Token.values[i % 6]);
      expect(c.playerId, isNotNull, reason: '${c.errors}');
      clients.add(c);
    }
    for (final c in clients.skip(1)) {
      c.send(const ReadyMsg(ready: true));
    }
    await clients.first.waitFor(() =>
        clients.first.state!.players.where((p) => p.ready).length >= n - 1);
    return clients;
  }

  test('health endpoint', () async {
    await boot();
    final client = HttpClient();
    final req = await client.get('127.0.0.1', port, '/health');
    final res = await req.close();
    final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
    expect(res.statusCode, 200);
    expect(body['status'], 'ok');
    client.close();
  });

  test('local hosts describe their room at /local for Wi-Fi scanning',
      () async {
    await boot();
    final client = HttpClient();
    final res = await (await client.get('127.0.0.1', port, '/local')).close();
    final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map;
    expect(res.statusCode, 200);
    expect(body['app'], 'vyapari');
    final rooms = body['rooms'] as List;
    expect(rooms.single['code'], room.code);
    expect(rooms.single['hasPassword'], isFalse);
    client.close();
  });

  test('3 clients: host starts, all get the same state and turn order',
      () async {
    await boot();
    final cs = await lobby(3);
    expect(cs.first.playerId, cs.first.state!.hostId);
    cs.first.send(const SimpleIntent('start'));
    for (final c in cs) {
      await c.waitFor(() =>
          c.state!.phase == GamePhase.awaitingRoll &&
          c.received.whereType<DiceCommitMsg>().isNotEmpty);
    }
    final order = cs.first.state!.players.map((p) => p.id).toList();
    for (final c in cs) {
      expect(c.state!.players.map((p) => p.id), order);
      expect(c.state, cs.first.state);
      expect(c.received.whereType<DiceCommitMsg>(), isNotEmpty);
    }
  });

  test('non-host kick is rejected with host_only', () async {
    await boot();
    final cs = await lobby(3);
    cs[1].send(PlayerTargetMsg('kick', cs[2].playerId!));
    await cs[1].waitFor(() => cs[1].errors.isNotEmpty);
    expect(cs[1].errors.single.code, ErrorCode.hostOnly);
    cs[0].send(PlayerTargetMsg('kick', cs[2].playerId!));
    await cs[2].waitFor(() => cs[2].closed);
    await cs[0].waitFor(() => cs[0].state!.players.length == 2);
  });

  test('a purchase reaches every client within 150 ms on localhost', () async {
    await boot();
    final cs = await lobby(3);
    cs.first.send(const SimpleIntent('start'));
    for (final c in cs) {
      await c.waitFor(() => c.state!.phase == GamePhase.awaitingRoll);
    }
    // Roll until someone may buy.
    TestClient mover() =>
        cs.firstWhere((c) => c.playerId == cs.first.state!.currentPlayer);
    for (var tries = 0; tries < 40; tries++) {
      final m = mover();
      final s = m.state!;
      if (s.phase == GamePhase.awaitingBuy &&
          s.player(m.playerId)!.cash >=
              s.tiles[s.player(m.playerId)!.position].price) {
        final v = s.version;
        final sent = DateTime.now().millisecondsSinceEpoch;
        m.send(const SimpleIntent('buy'));
        for (final c in cs) {
          await c.waitFor(() => c.patchArrivals.containsKey(v + 1));
          expect(c.patchArrivals[v + 1]! - sent, lessThan(150));
          expect(c.state!.ownershipOf(s.player(m.playerId)!.position)!.ownerId,
              m.playerId);
        }
        return;
      }
      final next = switch (s.phase) {
        GamePhase.awaitingRoll => const SimpleIntent('roll'),
        GamePhase.manage => SimpleIntent(s.rollAgain ? 'roll' : 'end_turn'),
        GamePhase.awaitingBuy => const SimpleIntent('decline'),
        _ => null,
      };
      final v = s.version;
      if (next != null) m.send(next);
      await cs.first.waitFor(() =>
          cs.first.state!.version > v &&
          cs.first.state!.phase != GamePhase.auction);
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('nobody got a chance to buy');
  });

  test('6 clients finish a game, with one disconnect and rejoin', () async {
    await boot();
    final cs = await lobby(6);
    cs.first.send(const SetRulesMsg(HouseRules(maxTurns: 60, turnTimerSec: 0)));
    await cs.first.waitFor(() => cs.first.state!.rules.maxTurns == 60);
    cs.first.send(const SimpleIntent('start'));
    for (var i = 0; i < cs.length; i++) {
      cs[i].autoplay(
          Bot.forLevel(BotLevel.values[i % 3], SeededRandomSource(i)));
    }
    // Drop player 3 mid-game, then rejoin with the session token.
    await cs.first.waitFor(() => (cs.first.state?.turnNumber ?? 0) >= 10,
        timeout: const Duration(seconds: 30));
    final dropped = cs[3];
    final token = dropped.sessionToken!;
    final seat = dropped.playerId!;
    await dropped.close();
    await cs.first
        .waitFor(() => cs.first.state!.player(seat)!.connected == false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final back = await TestClient.connect(port, 'P3');
    await back.hello(room.code, session: token);
    expect(back.playerId, seat);
    back.autoplay(MediumBot(SeededRandomSource(99)));
    cs[3] = back;
    for (final c in cs) {
      await c.waitFor(() => c.state!.phase == GamePhase.gameOver,
          timeout: const Duration(seconds: 60));
    }
    final finalState = cs.first.state!;
    for (final c in cs) {
      expect(c.state!.version, finalState.version);
      expect(c.state!.winnerId, finalState.winnerId);
    }
    expect(finalState.winnerId, isNotNull);
    expect(finalState.totalMoney, finalState.startingTotal);
    expect(server.hub.rooms[room.code]!.state, finalState);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('event log arrives in the same order for everyone', () async {
    await boot();
    final cs = await lobby(3);
    cs.first.send(const SetRulesMsg(HouseRules(maxTurns: 15, turnTimerSec: 0)));
    await cs.first.waitFor(() => cs.first.state!.rules.maxTurns == 15);
    cs.first.send(const SimpleIntent('start'));
    for (var i = 0; i < cs.length; i++) {
      cs[i].autoplay(MediumBot(SeededRandomSource(i)));
    }
    for (final c in cs) {
      await c.waitFor(() => c.state!.phase == GamePhase.gameOver,
          timeout: const Duration(seconds: 30));
    }
    // Compare from game start (later joiners missed earlier lobby events).
    List<String> fromStart(TestClient c) => c.events
        .skipWhile((e) => e.type != 'started')
        .map((e) => e.toJson().toString())
        .toList();
    final ref = fromStart(cs.first);
    expect(ref.length, greaterThan(20));
    for (final c in cs) {
      expect(fromStart(c), ref);
    }
  });

  test('host adds 2 bots to 2 humans: game starts with 4 players', () async {
    await boot();
    final cs = await lobby(2);
    cs.first.send(const AddBotMsg(level: BotLevel.easy));
    cs.first.send(const AddBotMsg(level: BotLevel.hard));
    await cs.first.waitFor(() => cs.first.state!.players.length == 4);
    cs.first.send(const SimpleIntent('start'));
    await cs.first.waitFor(() => cs.first.state!.phase != GamePhase.lobby);
    expect(cs.first.state!.players, hasLength(4));
    expect(cs.first.state!.players.where((p) => p.isBot), hasLength(2));
  });

  test('version mismatch on hello asks to update the app', () async {
    await boot();
    final c = await TestClient.connect(port, 'old');
    c.sendRaw(jsonEncode({
      'v': 0,
      'type': 'hello',
      'id': 'x',
      'room': room.code,
      'data': {'name': 'old', 'token': 'kite'},
    }));
    await c.waitFor(() => c.errors.isNotEmpty);
    expect(c.errors.single.code, ErrorCode.versionMismatch);
    expect(c.errors.single.message, 'Please update the app');
  });

  test('a full room refuses with room_full', () async {
    await boot();
    final cs = await lobby(1);
    for (var i = 0; i < 7; i++) {
      cs.first.send(const AddBotMsg());
    }
    await cs.first.waitFor(() => cs.first.state!.players.length == 8);
    final late = await TestClient.connect(port, 'Late');
    await late.hello(room.code);
    expect(late.errors.single.code, ErrorCode.roomFull);
    expect(late.errors.single.message, 'Room is full');
  });

  group('sessions and reconnect', () {
    test('rejoin after a drop restores the seat with current state', () async {
      await boot();
      final cs = await lobby(3);
      cs.first.send(const SimpleIntent('start'));
      await cs[1].waitFor(() => cs[1].state!.phase == GamePhase.awaitingRoll);
      final token = cs[1].sessionToken!;
      final seat = cs[1].playerId!;
      await cs[1].close();
      await cs[0].waitFor(() => !cs[0].state!.player(seat)!.connected);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final back = await TestClient.connect(port, 'P1');
      await back.hello(room.code, session: token);
      expect(back.playerId, seat);
      await cs[0].waitFor(() => cs[0].state!.player(seat)!.connected);
      await back.waitFor(() => back.state!.version == cs[0].state!.version);
      expect(back.state, cs[0].state);
    });

    test('rejoin after the window is refused and the seat goes to a bot',
        () async {
      await boot(
          config: const ServerConfig(
              paceAnimations: false,
              botDelay: Duration(milliseconds: 5),
              rejoinWindow: Duration(milliseconds: 300),
              heartbeatSweep: Duration(milliseconds: 100)));
      final cs = await lobby(3);
      cs.first.send(const SetRulesMsg(HouseRules(turnTimerSec: 0)));
      cs.first.send(const SimpleIntent('start'));
      await cs[2].waitFor(() => cs[2].state!.phase == GamePhase.awaitingRoll);
      final token = cs[2].sessionToken!;
      final seat = cs[2].playerId!;
      await cs[2].close();
      await cs[0].waitFor(() => cs[0].state!.player(seat)!.isBot,
          timeout: const Duration(seconds: 5));
      final back = await TestClient.connect(port, 'P2');
      await back.hello(room.code, session: token);
      expect(back.playerId, isNull);
      expect(back.errors.single.code, ErrorCode.illegalPhase);
    });

    test('disconnected on my turn with bot cover: a bot plays it', () async {
      // Online mode: a dropped host does not pause the game.
      await boot(
          config: const ServerConfig(
              paceAnimations: false,
              online: true,
              botDelay: Duration.zero,
              tradeReviewDelay: Duration.zero));
      final cs = await lobby(2);
      cs.first.send(const SetRulesMsg(HouseRules(turnTimerSec: 0)));
      cs.first.send(const SimpleIntent('start'));
      for (final c in cs) {
        await c.waitFor(() => c.state!.phase == GamePhase.awaitingRoll);
      }
      final current = cs[0].state!.currentPlayer!;
      final gone = cs.firstWhere((c) => c.playerId == current);
      final stay = cs.firstWhere((c) => c.playerId != current);
      await gone.close();
      await stay.waitFor(
          () =>
              stay.state!.currentPlayer != current &&
              stay.state!.phase == GamePhase.awaitingRoll,
          timeout: const Duration(seconds: 5));
      expect(
          stay.events.any((e) => e.type == 'rolled' && e.playerId == current),
          isTrue,
          reason: [
            'host=${stay.state!.hostId} current=$current',
            ...stay.events.map((e) => '${e.type}:${e.playerId}'),
          ].join(' '));
    });

    test('turn timer ends the turn and play passes on', () async {
      await boot();
      final cs = await lobby(2);
      cs.first.send(const SetRulesMsg(HouseRules(turnTimerSec: 1)));
      cs.first.send(const SimpleIntent('start'));
      await cs[0].waitFor(() => cs[0].state!.phase == GamePhase.awaitingRoll);
      final first = cs[0].state!.currentPlayer;
      await cs[0].waitFor(() => cs[0].state!.currentPlayer != first,
          timeout: const Duration(seconds: 5));
      expect(
          cs[0].received.whereType<NoticeMsg>().any((n) => n.kind == 'timeout'),
          isTrue);
      expect(cs[0].state!.totalMoney, cs[0].state!.startingTotal);
    });
  });

  group('save and resume', () {
    test('resume after restart continues from the same turn', () async {
      final dir = await Directory.systemTemp.createTemp('vyapari_save');
      final store = JsonFileStore(dir);
      await boot(store: store);
      final cs = await lobby(2);
      cs.first.send(const SetRulesMsg(HouseRules(turnTimerSec: 0)));
      cs.first.send(const SimpleIntent('start'));
      await cs[0].waitFor(() => cs[0].state!.phase == GamePhase.awaitingRoll);
      final cur =
          cs.firstWhere((c) => c.playerId == cs[0].state!.currentPlayer);
      cur.send(const SimpleIntent('roll'));
      await cs[0].waitFor(() => cs[0].state!.lastDice.isNotEmpty);
      cs.first.send(const SimpleIntent('save_game'));
      await cs[0].waitFor(() =>
          cs[0].received.whereType<NoticeMsg>().any((n) => n.kind == 'saved'));
      final saved = cs[0].state!;
      final tokens = [for (final c in cs) (c.sessionToken!, c.playerId!)];
      for (final c in cs) {
        await c.close();
      }
      await server.stop();

      // Restart with the same store.
      server = GameServer(board: board, config: testConfig, store: store);
      port = await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      final resumed = server.hub.resume(room.code)!;
      expect(resumed.state.turnNumber, saved.turnNumber);
      expect(resumed.paused, isTrue);
      final back = <TestClient>[];
      for (final (token, seat) in tokens) {
        final c = await TestClient.connect(port, seat);
        await c.hello(room.code, session: token);
        expect(c.playerId, seat);
        back.add(c);
      }
      final host = back.first;
      await host.waitFor(() =>
          host.state!.players.every((p) => p.connected) &&
          !server.hub.rooms[room.code]!.paused);
      expect(host.state!.turnNumber, saved.turnNumber);
      expect(host.state!.currentPlayer, saved.currentPlayer);
      expect(host.state!.ownership, saved.ownership);
      expect([for (final p in host.state!.players) p.cash],
          [for (final p in saved.players) p.cash]);
      await dir.delete(recursive: true);
    });

    test('a corrupt save is reported, not crashed on', () async {
      final dir = await Directory.systemTemp.createTemp('vyapari_bad');
      File('${dir.path}/room_9999.json').writeAsStringSync('{not json');
      final store = JsonFileStore(dir);
      await boot(store: store);
      final errors = <String>[];
      expect(server.hub.restoreAll(errors: errors), 0);
      expect(errors.single, contains('9999'));
      expect(() => store.load('9999'), throwsA(isA<CorruptSaveException>()));
      await dir.delete(recursive: true);
    });

    test('SQLite store round trip', () async {
      final dir = await Directory.systemTemp.createTemp('vyapari_sql');
      final store = SqliteStore('${dir.path}/rooms.db');
      store.save('ABC123', {'code': 'ABC123', 'n': 1}, 5);
      store.save('ABC123', {'code': 'ABC123', 'n': 2}, 6);
      expect(store.load('ABC123')!.json['n'], 2);
      expect(store.list(), hasLength(1));
      store.delete('ABC123');
      expect(store.load('ABC123'), isNull);
      store.close();
      await dir.delete(recursive: true);
    });
  });
}
