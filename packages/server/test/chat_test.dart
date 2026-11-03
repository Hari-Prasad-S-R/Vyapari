import 'dart:convert';

import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';
import 'package:vyapari_server/vyapari_server.dart';

import 'support.dart';

void main() {
  late RoomHub hub;
  late Room room;
  late List<(FakePeer, Connection)> ps;
  var now = 0;

  setUp(() {
    now = 1000000;
    hub = RoomHub(board: india(), config: testConfig, clock: () => now);
    room = hub.createRoom();
    ps = [];
    for (var i = 0; i < 5; i++) {
      final peer = FakePeer('10.3.0.$i');
      final c = hub.connect(peer);
      say(c, Hello(name: 'P$i', token: Token.values[i]), room: room.code);
      ps.add((peer, c));
    }
  });
  tearDown(() => hub.dispose());

  String id(int i) => ps[i].$2.playerId!;
  List<ChatBroadcast> chats(int i) =>
      ps[i].$1.messages.whereType<ChatBroadcast>().toList();

  test('broadcast chat reaches everyone, stamped with the real sender', () {
    say(ps[0].$2, const ChatMsg('  Deal?  '));
    for (var i = 0; i < 5; i++) {
      expect(chats(i).single.text, 'Deal?', reason: 'player $i');
      expect(chats(i).single.from, id(0));
    }
  });

  test('private chat reaches only the chosen players (and the sender)', () {
    say(ps[0].$2, ChatMsg('psst', to: [id(1), id(2)]));
    expect(chats(1).single.isPrivate, isTrue);
    expect(chats(2), hasLength(1));
    expect(chats(0), hasLength(1), reason: 'sender sees their own message');
    expect(chats(3), isEmpty);
    expect(chats(4), isEmpty);
  });

  test('limits: length, recipients, rate', () {
    say(ps[0].$2, ChatMsg('x' * (maxChatLength + 1)));
    say(ps[0].$2, const ChatMsg('   '));
    say(ps[0].$2, const ChatMsg('hi', to: ['nobody']));
    say(ps[0].$2, ChatMsg('hi', to: [id(1), id(2), id(3), id(4)]));
    expect(
        ps[0].$1.errors.map((e) => e.code).toSet(), {ErrorCode.invalidAction});
    say(ps[0].$2, const ChatMsg('one'));
    say(ps[0].$2, const ChatMsg('two'));
    expect(ps[0].$1.errors.last.code, ErrorCode.rateLimited);
    now += 1000;
    say(ps[0].$2, const ChatMsg('three'));
    expect(chats(1).map((c) => c.text), ['one', 'three']);
  });

  test('a room-muted player is read by nobody', () {
    say(ps[0].$2, PlayerTargetMsg('mute_player', id(3), flag: true));
    say(ps[3].$2, const ChatMsg('spam'));
    for (var i = 0; i < 5; i++) {
      expect(chats(i), isEmpty);
    }
  });

  test('chat is never saved', () {
    say(ps[0].$2, const ChatMsg('secret plan'));
    expect(jsonEncode(room.snapshot()), isNot(contains('secret plan')));
    expect(room.state.log.any((e) => e.text.contains('secret plan')), isFalse);
  });
}
