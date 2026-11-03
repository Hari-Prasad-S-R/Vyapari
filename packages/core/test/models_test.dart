import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';

import 'helpers.dart';

T roundTrip<T>(T value, Map<String, Object?> Function(T) enc,
        T Function(Map<String, Object?>) dec) =>
    dec((jsonDecode(jsonEncode(enc(value))) as Map).cast<String, Object?>());

void main() {
  group('JSON round trip', () {
    test('every model equals itself after encode/decode', () {
      final player = Player(
          id: 'a',
          name: 'Asha',
          token: Token.elephant,
          cash: 1500000,
          getOutCards: ['v08'],
          isBot: true,
          botLevel: BotLevel.hard);
      expect(roundTrip(player, (x) => x.toJson(), Player.fromJson), player);

      const own = Ownership(tileIndex: 3, ownerId: 'a', houses: 5);
      expect(roundTrip(own, (x) => x.toJson(), Ownership.fromJson), own);

      final tile = india().tiles[39];
      expect(roundTrip(tile, (x) => x.toJson(), Tile.fromJson), tile);

      final card = india().cards.first;
      expect(roundTrip(card, (x) => x.toJson(), GameCard.fromJson), card);

      final trade = Trade(
          id: 't1',
          from: 'a',
          to: 'b',
          give: TradeSide(cash: 100000, tiles: [1]),
          get: TradeSide(tiles: [3], cards: 1),
          createdAtVersion: 9);
      expect(roundTrip(trade, (x) => x.toJson(), Trade.fromJson), trade);

      final auction = Auction(tileIndex: 5, bids: {'a': 20000, 'b': 30000});
      expect(roundTrip(auction, (x) => x.toJson(), Auction.fromJson), auction);

      const rules = HouseRules(freeParkingPot: true, maxTurns: 100);
      expect(roundTrip(rules, (x) => x.toJson(), HouseRules.fromJson), rules);

      const session = Session(playerId: 'a', token: 'xyz', lastSeen: 42);
      expect(roundTrip(session, (x) => x.toJson(), Session.fromJson), session);

      const debt = Debt(amount: 5000, creditorId: 'b');
      expect(roundTrip(debt, (x) => x.toJson(), Debt.fromJson), debt);

      final state = startedGame();
      expect(roundTrip(state, (x) => x.toJson(), GameState.fromJson), state);
    });
  });

  test('copyWith leaves the original unchanged', () {
    final s = startedGame();
    final before = jsonEncode(s.toJson());
    final changed = s.copyWith(freeParkingPot: 999, phase: GamePhase.manage);
    expect(changed.freeParkingPot, 999);
    expect(jsonEncode(s.toJson()), before);
    expect(s.freeParkingPot, 0);
  });

  test('state lists are immutable', () {
    final s = startedGame();
    expect(() => s.players.add(s.players.first), throwsUnsupportedError);
  });

  test('no double is used for money in core', () {
    final lib = Directory('${repoRoot().path}/packages/core/lib');
    final files = lib.listSync(recursive: true).whereType<File>();
    for (final f in files) {
      expect(RegExp(r'\bdouble\b').hasMatch(f.readAsStringSync()), isFalse,
          reason: '${f.path} uses double');
    }
  });

  test('core has no Flutter or dart:io imports', () {
    final lib = Directory('${repoRoot().path}/packages/core/lib');
    for (final f in lib.listSync(recursive: true).whereType<File>()) {
      final src = f.readAsStringSync();
      expect(src.contains("'dart:io'"), isFalse, reason: f.path);
      expect(src.contains('package:flutter'), isFalse, reason: f.path);
    }
  });
}
