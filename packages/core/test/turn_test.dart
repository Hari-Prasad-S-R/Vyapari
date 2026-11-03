import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';

import 'helpers.dart';

void main() {
  const noAuction = HouseRules(auctions: false);

  test('game starts in turn order from opening rolls', () {
    var s = newLobby(roomId: 'r', board: india());
    s = ok(const JoinGame('a', name: 'A', token: Token.kite), s);
    s = ok(const JoinGame('b', name: 'B', token: Token.elephant), s);
    s = ok(const JoinGame('c', name: 'C', token: Token.teaGlass), s);
    s = ok(const SetReady('b', ready: true), s);
    s = ok(
        const StartGame('a', seed: 1, openingRolls: {'a': 4, 'b': 11, 'c': 7}),
        s);
    expect(s.players.map((p) => p.id), ['b', 'c', 'a']);
    expect(s.currentPlayer, 'b');
    expect(s.phase, GamePhase.awaitingRoll);
    expect(s.players.every((p) => p.cash == 1500000), isTrue);
    expect(s.totalMoney, s.startingTotal);
  });

  test('tile 38 + 5 lands on tile 3 and pays salary', () {
    var s = startedGame(rules: noAuction);
    s = withPlayer(s, 'p0', (p) => p.copyWith(position: 38));
    final before = cash(s, 'p0');
    s = ok(const Roll('p0', 2, 3), s);
    expect(s.player('p0')!.position, 3);
    expect(cash(s, 'p0'), before + 200000);
    expect(s.phase, GamePhase.awaitingBuy);
  });

  test('doubles give another roll', () {
    var s = startedGame(rules: noAuction);
    s = ok(const Roll('p0', 3, 3), s); // Start → Guwahati (6)
    expect(s.phase, GamePhase.awaitingBuy);
    s = ok(const DeclineBuy('p0'), s);
    expect(s.phase, GamePhase.manage);
    expect(s.rollAgain, isTrue);
    expect(apply(const EndTurn('p0'), s).error, ErrorCode.illegalPhase);
    s = ok(const Roll('p0', 1, 2), s); // → Ranchi (9)
    expect(s.player('p0')!.position, 9);
  });

  test('third double in a row goes to jail without moving', () {
    var s = startedGame();
    s = withPlayer(s, 'p0', (p) => p.copyWith(position: 6, doublesInRow: 2));
    s = ok(const Roll('p0', 2, 2), s);
    final p = s.player('p0')!;
    expect(p.inJail, isTrue);
    expect(p.position, 10);
    expect(s.rollAgain, isFalse);
    expect(s.phase, GamePhase.manage);
    s = ok(const EndTurn('p0'), s);
    expect(s.currentPlayer, 'p1');
  });

  test('roll out of turn is rejected with not_your_turn, state unchanged', () {
    final s = startedGame();
    final r = apply(const Roll('p1', 1, 2), s);
    expect(r.ok, isFalse);
    expect(r.error, ErrorCode.notYourTurn);
    expect(identical(r.state, s), isTrue);
  });

  test('rolling twice and ending before rolling are rejected', () {
    var s = startedGame();
    expect(apply(const EndTurn('p0'), s).error, ErrorCode.illegalPhase);
    s = withPlayer(s, 'p0', (p) => p.copyWith(position: 20)); // Chai Break
    s = ok(const Roll('p0', 1, 0 + 3), s); // → 24 Ahmedabad
    s = ok(const DeclineBuy('p0'), s);
    s = ok(const CloseAuction('p0'), s);
    expect(apply(const Roll('p0', 1, 2), s).error, ErrorCode.illegalPhase);
    s = ok(const EndTurn('p0'), s);
    expect(s.currentPlayer, 'p1');
    expect(s.phase, GamePhase.awaitingRoll);
  });

  test('version increments on every accepted action only', () {
    final s = startedGame();
    final v = s.version;
    expect(apply(const Roll('p1', 1, 2), s).state.version, v);
    expect(apply(const Roll('p0', 1, 2), s).state.version, v + 1);
  });

  test('roll intents without dice are rejected', () {
    final s = startedGame();
    expect(apply(const Roll.intent('p0'), s).error, ErrorCode.invalidAction);
  });

  test('phase table', () {
    var s = startedGame(rules: noAuction);
    // awaitingRoll → (tax) manage
    s = withPlayer(s, 'p0', (p) => p.copyWith(position: 1));
    s = ok(const Roll('p0', 1, 2), s); // 4 Income Tax
    expect(s.phase, GamePhase.manage);
    s = ok(const EndTurn('p0'), s);
    // awaitingRoll → Police Thana → jailed, manage
    s = withPlayer(s, 'p1', (p) => p.copyWith(position: 25));
    s = ok(const Roll('p1', 2, 3), s);
    expect(s.player('p1')!.inJail, isTrue);
    expect(s.phase, GamePhase.manage);
    s = ok(const EndTurn('p1'), s);
    // awaitingRoll → unowned city → awaitingBuy → buy → manage
    s = withPlayer(s, 'p2', (p) => p.copyWith(position: 35));
    s = ok(const Roll('p2', 1, 3), s); // 39 Mumbai
    expect(s.phase, GamePhase.awaitingBuy);
    s = ok(const Buy('p2'), s);
    expect(s.phase, GamePhase.manage);
    expect(s.totalMoney, s.startingTotal);
  });
}
