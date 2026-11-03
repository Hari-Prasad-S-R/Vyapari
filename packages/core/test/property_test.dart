import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';

import 'helpers.dart';

void main() {
  group('buying and auctions', () {
    test('buy Chennai with enough cash', () {
      var s = startedGame();
      final chennai = tileNamed(s, 'Chennai');
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: chennai - 4));
      final before = cash(s, 'p0');
      s = ok(const Roll('p0', 1, 3), s);
      s = ok(const Buy('p0'), s);
      expect(s.ownershipOf(chennai)!.ownerId, 'p0');
      expect(cash(s, 'p0'), before - 300000);
    });

    test('cannot buy without enough cash', () {
      var s = startedGame();
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 35, cash: 1000));
      s = ok(const Roll('p0', 1, 3), s);
      expect(apply(const Buy('p0'), s).error, ErrorCode.insufficientFunds);
    });

    test('declined city goes to the highest bidder', () {
      var s = startedGame();
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 35));
      s = ok(const Roll('p0', 1, 3), s); // Mumbai
      s = ok(const DeclineBuy('p0'), s);
      expect(s.phase, GamePhase.auction);
      s = ok(const Bid('p1', 10000), s);
      expect(apply(const Bid('p2', 15000), s).error, ErrorCode.invalidAction);
      s = ok(const Bid('p2', 20000), s);
      s = ok(const Bid('p0', 50000), s);
      s = ok(const Bid('p1', 120000), s);
      final before = cash(s, 'p1');
      s = ok(const CloseAuction('p0'), s);
      expect(s.ownershipOf(39)!.ownerId, 'p1');
      expect(cash(s, 'p1'), before - 120000);
      expect(s.phase, GamePhase.manage);
      expect(s.totalMoney, s.startingTotal);
    });

    test('one bidder wins at their bid', () {
      var s = startedGame();
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 35));
      s = ok(const Roll('p0', 1, 3), s);
      s = ok(const DeclineBuy('p0'), s);
      s = ok(const Bid('p2', 10000), s);
      s = ok(const CloseAuction('p0'), s);
      expect(s.ownershipOf(39)!.ownerId, 'p2');
    });

    test('no bids leaves the city with the bank', () {
      var s = startedGame();
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 35));
      s = ok(const Roll('p0', 1, 3), s);
      s = ok(const DeclineBuy('p0'), s);
      s = ok(const CloseAuction('p0'), s);
      expect(s.ownershipOf(39), isNull);
      expect(s.phase, GamePhase.manage);
    });

    test('cannot bid more than your cash', () {
      var s = startedGame();
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 35));
      s = ok(const Roll('p0', 1, 3), s);
      s = ok(const DeclineBuy('p0'), s);
      expect(apply(const Bid('p1', 9000000), s).error,
          ErrorCode.insufficientFunds);
    });
  });

  group('rent', () {
    GameState landOn(GameState s, int tile, {int d1 = 1, int d2 = 2}) {
      s = withPlayer(
          s, 'p0', (p) => p.copyWith(position: (tile - d1 - d2 + 40) % 40));
      return ok(Roll('p0', d1, d2), s);
    }

    test('base, full-set double, houses and hotel', () {
      final base = startedGame();
      final chennai = tileNamed(base, 'Chennai');
      final rents = base.tiles[chennai].rent;
      final cases = <(List<int>, int, int)>[
        ([chennai], 0, rents[0]),
        ([31, 32, 34], 0, rents[0] * 2),
        ([31, 32, 34], 1, rents[1]),
        ([31, 32, 34], 2, rents[2]),
        ([31, 32, 34], 3, rents[3]),
        ([31, 32, 34], 4, rents[4]),
        ([31, 32, 34], 5, rents[5]),
      ];
      for (final (owned, houses, expected) in cases) {
        var s = withOwned(base, 'p1', owned, houses: houses);
        final before = cash(s, 'p0');
        s = landOn(s, chennai);
        expect(before - cash(s, 'p0'), expected,
            reason: 'owned=$owned houses=$houses');
        expect(s.totalMoney, s.startingTotal);
      }
    });

    test('every city on the board charges its base rent', () {
      final base = startedGame();
      for (final t in base.tiles.where((t) => t.type == TileType.city)) {
        var s = withOwned(base, 'p1', [t.index]);
        final before = cash(s, 'p1');
        s = landOn(s, t.index);
        expect(cash(s, 'p1') - before, t.rent[0], reason: t.name);
      }
    });

    test('transport by count owned', () {
      final base = startedGame();
      const all = [5, 15, 25, 35];
      for (var n = 1; n <= 4; n++) {
        var s = withOwned(base, 'p1', all.take(n).toList());
        final before = cash(s, 'p0');
        s = landOn(s, 5);
        expect(before - cash(s, 'p0'), base.tiles[5].rent[n - 1]);
      }
    });

    test('utilities: dice × 4 or × 10 × unit', () {
      final base = startedGame();
      var s = withOwned(base, 'p1', [12]);
      var before = cash(s, 'p0');
      s = landOn(s, 12, d1: 3, d2: 5);
      expect(before - cash(s, 'p0'), 8 * 4 * 1000);

      s = withOwned(base, 'p1', [12, 28]);
      before = cash(s, 'p0');
      s = landOn(s, 28, d1: 3, d2: 5);
      expect(before - cash(s, 'p0'), 8 * 10 * 1000);
    });

    test('no rent on mortgaged tiles or to yourself', () {
      final base = startedGame();
      var s = withOwned(base, 'p1', [31, 32, 34], mortgaged: true);
      var before = cash(s, 'p0');
      s = landOn(s, 31);
      expect(cash(s, 'p0'), before);

      s = withOwned(base, 'p0', [31]);
      before = cash(s, 'p0');
      s = landOn(s, 31);
      expect(cash(s, 'p0'), before);
    });

    test('noRentInJail toggle', () {
      final base = startedGame(rules: const HouseRules(noRentInJail: true));
      var s = withOwned(base, 'p1', [31]);
      s = withPlayer(s, 'p1', (p) => p.copyWith(inJail: true, position: 10));
      final before = cash(s, 'p0');
      s = landOn(s, 31);
      expect(cash(s, 'p0'), before);
    });
  });

  group('building and mortgages', () {
    test('build on an incomplete set fails', () {
      var s = startedGame();
      s = withOwned(s, 'p0', [31, 32]);
      expect(apply(const Build('p0', 31), s).error, ErrorCode.incompleteSet);
    });

    test('even-build rule', () {
      var s = startedGame();
      s = withOwned(s, 'p0', [31, 32, 34]);
      s = ok(const Build('p0', 31), s);
      expect(apply(const Build('p0', 31), s).error, ErrorCode.unevenBuild);
      s = ok(const Build('p0', 32), s);
      s = ok(const Build('p0', 34), s);
      s = ok(const Build('p0', 31), s);
      expect(s.ownershipOf(31)!.houses, 2);
      expect(
          apply(const SellBuilding('p0', 32), s).error, ErrorCode.unevenBuild);
      s = ok(const SellBuilding('p0', 31), s);
      expect(s.totalMoney, s.startingTotal);
    });

    test('bank with no houses refuses', () {
      var s = startedGame();
      s = withOwned(s, 'p0', [31, 32, 34]);
      s = s.copyWith(bank: s.bank.copyWith(houses: 0));
      expect(apply(const Build('p0', 31), s).error, ErrorCode.noHousesLeft);
    });

    test('hotel needs a hotel in the bank and returns 4 houses', () {
      var s = startedGame();
      s = withOwned(s, 'p0', [37, 39], houses: 4);
      s = s.copyWith(bank: s.bank.copyWith(houses: 24, hotels: 0));
      expect(apply(const Build('p0', 37), s).error, ErrorCode.noHotelsLeft);
      s = s.copyWith(bank: s.bank.copyWith(hotels: 1));
      s = ok(const Build('p0', 37), s);
      expect(s.ownershipOf(37)!.houses, 5);
      expect(s.bank.houses, 28);
      expect(s.bank.hotels, 0);
    });

    test('cannot build on a mortgaged set', () {
      var s = startedGame();
      s = withOwned(s, 'p0', [37, 39]);
      s = ok(const Mortgage('p0', 39), s);
      expect(apply(const Build('p0', 37), s).error, ErrorCode.mortgaged);
    });

    test('cannot mortgage with buildings in the group', () {
      var s = startedGame();
      s = withOwned(s, 'p0', [37, 39]);
      s = ok(const Build('p0', 37), s);
      expect(apply(const Mortgage('p0', 39), s).error, ErrorCode.hasBuildings);
    });

    test('sell at half cost; mortgage at half price; unmortgage +10%', () {
      var s = startedGame();
      s = withOwned(s, 'p0', [37, 39]);
      final c0 = cash(s, 'p0');
      s = ok(const Build('p0', 39), s);
      s = ok(const SellBuilding('p0', 39), s);
      expect(cash(s, 'p0'), c0 - 200000 + 100000);
      final c1 = cash(s, 'p0');
      s = ok(const Mortgage('p0', 39), s);
      expect(cash(s, 'p0'), c1 + 200000);
      s = ok(const Unmortgage('p0', 39), s);
      expect(cash(s, 'p0'), c1 + 200000 - 220000);
      expect(s.ownershipOf(39)!.mortgaged, isFalse);
      expect(s.totalMoney, s.startingTotal);
    });

    test('only the owner can build or mortgage', () {
      var s = startedGame();
      s = withOwned(s, 'p1', [37, 39]);
      expect(apply(const Build('p0', 37), s).error, ErrorCode.notOwner);
      expect(apply(const Mortgage('p0', 37), s).error, ErrorCode.notOwner);
    });
  });
}
