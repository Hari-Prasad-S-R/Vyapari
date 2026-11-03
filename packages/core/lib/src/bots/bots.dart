import 'dart:math';

import '../dice/fair_dice.dart';
import '../models/game_state.dart';
import '../models/misc.dart';
import '../models/player.dart';
import '../models/tile.dart';
import '../rules/actions.dart';
import '../rules/engine.dart';
import '../rules/queries.dart';

/// A computer player. Bots propose actions in order of preference; the
/// driver applies the first one the rules engine accepts.
abstract class Bot {
  /// Creates a bot using [rng] for its own choices (never for dice).
  Bot(this.rng);

  /// Randomness for decisions.
  final RandomSource rng;

  /// Difficulty.
  BotLevel get level;

  /// Bot for [level].
  factory Bot.forLevel(BotLevel level, RandomSource rng) => switch (level) {
        BotLevel.easy => EasyBot(rng),
        BotLevel.medium => MediumBot(rng),
        BotLevel.hard => HardBot(rng),
      };

  /// Candidate actions for [me], best first. Empty means "nothing to do"
  /// (for example, passing in an auction).
  List<GameAction> candidates(GameState s, String me) {
    final p = s.player(me);
    if (p == null || p.bankrupt) return const [];
    if (s.phase == GamePhase.lobby || s.phase == GamePhase.gameOver) {
      return const [];
    }
    final out = <GameAction>[];
    if (s.phase != GamePhase.auction) {
      for (final t in s.trades.where((t) => t.to == me)) {
        out.add(judgeTrade(s, me, t)
            ? AcceptTrade(me, t.id)
            : RejectTrade(me, t.id));
      }
      if (out.isNotEmpty) return out;
    }
    if (s.phase == GamePhase.auction) {
      final bid = auctionBid(s, me);
      return bid == null ? const [] : [Bid(me, bid)];
    }
    if (s.actingPlayer != me) return const [];
    switch (s.phase) {
      case GamePhase.awaitingRoll:
        if (p.inJail) out.addAll(jailChoice(s, p));
        out.addAll(proposeTrades(s, me));
        out.add(Roll.intent(me));
      case GamePhase.awaitingBuy:
        final tile = s.tiles[p.position];
        if (p.cash >= tile.price && shouldBuy(s, p, tile)) out.add(Buy(me));
        out.add(DeclineBuy(me));
      case GamePhase.manage:
        out.addAll(buildChoices(s, p));
        out.addAll(unmortgageChoices(s, p));
        out.add(s.rollAgain ? Roll.intent(me) : EndTurn(me));
      case GamePhase.raiseCash:
        if (p.cash >= s.debtOf(me)) {
          out.add(PayDebt(me));
        } else {
          out.addAll(liquidationSteps(s, me));
          out.add(DeclareBankruptcy(me));
        }
      case GamePhase.lobby || GamePhase.auction || GamePhase.gameOver:
        break;
    }
    return out;
  }

  /// Whether to buy [tile] at list price.
  bool shouldBuy(GameState s, Player p, Tile tile);

  /// Bid amount in the current auction, or `null` to pass.
  int? auctionBid(GameState s, String me);

  /// Builds to try in the manage phase.
  List<GameAction> buildChoices(GameState s, Player p);

  /// Jail actions to try before rolling.
  List<GameAction> jailChoice(GameState s, Player p) => [
        if (p.getOutCards.isNotEmpty) UseJailCard(p.id),
        if (p.cash > 500000) PayJailFine(p.id),
      ];

  /// Unmortgages to try in the manage phase.
  List<GameAction> unmortgageChoices(GameState s, Player p) => const [];

  /// Trades to propose at the start of a turn.
  List<GameAction> proposeTrades(GameState s, String me) => const [];

  /// Whether to accept an incoming trade.
  bool judgeTrade(GameState s, String me, Trade t) => false;

  /// Sell/mortgage steps to raise cash, cheapest loss first.
  List<GameAction> liquidationSteps(GameState s, String me) {
    final mine = s.ownedBy(me);
    final sells = mine.where((o) => o.houses > 0).toList()
      ..sort((a, b) => b.houses.compareTo(a.houses));
    final mortgages = mine.where((o) => !o.mortgaged).toList()
      ..sort((a, b) =>
          s.tiles[a.tileIndex].price.compareTo(s.tiles[b.tileIndex].price));
    return [
      for (final o in sells) SellBuilding(me, o.tileIndex),
      for (final o in mortgages) Mortgage(me, o.tileIndex),
    ];
  }

  /// Even-build candidates on full sets keeping [reserve] cash, up to
  /// [maxHouses] per tile.
  List<GameAction> evenBuilds(GameState s, Player p,
      {required int reserve, int maxHouses = 5}) {
    final out = <GameAction>[];
    final groups = s.tiles
        .where((t) => t.type == TileType.city)
        .map((t) => t.group!)
        .toSet();
    for (final g in groups) {
      if (!s.ownsFullGroup(p.id, g)) continue;
      final owned =
          s.groupTiles(g).map((t) => s.ownershipOf(t.index)!).toList();
      if (owned.any((o) => o.mortgaged)) continue;
      owned.sort((a, b) => a.houses.compareTo(b.houses));
      final o = owned.first;
      final tile = s.tiles[o.tileIndex];
      if (o.houses < maxHouses && p.cash - tile.houseCost >= reserve) {
        out.add(Build(p.id, o.tileIndex));
      }
    }
    return out;
  }
}

/// Random legal moves.
class EasyBot extends Bot {
  /// Creates an easy bot.
  EasyBot(super.rng);

  @override
  BotLevel get level => BotLevel.easy;

  @override
  bool shouldBuy(GameState s, Player p, Tile tile) => rng.nextInt(2) == 0;

  @override
  int? auctionBid(GameState s, String me) {
    final auc = s.auction!;
    final p = s.player(me)!;
    final minBid = auc.highBid == 0 ? auc.minStep : auc.highBid + auc.minStep;
    if (auc.highBidder == me) return null;
    if (minBid > s.tiles[auc.tileIndex].price || minBid > p.cash ~/ 3) {
      return null;
    }
    return rng.nextInt(4) == 0 ? minBid : null;
  }

  @override
  List<GameAction> buildChoices(GameState s, Player p) =>
      rng.nextInt(3) == 0 ? evenBuilds(s, p, reserve: 100000) : const [];

  @override
  List<GameAction> jailChoice(GameState s, Player p) =>
      rng.nextInt(2) == 0 ? super.jailChoice(s, p) : const [];

  @override
  bool judgeTrade(GameState s, String me, Trade t) => rng.nextInt(4) == 0;
}

/// Buys with a ₹3,00,000 cushion and builds on full sets.
class MediumBot extends Bot {
  /// Creates a medium bot.
  MediumBot(super.rng);

  /// Cash kept after any purchase.
  static const reserve = 300000;

  @override
  BotLevel get level => BotLevel.medium;

  @override
  bool shouldBuy(GameState s, Player p, Tile tile) =>
      p.cash - tile.price > reserve;

  @override
  int? auctionBid(GameState s, String me) {
    final auc = s.auction!;
    final p = s.player(me)!;
    if (auc.highBidder == me) return null;
    final minBid = auc.highBid == 0 ? auc.minStep : auc.highBid + auc.minStep;
    final price = s.tiles[auc.tileIndex].price;
    if (minBid <= price && p.cash - minBid > reserve) {
      return max(minBid, min(price ~/ 2, p.cash - reserve));
    }
    return null;
  }

  @override
  List<GameAction> buildChoices(GameState s, Player p) =>
      evenBuilds(s, p, reserve: reserve);

  @override
  List<GameAction> unmortgageChoices(GameState s, Player p) => [
        for (final o in s.ownedBy(p.id).where((o) => o.mortgaged))
          if (p.cash - s.unmortgageCost(s.tiles[o.tileIndex]) > reserve * 2)
            Unmortgage(p.id, o.tileIndex),
      ];

  @override
  bool judgeTrade(GameState s, String me, Trade t) =>
      tradeValueFor(s, me, t) > 0;
}

/// Values set completion, trades sensibly and keeps a cash reserve.
class HardBot extends Bot {
  /// Creates a hard bot.
  HardBot(super.rng);

  @override
  BotLevel get level => BotLevel.hard;

  /// Turn of the last proposal, so a rejected offer is not repeated at once.
  int _lastProposalTurn = -1;

  /// Cash reserve scaled to the worst rent on the board.
  int reserveFor(GameState s, String me) {
    var worst = 0;
    for (final o in s.ownership) {
      if (o.ownerId == me || o.mortgaged) continue;
      worst = max(worst, s.rentFor(o.tileIndex, 7));
    }
    return min(400000, max(100000, worst ~/ 2));
  }

  @override
  bool shouldBuy(GameState s, Player p, Tile tile) {
    final helps = _groupInterest(s, p.id, tile) > 0;
    final r = reserveFor(s, p.id);
    return p.cash - tile.price > (helps ? r ~/ 2 : r);
  }

  /// >0 if [tile] advances my set, <0 if it would complete someone else's.
  int _groupInterest(GameState s, String me, Tile tile) {
    final g = tile.group;
    if (g == null) return 0;
    final group = s.groupTiles(g);
    final mine =
        group.where((t) => s.ownershipOf(t.index)?.ownerId == me).length;
    if (mine > 0) return mine;
    final owners = group
        .map((t) => s.ownershipOf(t.index)?.ownerId)
        .whereType<String>()
        .toSet();
    if (owners.length == 1 &&
        group.where((t) => s.ownershipOf(t.index) != null).length ==
            group.length - 1) {
      return -1;
    }
    return 0;
  }

  /// How much a tile is worth to [me].
  int tileValue(GameState s, String me, int index) {
    final tile = s.tiles[index];
    final g = tile.group;
    if (g == null) return tile.price;
    final group = s.groupTiles(g);
    final mine = group
        .where((t) => t.index != index && s.ownershipOf(t.index)?.ownerId == me)
        .length;
    if (mine == group.length - 1) return tile.price * 3;
    if (mine > 0) return tile.price * 3 ~/ 2;
    return tile.price;
  }

  @override
  int? auctionBid(GameState s, String me) {
    final auc = s.auction!;
    final p = s.player(me)!;
    if (auc.highBidder == me) return null;
    final minBid = auc.highBid == 0 ? auc.minStep : auc.highBid + auc.minStep;
    final tile = s.tiles[auc.tileIndex];
    final interest = _groupInterest(s, me, tile);
    final value = interest > 0
        ? tile.price * 8 ~/ 5
        : interest < 0
            ? tile.price * 13 ~/ 10
            : tile.price * 9 ~/ 10;
    final cap = min(value, p.cash - reserveFor(s, me) ~/ 2);
    return minBid <= cap ? minBid : null;
  }

  @override
  List<GameAction> buildChoices(GameState s, Player p) {
    final r = reserveFor(s, p.id);
    final toThree = evenBuilds(s, p, reserve: r ~/ 2, maxHouses: 3);
    return toThree.isNotEmpty ? toThree : evenBuilds(s, p, reserve: r);
  }

  @override
  List<GameAction> jailChoice(GameState s, Player p) {
    // Late game, jail is a safe place: stay and roll.
    final dangerous = s.ownership.where((o) => o.houses >= 3).length >= 3;
    if (dangerous) return const [];
    return super.jailChoice(s, p);
  }

  @override
  List<GameAction> unmortgageChoices(GameState s, Player p) {
    final r = reserveFor(s, p.id) * 2;
    return [
      for (final o in s.ownedBy(p.id).where((o) => o.mortgaged))
        if (p.cash - s.unmortgageCost(s.tiles[o.tileIndex]) > r)
          Unmortgage(p.id, o.tileIndex),
    ];
  }

  @override
  List<GameAction> proposeTrades(GameState s, String me) {
    // At most one open offer, one proposal per turn, every third turn.
    if (s.trades.any((t) => t.from == me)) return const [];
    if (s.turnNumber % 3 != 0 || s.turnNumber == _lastProposalTurn) {
      return const [];
    }
    final p = s.player(me)!;
    for (final g in s.tiles
        .where((t) => t.type == TileType.city)
        .map((t) => t.group!)
        .toSet()) {
      final group = s.groupTiles(g);
      final missing =
          group.where((t) => s.ownershipOf(t.index)?.ownerId != me).toList();
      if (missing.length != 1) continue;
      final o = s.ownershipOf(missing.first.index);
      if (o == null) continue;
      final owner = s.player(o.ownerId);
      if (owner == null || owner.bankrupt || !owner.connected) continue;
      if (s.groupHasBuildings(g)) continue;
      final offer = missing.first.price * 3 ~/ 2;
      if (p.cash - offer < reserveFor(s, me)) continue;
      _lastProposalTurn = s.turnNumber;
      return [
        ProposeTrade(me,
            to: owner.id,
            give: TradeSide(cash: offer),
            get: TradeSide(tiles: [missing.first.index])),
      ];
    }
    return const [];
  }

  @override
  bool judgeTrade(GameState s, String me, Trade t) {
    final opponent = t.from;
    var value = tradeValueFor(s, me, t);
    // Giving a tile that completes the opponent's set costs extra.
    for (final i in t.get.tiles) {
      final g = s.tiles[i].group;
      if (g == null) continue;
      final group = s.groupTiles(g);
      final theirs = group
          .where((x) =>
              x.index != i && s.ownershipOf(x.index)?.ownerId == opponent)
          .length;
      if (theirs == group.length - 1) value -= s.tiles[i].price * 2;
    }
    final p = s.player(me)!;
    return value > 0 && p.cash - t.get.cash >= reserveFor(s, me) ~/ 2;
  }

  /// Value of a trade for [me] using this bot's tile valuation.
  int tradeValueFor(GameState s, String me, Trade t) {
    int side(TradeSide x) =>
        x.cash +
        x.cards * 50000 +
        x.tiles.fold(0, (sum, i) => sum + tileValue(s, me, i));
    final incoming = side(t.give);
    final outgoing = side(t.get);
    return incoming - outgoing;
  }
}

/// Simple trade valuation from the receiver's view: list prices, cash, and
/// ₹50,000 per get-out card.
int tradeValueFor(GameState s, String me, Trade t) {
  int side(TradeSide x) =>
      x.cash +
      x.cards * 50000 +
      x.tiles.fold(0, (sum, i) => sum + s.tiles[i].price);
  return side(t.give) - side(t.get);
}

/// Applies the first of [bot]'s candidates that the engine accepts, filling
/// roll intents with [rollDice]. Returns `null` if nothing was accepted.
ApplyResult? botAct(
    Bot bot, GameState s, String me, List<int> Function() rollDice) {
  for (final a in bot.candidates(s, me)) {
    final action = a is Roll && !a.hasDice
        ? (() {
            final d = rollDice();
            return Roll(me, d[0], d[1]);
          })()
        : a;
    final r = apply(action, s);
    if (r.ok) return r;
  }
  return null;
}
