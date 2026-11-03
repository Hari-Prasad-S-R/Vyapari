import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

GameState sampleState() {
  var dir = Directory.current;
  while (!Directory('${dir.path}/assets/boards/india').existsSync()) {
    dir = dir.parent;
  }
  final board = BoardData.parse(
    File('${dir.path}/assets/boards/india/board.json').readAsStringSync(),
    File('${dir.path}/assets/boards/india/cards.json').readAsStringSync(),
  );
  var s = newLobby(roomId: '4821', board: board);
  s = apply(const JoinGame('a', name: 'Asha', token: Token.kite), s).state;
  s = apply(const JoinGame('b', name: 'Bala', token: Token.elephant), s).state;
  s = apply(const SetReady('b', ready: true), s).state;
  return apply(const StartGame('a', seed: 3, openingRolls: {'a': 9}), s).state;
}

void main() {
  final state = sampleState();
  final side = TradeSide(cash: 50000, tiles: [1, 3], cards: 1);
  final messages = <Message>[
    const Hello(name: 'Asha', token: Token.kite),
    const Hello(
        name: 'Bala',
        token: Token.teaGlass,
        sessionToken: 'tok',
        lastVersion: 12,
        create: true,
        password: '1234',
        deviceName: 'Pixel'),
    const ReadyMsg(ready: true),
    const SetRulesMsg(HouseRules(freeParkingPot: true, turnTimerSec: 90)),
    const AddBotMsg(level: BotLevel.hard),
    const PlayerTargetMsg('kick', 'b'),
    const PlayerTargetMsg('mute_player', 'b', flag: true),
    const BidMsg(120000),
    for (final t in TileMsg.types) TileMsg(t, 31),
    TradeProposeMsg(to: 'b', give: side, get: TradeSide(tiles: [39])),
    for (final t in TradeAnswerMsg.types) TradeAnswerMsg(t, 't1'),
    TradeCounterMsg('t1', give: TradeSide(cash: 1), get: side),
    const EmoteMsg(Emote.semma),
    const SyncMsg(7),
    for (final t in SimpleIntent.types) SimpleIntent(t),
    Welcome(playerId: 'a', sessionToken: 'tok', state: state, password: true),
    StateMsg(state),
    PatchMsg.diff(state, state.copyWith(version: state.version + 1), [
      GameEvent('rolled', playerId: 'a', data: {'d1': 3}, text: 'x')
    ]),
    const DiceCommitMsg(DiceCommit(rollNumber: 1, hash: 'abc')),
    const DiceRevealMsg(DiceReveal(rollNumber: 1, key: 'ff', d1: 2, d2: 5)),
    const ErrorMsg(ErrorCode.notYourTurn, message: 'wait', refId: 'c-1'),
    const EmoteBroadcast(from: 'a', emote: Emote.aiyo),
    const NoticeMsg('paused', text: 'Host left', data: {'canSave': true}),
  ];

  test('every message survives encode → decode', () {
    for (final m in messages) {
      final env = Envelope(m, id: 'c-1042', room: '4821');
      final r = decodeFrame(env.encode());
      expect(r.ok, isTrue, reason: '${m.type}: ${r.error}');
      expect(r.envelope, env, reason: m.type);
      expect(r.envelope!.message.runtimeType, m.runtimeType);
    }
  });

  test('every design §5 message type exists', () {
    const required = [
      'hello', 'ready', 'set_rules', 'add_bot', 'kick', 'start', 'roll', //
      'buy', 'decline', 'bid', 'pay_jail', 'use_card', 'end_turn', 'build',
      'sell_building', 'mortgage', 'unmortgage', 'trade_propose',
      'trade_accept', 'trade_reject', 'trade_counter', 'emote',
      'mute_player', 'welcome', 'state', 'patch', 'dice_commit',
      'dice_reveal', 'error',
    ];
    for (final t in required) {
      expect(decoders.containsKey(t), isTrue, reason: t);
    }
  });

  test('patch applies to the matching version and ignores stale ones', () {
    final next = state.copyWith(version: state.version + 1, freeParkingPot: 5);
    final patch = PatchMsg.diff(state, next);
    expect(patch.changes.keys, containsAll(['version', 'freeParkingPot']));
    expect(patch.changes.containsKey('tiles'), isFalse);
    expect(patch.applyTo(state), next);
    expect(patch.applyTo(next), isNull);
  });

  group('malformed input returns a typed error and never throws', () {
    final cases = <String, ErrorCode>{
      'not json': ErrorCode.malformed,
      '[1,2]': ErrorCode.malformed,
      '{"type":"roll"}': ErrorCode.malformed,
      '{"v":99,"type":"roll"}': ErrorCode.versionMismatch,
      '{"v":1,"type":"teleport","data":{}}': ErrorCode.unknownMessage,
      '{"v":1,"type":"bid","data":{"amount":"lots"}}': ErrorCode.malformed,
      '{"v":1,"type":"hello","data":{"name":"x","token":"spaceship"}}':
          ErrorCode.malformed,
      '{"v":1,"type":7}': ErrorCode.malformed,
      '{"v":1,"type":"roll","data":[]}': ErrorCode.malformed,
    };
    cases.forEach((input, code) {
      test(input, () {
        final r = decodeFrame(input);
        expect(r.ok, isFalse);
        expect(r.error!.code, code);
      });
    });

    test('random garbage', () {
      final rng = Random(5);
      for (var i = 0; i < 5000; i++) {
        final s = String.fromCharCodes(
            List.generate(rng.nextInt(60), (_) => 32 + rng.nextInt(90)));
        expect(() => decodeFrame(s), returnsNormally);
        expect(() => decodeFrame('{"v":1,"type":"bid","data":$s}'),
            returnsNormally);
        final bytes = List.generate(rng.nextInt(80), (_) => rng.nextInt(256));
        expect(() => VoiceFrame.decode(bytes), returnsNormally);
      }
    });
  });

  group('voice frame', () {
    test('round trip', () {
      final audio = Uint8List.fromList(List.generate(3000, (i) => i % 256));
      final f = VoiceFrame(
          const VoiceHeader(
              clipId: 'c1',
              from: 'a',
              to: ['b', 'c'],
              codec: 'opus',
              durationMs: 4200),
          audio);
      final back = VoiceFrame.decode(f.encode())!;
      expect(back.header, f.header);
      expect(back.audio, audio);
      expect(back.header.isPrivate, isTrue);
    });

    test('header length is a 4-byte big-endian prefix', () {
      final f = VoiceFrame(
          const VoiceHeader(clipId: 'x', from: '', codec: 'aac', durationMs: 1),
          Uint8List(0));
      final bytes = f.encode();
      final len = ByteData.sublistView(bytes).getUint32(0);
      expect(len, bytes.length - 4);
      expect(utf8.decode(bytes.sublist(4)), contains('"codec":"aac"'));
    });

    test('truncated or lying headers decode to null', () {
      expect(VoiceFrame.decode([0, 0]), isNull);
      expect(VoiceFrame.decode([0, 0, 0, 50, 1, 2]), isNull);
      expect(VoiceFrame.decode([0, 0, 0, 2, 123, 125]), isNull);
    });
  });
}
