import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';

import 'helpers.dart';

void main() {
  group('trades', () {
    GameState base() {
      var s = startedGame();
      s = withOwned(s, 'p0', [1]);
      s = withOwned(s, 'p1', [3]);
      return withPlayer(s, 'p1', (p) => p.copyWith(getOutCards: ['v08']));
    }

    test('accepted offer swaps exactly what was offered', () {
      var s = base();
      s = ok(
          ProposeTrade('p0',
              to: 'p1',
              give: TradeSide(cash: 100000, tiles: [1]),
              get: TradeSide(tiles: [3], cards: 1)),
          s);
      final id = s.trades.single.id;
      final c0 = cash(s, 'p0');
      final c1 = cash(s, 'p1');
      s = ok(AcceptTrade('p1', id), s);
      expect(s.ownershipOf(1)!.ownerId, 'p1');
      expect(s.ownershipOf(3)!.ownerId, 'p0');
      expect(cash(s, 'p0'), c0 - 100000);
      expect(cash(s, 'p1'), c1 + 100000);
      expect(s.player('p0')!.getOutCards, ['v08']);
      expect(s.player('p1')!.getOutCards, isEmpty);
      expect(s.trades, isEmpty);
      expect(s.totalMoney, s.startingTotal);
    });

    test('proposer spent the cash: trade_invalid, nothing moves', () {
      var s = base();
      s = ok(
          ProposeTrade('p0',
              to: 'p1',
              give: TradeSide(cash: 1400000),
              get: TradeSide(tiles: [3])),
          s);
      s = withPlayer(s, 'p0', (p) => p.copyWith(cash: 1000)); // spent it
      final r = apply(AcceptTrade('p1', s.trades.single.id), s);
      expect(r.error, ErrorCode.tradeInvalid);
      expect(identical(r.state, s), isTrue);
    });

    test('buildings on the group invalidate the trade', () {
      var s = startedGame();
      s = withOwned(s, 'p0', [37, 39]);
      s = ok(
          ProposeTrade('p0',
              to: 'p1', give: TradeSide(tiles: [37]), get: TradeSide(cash: 1)),
          s);
      s = ok(const Build('p0', 39), s);
      expect(apply(AcceptTrade('p1', s.trades.single.id), s).error,
          ErrorCode.tradeInvalid);
    });

    test('reject, cancel and counter', () {
      var s = base();
      s = ok(
          ProposeTrade('p0',
              to: 'p1',
              give: TradeSide(cash: 50000),
              get: TradeSide(tiles: [3])),
          s);
      final t1 = s.trades.single.id;
      expect(apply(AcceptTrade('p0', t1), s).error, ErrorCode.notOwner);
      s = ok(
          CounterTrade('p1', t1,
              give: TradeSide(tiles: [3]), get: TradeSide(cash: 150000)),
          s);
      final counter = s.trades.single;
      expect(counter.from, 'p1');
      expect(counter.to, 'p0');
      s = ok(RejectTrade('p0', counter.id), s);
      expect(s.trades, isEmpty);
      s = ok(
          ProposeTrade('p0',
              to: 'p1', give: TradeSide(cash: 1), get: TradeSide(tiles: [3])),
          s);
      s = ok(CancelTrade('p0', s.trades.single.id), s);
      expect(s.trades, isEmpty);
    });

    test('bankrupt or disconnected players cannot trade', () {
      var s = base();
      final offer = ProposeTrade('p0',
          to: 'p1', give: TradeSide(cash: 1), get: TradeSide(tiles: [3]));
      final gone = withPlayer(s, 'p1', (p) => p.copyWith(connected: false));
      expect(apply(offer, gone).error, ErrorCode.tradeInvalid);
      final broke = withPlayer(s, 'p1', (p) => p.copyWith(bankrupt: true));
      expect(apply(offer, broke).error, ErrorCode.tradeInvalid);
      final meBroke = withPlayer(s, 'p0', (p) => p.copyWith(bankrupt: true));
      expect(apply(offer, meBroke).error, ErrorCode.tradeInvalid);
      // Disconnecting cancels pending offers.
      s = ok(offer, s);
      s = ok(const SetConnected('p1', connected: false), s);
      expect(s.trades, isEmpty);
    });

    test('trades cannot be accepted during an auction', () {
      var s = base();
      s = ok(
          ProposeTrade('p0',
              to: 'p1', give: TradeSide(cash: 1), get: TradeSide(tiles: [3])),
          s);
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 35));
      s = ok(const Roll('p0', 1, 3), s);
      s = ok(const DeclineBuy('p0'), s);
      expect(apply(AcceptTrade('p1', s.trades.single.id), s).error,
          ErrorCode.illegalPhase);
    });
  });

  group('bankruptcy and game end', () {
    test('bankrupted by a player: all cities and cash go to them', () {
      var s = startedGame();
      s = withOwned(s, 'p1', [37, 39], houses: 5);
      s = withOwned(s, 'p0', [1, 3]);
      s = withPlayer(s, 'p0', (p) => p.copyWith(cash: 1000, position: 35));
      final total = s.totalMoney;
      s = ok(const Roll('p0', 1, 3), s); // Mumbai with hotel
      expect(s.phase, GamePhase.raiseCash);
      expect(apply(const EndTurn('p0'), s).error, ErrorCode.illegalPhase);
      expect(apply(const PayDebt('p0'), s).error, ErrorCode.insufficientFunds);
      s = ok(const Mortgage('p0', 1), s);
      s = ok(const Mortgage('p0', 3), s);
      final p1Before = cash(s, 'p1');
      final p0Cash = cash(s, 'p0');
      s = ok(const DeclareBankruptcy('p0'), s);
      expect(s.player('p0')!.bankrupt, isTrue);
      expect(s.ownershipOf(1)!.ownerId, 'p1');
      expect(s.ownershipOf(3)!.ownerId, 'p1');
      expect(cash(s, 'p1'), p1Before + p0Cash);
      expect(s.currentPlayer, 'p1');
      expect(s.totalMoney, total);
    });

    test('raise cash then pay debt', () {
      var s = startedGame();
      s = withOwned(s, 'p1', [39]);
      s = withOwned(s, 'p0', [37]);
      s = withPlayer(s, 'p0', (p) => p.copyWith(cash: 10000, position: 35));
      final total = s.totalMoney;
      s = ok(const Roll('p0', 1, 3), s); // rent 50,000
      expect(s.phase, GamePhase.raiseCash);
      expect(apply(const DeclareBankruptcy('p0'), s).ok, isTrue);
      s = ok(const Mortgage('p0', 37), s); // +1,75,000
      expect(apply(const DeclareBankruptcy('p0'), s).error,
          ErrorCode.invalidAction);
      s = ok(const PayDebt('p0'), s);
      expect(s.phase, GamePhase.manage);
      expect(cash(s, 'p0'), 10000 + 175000 - 50000);
      expect(s.totalMoney, total);
    });

    test('bankrupt to the bank returns cities to the bank', () {
      var s = startedGame();
      s = withOwned(s, 'p0', [1]);
      s = withPlayer(s, 'p0', (p) => p.copyWith(cash: 1000, position: 1));
      final total = s.totalMoney;
      s = ok(const Roll('p0', 1, 2), s); // Income Tax
      s = ok(const Mortgage('p0', 1), s);
      s = ok(const DeclareBankruptcy('p0'), s);
      expect(s.ownershipOf(1), isNull);
      expect(s.totalMoney, total);
    });

    test('last player standing wins', () {
      var s = startedGame(n: 2);
      s = withOwned(s, 'p1', [39], houses: 5);
      s = withPlayer(s, 'p0', (p) => p.copyWith(cash: 1000, position: 35));
      s = ok(const Roll('p0', 1, 3), s);
      s = ok(const DeclareBankruptcy('p0'), s);
      expect(s.phase, GamePhase.gameOver);
      expect(s.winnerId, 'p1');
    });

    test('time limit: highest net worth wins', () {
      var s = startedGame();
      s = withOwned(s, 'p2', [39]);
      s = ok(const EndGameByLimit('p0'), s);
      expect(s.phase, GamePhase.gameOver);
      expect(s.winnerId, 'p2');
      expect(s.ranking.first, 'p2');
    });

    test('turn limit ends the game', () {
      var s = startedGame(n: 2, rules: const HouseRules(maxTurns: 1));
      s = withPlayer(s, 'p1', (p) => p.copyWith(cash: 2000000));
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 1));
      s = ok(const Roll('p0', 1, 2), s);
      s = ok(const EndTurn('p0'), s);
      expect(s.phase, GamePhase.gameOver);
      expect(s.winnerId, 'p1');
    });
  });

  group('house rules', () {
    test('Free Parking pot collects taxes and pays out', () {
      var s = startedGame(rules: const HouseRules(freeParkingPot: true));
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 1));
      s = ok(const Roll('p0', 1, 2), s); // Income Tax 2,00,000
      expect(s.freeParkingPot, 200000);
      s = ok(const EndTurn('p0'), s);
      s = withPlayer(s, 'p1', (p) => p.copyWith(position: 17));
      final before = cash(s, 'p1');
      s = ok(const Roll('p1', 1, 2), s); // Chai Break
      expect(cash(s, 'p1'), before + 200000);
      expect(s.freeParkingPot, 0);
      expect(s.totalMoney, s.startingTotal);
    });

    test('pot off: tax goes to the bank, Chai Break pays nothing', () {
      var s = startedGame();
      final bank = s.bank.cash;
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 1));
      s = ok(const Roll('p0', 1, 2), s);
      expect(s.freeParkingPot, 0);
      expect(s.bank.cash, bank + 200000);
    });

    test('double salary for landing exactly on Start', () {
      for (final on in [true, false]) {
        var s = startedGame(rules: HouseRules(doubleOnStart: on));
        s = withPlayer(s, 'p0', (p) => p.copyWith(position: 37));
        final before = cash(s, 'p0');
        s = ok(const Roll('p0', 1, 2), s);
        expect(cash(s, 'p0') - before, on ? 400000 : 200000);
      }
    });

    test('no auctions: decline returns to manage', () {
      var s = startedGame(rules: const HouseRules(auctions: false));
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 35));
      s = ok(const Roll('p0', 1, 3), s);
      s = ok(const DeclineBuy('p0'), s);
      expect(s.phase, GamePhase.manage);
      expect(s.auction, isNull);
    });

    test('quick game deals 2 random cities each', () {
      final s = startedGame(rules: const HouseRules(quickGame: true));
      for (final p in s.players) {
        expect(s.ownedBy(p.id), hasLength(2));
      }
      expect(s.rules.effectiveTimeLimitMin, 60);
      expect(startedGame().ownership, isEmpty);
    });
  });
}
