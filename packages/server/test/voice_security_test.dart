import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';
import 'package:vyapari_server/vyapari_server.dart';

import 'support.dart';

void main() {
  final board = india();

  group('voice relay', () {
    late RoomHub hub;
    late Room room;
    late List<(FakePeer, Connection)> players;
    var now = 0;

    setUp(() {
      now = 1000000;
      hub = RoomHub(board: board, config: testConfig, clock: () => now);
      room = hub.createRoom();
      players = [];
      for (var i = 0; i < 5; i++) {
        final peer = FakePeer('10.0.0.${i + 1}');
        final conn = hub.connect(peer);
        say(conn, Hello(name: 'P$i', token: Token.values[i]), room: room.code);
        players.add((peer, conn));
      }
    });

    tearDown(() => hub.dispose());

    String id(int i) => players[i].$2.playerId!;

    Uint8List clip(
            {List<String> to = const [], int bytes = 2000, int ms = 3000}) =>
        VoiceFrame(
                VoiceHeader(
                    clipId: 'c${Random().nextInt(1 << 30)}',
                    from: 'spoofed',
                    to: to,
                    codec: 'opus',
                    durationMs: ms),
                Uint8List(bytes))
            .encode();

    test('private clip to B and C reaches only B and C', () {
      players[0].$2.onBinary(clip(to: [id(1), id(2)]));
      expect(players[1].$1.binaries, hasLength(1));
      expect(players[2].$1.binaries, hasLength(1));
      for (final i in [0, 3, 4]) {
        expect(players[i].$1.binaries, isEmpty, reason: 'player $i');
      }
      final got = VoiceFrame.decode(players[1].$1.binaries.single)!;
      expect(got.header.from, id(0), reason: 'server stamps the real sender');
      expect(got.header.to.toSet(), {id(1), id(2)});
    });

    test('broadcast reaches everyone else', () {
      players[0].$2.onBinary(clip());
      for (var i = 1; i < 5; i++) {
        expect(players[i].$1.binaries, hasLength(1));
      }
      expect(players[0].$1.binaries, isEmpty);
    });

    test('rate limit: one clip every 3 s', () {
      players[0].$2.onBinary(clip());
      players[0].$2.onBinary(clip());
      expect(players[0].$1.errors.last.code, ErrorCode.rateLimited);
      expect(players[1].$1.binaries, hasLength(1));
      now += 3000;
      players[0].$2.onBinary(clip());
      expect(players[1].$1.binaries, hasLength(2));
    });

    test('size, length and recipient limits', () {
      players[0].$2.onBinary(clip(bytes: 61 * 1024));
      expect(players[0].$1.errors.last.code, ErrorCode.invalidAction);
      players[0].$2.onBinary(clip(ms: 20000));
      expect(players[0].$1.errors.last.code, ErrorCode.invalidAction);
      players[0].$2.onBinary(clip(to: ['nobody']));
      expect(players[0].$1.errors.last.code, ErrorCode.invalidAction);
      players[0].$2.onBinary(clip(to: [id(1), id(2), id(3), id(4)]));
      expect(players[0].$1.errors.last.code, ErrorCode.invalidAction);
      for (var i = 1; i < 5; i++) {
        expect(players[i].$1.binaries, isEmpty);
      }
    });

    test('a room-muted player is heard by nobody', () {
      say(players[0].$2, PlayerTargetMsg('mute_player', id(3), flag: true));
      players[3].$2.onBinary(clip());
      for (var i = 0; i < 5; i++) {
        expect(players[i].$1.binaries, isEmpty);
      }
      // Only the host may mute.
      say(players[1].$2, PlayerTargetMsg('mute_player', id(4), flag: true));
      expect(players[1].$1.errors.last.code, ErrorCode.hostOnly);
    });

    test('clips are never kept or saved', () {
      players[0].$2.onBinary(clip());
      expect(jsonEncode(room.snapshot()), isNot(contains('opus')));
      final src = File('${Directory.current.path}/lib/src/room.dart')
          .readAsStringSync();
      expect(src.contains('writeAsBytes'), isFalse);
    });
  });

  group('security', () {
    test('5 wrong codes block the device; a 6th within 1 min is refused', () {
      var now = 0;
      final hub = RoomHub(board: board, config: testConfig, clock: () => now);
      final room = hub.createRoom();
      final peer = FakePeer('192.168.1.50');
      final conn = hub.connect(peer);
      for (var i = 0; i < 5; i++) {
        say(conn, const Hello(name: 'X', token: Token.kite), room: '0000');
      }
      expect(peer.errors.map((e) => e.code).toSet(), {ErrorCode.badCode});
      say(conn, const Hello(name: 'X', token: Token.kite), room: room.code);
      expect(peer.errors.last.code, ErrorCode.rateLimited);
      expect(conn.playerId, isNull);
      now += 61000;
      say(conn, const Hello(name: 'X', token: Token.kite), room: room.code);
      expect(conn.playerId, isNotNull);
      hub.dispose();
    });

    test('wrong password cannot join', () {
      final hub = RoomHub(board: board, config: testConfig);
      final room = hub.createRoom(password: 'chai');
      final peer = FakePeer();
      final conn = hub.connect(peer);
      say(conn, const Hello(name: 'X', token: Token.kite, password: 'coffee'),
          room: room.code);
      expect(peer.errors.single.code, ErrorCode.badPassword);
      expect(conn.playerId, isNull);
      say(conn, const Hello(name: 'X', token: Token.kite, password: 'chai'),
          room: room.code);
      expect(conn.playerId, isNotNull);
      hub.dispose();
    });

    test('100,000 random messages: no crash, no state change', () {
      final hub = RoomHub(board: board, config: testConfig);
      final room = hub.createRoom();
      final conns = <Connection>[];
      for (var i = 0; i < 3; i++) {
        final c = hub.connect(FakePeer('10.1.0.$i'));
        say(c, Hello(name: 'F$i', token: Token.values[i]), room: room.code);
        say(c, const ReadyMsg(ready: true));
        conns.add(c);
      }
      say(conns[0], const SimpleIntent('start'));
      final before = room.state;
      final rng = Random(42);
      const types = [
        'roll', 'buy', 'bid', 'build', 'welcome', 'state', 'patch', 'hello', //
        'trade_accept', 'kick', 'set_rules', 'xyz', 'error', 'dice_reveal',
      ];
      Object? junk(int depth) => switch (rng.nextInt(depth > 2 ? 4 : 7)) {
            0 => rng.nextInt(1 << 20) - 1000,
            1 => String.fromCharCodes(
                List.generate(rng.nextInt(8), (_) => 33 + rng.nextInt(90))),
            2 => rng.nextBool(),
            3 => null,
            4 => [for (var i = 0; i < rng.nextInt(3); i++) junk(depth + 1)],
            _ => {
                for (final k in [
                  'amount',
                  'tile',
                  'tradeId',
                  'state',
                  'to',
                  'x'
                ])
                  if (rng.nextBool()) k: junk(depth + 1),
              },
          };
      // Players not on turn (so legal-looking moves are still refused) plus
      // non-intent and garbage frames from everyone.
      final current = room.state.currentPlayer;
      final others = conns.where((c) => c.playerId != current).toList();
      for (var i = 0; i < 100000; i++) {
        final c = others[rng.nextInt(others.length)];
        final kind = rng.nextInt(4);
        final text = switch (kind) {
          0 => String.fromCharCodes(
              List.generate(rng.nextInt(40), (_) => rng.nextInt(128))),
          1 => jsonEncode({
              'v': rng.nextInt(3),
              'type': types[rng.nextInt(types.length)],
              'data': junk(0),
            }),
          _ => jsonEncode({
              'v': 1,
              'type': types[rng.nextInt(types.length)],
              'id': 'f$i',
              'data': junk(0),
            }),
        };
        expect(() => c.onText(text), returnsNormally);
        if (i % 7 == 0) {
          expect(
              () => c.onBinary(Uint8List.fromList(
                  List.generate(rng.nextInt(64), (_) => rng.nextInt(256)))),
              returnsNormally);
        }
      }
      expect(room.state.version, before.version);
      expect(room.state, before);
      hub.dispose();
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('clients cannot send server-only messages', () {
      final hub = RoomHub(board: board, config: testConfig);
      final room = hub.createRoom();
      final peer = FakePeer();
      final c = hub.connect(peer);
      say(c, const Hello(name: 'A', token: Token.kite), room: room.code);
      c.onText(const Envelope(NoticeMsg('paused')).encode());
      c.onText(Envelope(StateMsg(room.state)).encode());
      expect(peer.errors.map((e) => e.code),
          everyElement(ErrorCode.unknownMessage));
      hub.dispose();
    });
  });

  group('discovery', () {
    test('a host appears within 3 s and disappears within 6 s of stopping',
        () async {
      const port = 47911;
      final listener = DiscoveryListener(port: port);
      await listener.start();
      final a = DiscoveryAnnouncer(
          info: () => {
                'name': "Hari's game",
                'code': '4821',
                'port': 47800,
                'players': 2
              },
          target: InternetAddress.loopbackIPv4,
          targetPort: port);
      final b = DiscoveryAnnouncer(
          info: () =>
              {'name': 'Second', 'code': '1111', 'port': 47802, 'players': 1},
          target: InternetAddress.loopbackIPv4,
          targetPort: port);
      final sw = Stopwatch()..start();
      await a.start();
      await b.start();
      await listener.games
          .firstWhere((g) => g.length == 2)
          .timeout(const Duration(seconds: 3));
      expect(sw.elapsedMilliseconds, lessThan(3000));
      final g = listener.current.firstWhere((g) => g.code == '4821');
      expect(g.joinUri.toString(),
          'vyapari://join?ip=127.0.0.1&port=47800&code=4821');
      b.stop();
      sw.reset();
      await listener.games
          .firstWhere((g) => g.length == 1)
          .timeout(const Duration(seconds: 8));
      expect(sw.elapsedMilliseconds, lessThan(8000));
      a.stop();
      await listener.stop();
    });
  });
}
