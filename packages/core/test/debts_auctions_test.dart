import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';

import 'helpers.dart';

/// p0 draws the Undiyal wedding card (collect ₹50,000 from every player).
GameState drawWedding(GameState s) {
  s = withTopCard(s, Deck.undiyal, 'u07');
  s = withPlayer(s, 'p0', (p) => p.copyWith(position: 14));
  return ok(const Roll('p0', 1, 2), s); // → 17 Undiyal
}

void main() {
  group('collect from each player (official rules)', () {
    test('a short payer must raise cash before play continues', () {
      var s = startedGame();
      s = withOwned(s, 'p1', [3]); // Bhopal, mortgage value 30,000
      s = withPlayer(s, 'p1', (p) => p.copyWith(cash: 30000));
      final total = s.totalMoney;
      final p0 = cash(s, 'p0');
      s = drawWedding(s);
      expect(s.phase, GamePhase.raiseCash);
      expect(s.actingPlayer, 'p1');
      expect(s.debtOf('p1'), 50000);
      // p2 could pay at once; p1 still owes.
      expect(cash(s, 'p0'), p0 + 50000);
      expect(apply(const EndTurn('p0'), s).error, ErrorCode.illegalPhase);
      expect(apply(const PayDebt('p0'), s).error, ErrorCode.notYourTurn);
      expect(apply(const PayDebt('p1'), s).error, ErrorCode.insufficientFunds);
      s = ok(const Mortgage('p1', 3), s); // 30,000 + 30,000 = 60,000
      s = ok(const PayDebt('p1'), s);
      expect(s.phase, GamePhase.manage);
      expect(s.currentPlayer, 'p0');
      expect(cash(s, 'p0'), p0 + 100000);
      expect(cash(s, 'p1'), 10000);
      expect(s.totalMoney, total);
    });

    test('several short payers settle one at a time in seat order', () {
      var s = startedGame(n: 4);
      s = withPlayer(s, 'p1', (p) => p.copyWith(cash: 0));
      s = withPlayer(s, 'p3', (p) => p.copyWith(cash: 0));
      s = withOwned(s, 'p3', [5]);
      final total = s.totalMoney;
      s = drawWedding(s);
      expect(s.actingPlayer, 'p1');
      expect(
          apply(const DeclareBankruptcy('p3'), s).error, ErrorCode.notYourTurn);
      s = ok(const DeclareBankruptcy('p1'), s);
      expect(s.player('p1')!.bankrupt, isTrue);
      expect(s.phase, GamePhase.raiseCash);
      expect(s.actingPlayer, 'p3');
      s = ok(const Mortgage('p3', 5), s); // +1,00,000
      s = ok(const PayDebt('p3'), s);
      expect(s.phase, GamePhase.manage);
      expect(s.currentPlayer, 'p0');
      expect(s.totalMoney, total);
    });

    test('a payer who cannot raise it goes bankrupt to the card drawer', () {
      var s = startedGame();
      s = withOwned(s, 'p1', [5]);
      s = withPlayer(s, 'p1', (p) => p.copyWith(cash: 1000));
      final total = s.totalMoney;
      final p0 = cash(s, 'p0');
      s = drawWedding(s);
      s = ok(const DeclareBankruptcy('p1'), s);
      expect(s.player('p1')!.bankrupt, isTrue);
      expect(s.ownershipOf(5)!.ownerId, 'p0');
      // 50,000 from p2 plus p1's last 1,000.
      expect(cash(s, 'p0'), p0 + 50000 + 1000);
      expect(s.auction, isNull, reason: 'owed to a player, not the bank');
      expect(s.phase, GamePhase.manage);
      expect(s.totalMoney, total);
    });
  });

  group('bankrupt to the bank: every city is auctioned', () {
    test('cities go to auction one after another, then play resumes', () {
      var s = startedGame();
      s = withOwned(s, 'p0', [1, 3], houses: 1);
      s = withOwned(s, 'p0', [39]);
      s = s.copyWith(ownership: [
        for (final o in s.ownership)
          o.tileIndex == 39 ? o.copyWith(mortgaged: true) : o,
      ]);
      s = withPlayer(s, 'p0', (p) => p.copyWith(cash: 1000, position: 1));
      final total = s.totalMoney;
      s = ok(const Roll('p0', 1, 2), s); // Income Tax 2,00,000
      s = ok(const DeclareBankruptcy('p0'), s);
      expect(s.player('p0')!.bankrupt, isTrue);
      expect(s.currentPlayer, 'p1');
      expect(s.phase, GamePhase.auction);
      expect(s.auction!.tileIndex, 1);
      expect(s.auctionQueue, [3, 39]);
      // The test granted 2 houses for free; both go back to the bank.
      expect(s.bank.houses, 34, reason: 'buildings returned first');

      s = ok(const Bid('p2', 40000), s);
      s = ok(const CloseAuction('p1'), s);
      expect(s.ownershipOf(1)!.ownerId, 'p2');
      expect(s.auction!.tileIndex, 3);
      s = ok(const CloseAuction('p1'), s); // nobody bids on Bhopal
      expect(s.ownershipOf(3), isNull);
      expect(s.auction!.tileIndex, 39);
      s = ok(const Bid('p1', 300000), s);
      s = ok(const CloseAuction('p1'), s);
      expect(s.ownershipOf(39)!.ownerId, 'p1');
      expect(s.ownershipOf(39)!.mortgaged, isFalse,
          reason: 'sold free of mortgage');
      expect(s.auction, isNull);
      expect(s.auctionQueue, isEmpty);
      expect(s.phase, GamePhase.awaitingRoll);
      expect(s.currentPlayer, 'p1');
      expect(s.totalMoney, total);
    });

    test('a player leaving mid-game has their cities auctioned', () {
      var s = startedGame();
      s = withOwned(s, 'p2', [5]);
      s = ok(const LeaveGame('p2'), s);
      expect(s.phase, GamePhase.auction);
      expect(s.auction!.tileIndex, 5);
      expect(s.currentPlayer, 'p0');
      s = ok(const CloseAuction('p0'), s);
      expect(s.phase, GamePhase.awaitingRoll, reason: 'back where p0 was');
      expect(s.currentPlayer, 'p0');
    });

    test('auction queue survives a save', () {
      var s = startedGame();
      s = withOwned(s, 'p2', [5, 15]);
      s = ok(const LeaveGame('p2'), s);
      final back = GameState.fromJson(s.toJson());
      expect(back.auctionQueue, [15]);
      expect(back.resumePhase, GamePhase.awaitingRoll);
      expect(back, s);
    });
  });
}
