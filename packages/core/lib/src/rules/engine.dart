import 'dart:math';

import '../models/card.dart';
import '../models/game_state.dart';
import '../models/misc.dart';
import '../models/player.dart';
import '../models/rules.dart';
import '../models/tile.dart';
import '../money.dart';
import 'actions.dart';
import 'queries.dart';

/// Result of applying an action: the new state and events, or an error with
/// the original state unchanged.
class ApplyResult {
  const ApplyResult._(this.state, this.events, this.error);

  /// Successful result.
  const ApplyResult.ok(GameState state, List<GameEvent> events)
      : this._(state, events, null);

  /// Rejected result.
  const ApplyResult.rejected(GameState state, ErrorCode error)
      : this._(state, const [], error);

  /// New state (or unchanged state if rejected).
  final GameState state;

  /// Events produced, in order.
  final List<GameEvent> events;

  /// Reason code if rejected.
  final ErrorCode? error;

  /// Whether the action was accepted.
  bool get ok => error == null;
}

/// Maximum events kept in [GameState.log].
const maxLogEntries = 200;

/// The rules engine reducer: `apply(action, state) -> (newState, events)`.
///
/// Pure and deterministic: all randomness (dice, seeds) arrives inside the
/// action. Illegal actions return a reason code and the unchanged state.
ApplyResult apply(GameAction action, GameState state) {
  final d = _Draft(state);
  final error = d.run(action);
  if (error != null) return ApplyResult.rejected(state, error);
  return ApplyResult.ok(d.freeze(), List.unmodifiable(d.events));
}

class _Reject implements Exception {
  _Reject(this.code);
  final ErrorCode code;
}

Never _fail(ErrorCode code) => throw _Reject(code);

/// Mutable working copy used inside one `apply` call.
class _Draft {
  _Draft(this.s)
      : players = [...s.players],
        ownership = [...s.ownership],
        bank = s.bank,
        vaaippu = [...s.decks.vaaippu],
        undiyal = [...s.decks.undiyal],
        pot = s.freeParkingPot,
        phase = s.phase,
        current = s.currentPlayer,
        hostId = s.hostId,
        rules = s.rules,
        auction = s.auction,
        trades = [...s.trades],
        debts = [...s.debts],
        rollAgain = s.rollAgain,
        lastDice = s.lastDice,
        turnNumber = s.turnNumber,
        winnerId = s.winnerId,
        startingTotal = s.startingTotal,
        nextTradeId = s.nextTradeId;

  final GameState s;
  final List<Player> players;
  final List<Ownership> ownership;
  Bank bank;
  final List<String> vaaippu;
  final List<String> undiyal;
  int pot;
  GamePhase phase;
  String? current;
  String? hostId;
  HouseRules rules;
  Auction? auction;
  final List<Trade> trades;
  final List<Debt> debts;
  bool rollAgain;
  List<int> lastDice;
  int turnNumber;
  String? winnerId;
  int startingTotal;
  int nextTradeId;
  final List<GameEvent> events = [];

  /// Set when the current player lands on an unowned property.
  bool _offerBuy = false;

  GameConfig get config => s.config;
  List<Tile> get tiles => s.tiles;

  GameState freeze() => GameState(
        roomId: s.roomId,
        version: s.version + 1,
        phase: phase,
        players: players,
        tiles: s.tiles,
        cards: s.cards,
        ownership: ownership,
        currentPlayer: current,
        hostId: hostId,
        bank: bank,
        decks: Decks(vaaippu: vaaippu, undiyal: undiyal),
        freeParkingPot: pot,
        rules: rules,
        config: s.config,
        log: _cappedLog(),
        auction: auction,
        trades: trades,
        debts: debts,
        rollAgain: rollAgain,
        lastDice: lastDice,
        turnNumber: turnNumber,
        winnerId: winnerId,
        startingTotal: startingTotal,
        nextTradeId: nextTradeId,
      );

  List<GameEvent> _cappedLog() {
    if (events.isEmpty) return s.log;
    final all = [...s.log, ...events];
    return all.length > maxLogEntries
        ? all.sublist(all.length - maxLogEntries)
        : all;
  }

  // ---------------------------------------------------------------- helpers

  Player? find(String? id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  Player p(String id) => find(id) ?? _fail(ErrorCode.notFound);

  void put(Player np) {
    final i = players.indexWhere((x) => x.id == np.id);
    players[i] = np;
  }

  void update(String id, Player Function(Player) f) => put(f(p(id)));

  Ownership? own(int index) {
    for (final o in ownership) {
      if (o.tileIndex == index) return o;
    }
    return null;
  }

  void putOwn(Ownership o) {
    final i = ownership.indexWhere((x) => x.tileIndex == o.tileIndex);
    if (i < 0) {
      ownership.add(o);
    } else {
      ownership[i] = o;
    }
  }

  void removeOwn(int index) =>
      ownership.removeWhere((o) => o.tileIndex == index);

  List<Tile> groupTiles(String g) => tiles.where((t) => t.group == g).toList();

  bool ownsGroup(String id, String g) =>
      groupTiles(g).every((t) => own(t.index)?.ownerId == id);

  int get jailIndex =>
      tiles.firstWhere((t) => t.corner == CornerKind.jail).index;

  String name(String? id) => find(id)?.name ?? 'Bank';

  void log(String type, String text,
          {String? playerId, Map<String, Object?> data = const {}}) =>
      events.add(GameEvent(type, playerId: playerId, data: data, text: text));

  void requireCurrent(String id) {
    if (current != id) _fail(ErrorCode.notYourTurn);
  }

  void requirePhase(Set<GamePhase> allowed) {
    if (!allowed.contains(phase)) _fail(ErrorCode.illegalPhase);
  }

  void requireHost(String id) {
    if (hostId != id) _fail(ErrorCode.hostOnly);
  }

  Player requireActive(String id) {
    final pl = p(id);
    if (pl.bankrupt) _fail(ErrorCode.illegalPhase);
    return pl;
  }

  // ---------------------------------------------------------------- money

  void bankPays(String id, int amount) {
    if (amount <= 0) return;
    bank = bank.copyWith(cash: bank.cash - amount);
    update(id, (x) => x.copyWith(cash: x.cash + amount));
  }

  void paysBank(String id, int amount) {
    if (amount <= 0) return;
    update(id, (x) => x.copyWith(cash: x.cash - amount));
    bank = bank.copyWith(cash: bank.cash + amount);
  }

  void transfer(String from, String to, int amount) {
    if (amount <= 0) return;
    update(from, (x) => x.copyWith(cash: x.cash - amount));
    update(to, (x) => x.copyWith(cash: x.cash + amount));
  }

  /// Settles one debt item from [payer]'s cash.
  void settle(String payer, Debt debt) {
    if (debt.creditorId != null) {
      transfer(payer, debt.creditorId!, debt.amount);
    } else if (debt.toPot) {
      update(payer, (x) => x.copyWith(cash: x.cash - debt.amount));
      pot += debt.amount;
    } else {
      paysBank(payer, debt.amount);
    }
  }

  /// Charges [payer]; if they cannot pay now the charge becomes a debt.
  /// Returns whether it was paid immediately.
  bool charge(String payer, int amount, {String? to, bool fine = false}) {
    if (amount <= 0) return true;
    final debt = Debt(
        amount: amount,
        creditorId: to,
        toPot: to == null && fine && rules.freeParkingPot);
    if (debts.isEmpty && p(payer).cash >= amount) {
      settle(payer, debt);
      return true;
    }
    debts.add(debt);
    log('debt',
        '${name(payer)} owes ${formatRupees(amount)} to ${to == null ? (debt.toPot ? 'the Chai Break pot' : 'the bank') : name(to)}',
        playerId: payer, data: {'amount': amount, 'to': to});
    return false;
  }

  // ---------------------------------------------------------------- movement

  void paySalary(String id, {required bool exact}) {
    final amount = config.salary * (exact && rules.doubleOnStart ? 2 : 1);
    bankPays(id, amount);
    log('salary',
        '${name(id)} passed Start and collected ${formatRupees(amount)}',
        playerId: id, data: {'amount': amount});
  }

  void moveBy(String id, int steps) {
    final from = p(id).position;
    final raw = from + steps;
    final to = raw % tiles.length;
    log('moved', '${name(id)} moved to ${tiles[to].name}',
        playerId: id, data: {'from': from, 'to': to, 'steps': steps});
    update(id, (x) => x.copyWith(position: to));
    if (raw >= tiles.length) paySalary(id, exact: to == 0);
    resolveLanding(id);
  }

  void moveTo(String id, int target) {
    final from = p(id).position;
    final steps = (target - from + tiles.length) % tiles.length;
    log('moved', '${name(id)} moved to ${tiles[target].name}',
        playerId: id, data: {'from': from, 'to': target, 'steps': steps});
    update(id, (x) => x.copyWith(position: target));
    if (target < from || (target == 0 && from != 0)) {
      paySalary(id, exact: target == 0);
    }
    resolveLanding(id);
  }

  void moveBack(String id, int steps) {
    final from = p(id).position;
    final to = (from - steps + tiles.length) % tiles.length;
    log('moved', '${name(id)} went back to ${tiles[to].name}',
        playerId: id, data: {'from': from, 'to': to, 'steps': -steps});
    update(id, (x) => x.copyWith(position: to));
    resolveLanding(id);
  }

  void sendToJail(String id) {
    update(
        id,
        (x) => x.copyWith(
            position: jailIndex, inJail: true, jailTurns: 0, doublesInRow: 0));
    rollAgain = false;
    log('jailed', '${name(id)} was sent to Jail', playerId: id);
  }

  void resolveLanding(String id) {
    final pl = p(id);
    final tile = tiles[pl.position];
    switch (tile.type) {
      case TileType.city || TileType.transport || TileType.utility:
        final o = own(tile.index);
        if (o == null) {
          // With unpaid debts the purchase offer is skipped.
          if (debts.isEmpty) _offerBuy = true;
          return;
        }
        if (o.ownerId == id || o.mortgaged) return;
        final owner = p(o.ownerId);
        if (owner.bankrupt) return;
        if (rules.noRentInJail && owner.inJail) {
          log('rent_skipped', '${owner.name} is in Jail and collects no rent',
              playerId: id);
          return;
        }
        final total = lastDice.isEmpty ? 0 : lastDice[0] + lastDice[1];
        final rent = freezeView().rentFor(tile.index, total);
        log('rent',
            '${pl.name} paid ${formatRupees(rent)} rent to ${owner.name} for ${tile.name}',
            playerId: id,
            data: {'amount': rent, 'to': owner.id, 'tile': tile.index});
        charge(id, rent, to: owner.id);
      case TileType.tax:
        log('tax',
            '${pl.name} paid ${tile.name} of ${formatRupees(tile.amount)}',
            playerId: id, data: {'amount': tile.amount, 'tile': tile.index});
        charge(id, tile.amount, fine: true);
      case TileType.card:
        drawCard(id, tile.deck!);
      case TileType.corner:
        switch (tile.corner!) {
          case CornerKind.goToJail:
            sendToJail(id);
          case CornerKind.freeParking:
            if (rules.freeParkingPot && pot > 0) {
              final amount = pot;
              pot = 0;
              update(id, (x) => x.copyWith(cash: x.cash + amount));
              log('pot',
                  '${pl.name} collected the Chai Break pot of ${formatRupees(amount)}',
                  playerId: id, data: {'amount': amount});
            }
          case CornerKind.start || CornerKind.jail:
            break;
        }
    }
  }

  // ---------------------------------------------------------------- cards

  void drawCard(String id, Deck deck) {
    final pile = deck == Deck.vaaippu ? vaaippu : undiyal;
    if (pile.isEmpty) return;
    final cardId = pile.removeAt(0);
    final card = s.card(cardId);
    final deckName = deck == Deck.vaaippu ? 'Vaaippu' : 'Undiyal';
    log('card', '${name(id)} drew $deckName: ${card.text}',
        playerId: id, data: {'card': cardId, 'deck': deck.name});
    final e = card.effect;
    if (e.type == CardEffectType.getOutOfJail) {
      update(id, (x) => x.copyWith(getOutCards: [...x.getOutCards, cardId]));
      return;
    }
    pile.add(cardId);
    switch (e.type) {
      case CardEffectType.collect:
        bankPays(id, e.amount);
      case CardEffectType.pay:
        charge(id, e.amount, fine: true);
      case CardEffectType.payEachPlayer:
        for (final other in players.where((x) => !x.bankrupt && x.id != id)) {
          charge(id, e.amount, to: other.id);
        }
      case CardEffectType.collectFromEachPlayer:
        // Each player pays what cash they have, up to the amount.
        for (final other in players.where((x) => !x.bankrupt && x.id != id)) {
          transfer(other.id, id, min(other.cash, e.amount));
        }
      case CardEffectType.moveTo:
        moveTo(id, e.target);
      case CardEffectType.moveBack:
        moveBack(id, e.target);
      case CardEffectType.goToJail:
        sendToJail(id);
      case CardEffectType.repairs:
        var cost = 0;
        for (final o in ownership.where((o) => o.ownerId == id)) {
          cost += o.hasHotel ? e.perHotel : o.houses * e.perHouse;
        }
        if (cost > 0) charge(id, cost, fine: true);
      case CardEffectType.getOutOfJail:
        break;
    }
  }

  void returnCardToDeck(String cardId) {
    final card = s.card(cardId);
    (card.deck == Deck.vaaippu ? vaaippu : undiyal).add(cardId);
  }

  // ---------------------------------------------------------------- phases

  /// Picks the phase after a resolution step.
  void settlePhase() {
    if (phase == GamePhase.gameOver) return;
    if (auction != null) {
      phase = GamePhase.auction;
    } else if (debts.isNotEmpty) {
      phase = GamePhase.raiseCash;
    } else if (_offerBuy) {
      phase = GamePhase.awaitingBuy;
    } else {
      phase = GamePhase.manage;
    }
  }

  void advanceTurn() {
    final prev = current;
    if (prev != null && find(prev) != null) {
      update(prev, (x) => x.copyWith(doublesInRow: 0));
    }
    final active = players.where((x) => !x.bankrupt).toList();
    if (active.length <= 1) {
      endGame(active.isEmpty ? null : active.first.id, 'last player standing');
      return;
    }
    final start = players.indexWhere((x) => x.id == prev);
    for (var i = 1; i <= players.length; i++) {
      final next = players[(start + i) % players.length];
      if (!next.bankrupt) {
        current = next.id;
        break;
      }
    }
    turnNumber++;
    rollAgain = false;
    debts.clear();
    phase = GamePhase.awaitingRoll;
    final limit = rules.maxTurns;
    if (limit != null && turnNumber > limit) {
      endByNetWorth('turn limit reached');
      return;
    }
    log('turn', "It is ${name(current)}'s turn", playerId: current);
  }

  void endByNetWorth(String why) {
    final snapshot = freezeView();
    final ranking = snapshot.ranking;
    endGame(ranking.isEmpty ? null : ranking.first, why);
  }

  /// A frozen view without bumping events (for queries).
  GameState freezeView() => GameState(
        roomId: s.roomId,
        players: players,
        tiles: s.tiles,
        cards: s.cards,
        ownership: ownership,
        bank: bank,
        decks: s.decks,
        config: s.config,
        rules: rules,
      );

  void endGame(String? winner, String why) {
    winnerId = winner;
    phase = GamePhase.gameOver;
    auction = null;
    debts.clear();
    rollAgain = false;
    log('game_over', '${winner == null ? 'Nobody' : name(winner)} wins ($why)',
        playerId: winner, data: {'reason': why});
  }

  // ---------------------------------------------------------------- run

  ErrorCode? run(GameAction a) {
    try {
      _dispatch(a);
      return null;
    } on _Reject catch (r) {
      return r.code;
    }
  }

  static const _managePhases = {
    GamePhase.awaitingRoll,
    GamePhase.awaitingBuy,
    GamePhase.manage,
    GamePhase.raiseCash,
  };

  void _dispatch(GameAction a) {
    if (phase == GamePhase.gameOver && a is! SetConnected) {
      _fail(ErrorCode.illegalPhase);
    }
    switch (a) {
      case JoinGame():
        _join(a.playerId, a.name, a.token, bot: null);
      case AddBot():
        requireHost(a.playerId);
        _join(a.botId, a.name, a.token, bot: a.level);
      case LeaveGame():
        _leave(a.playerId);
      case SetReady():
        requirePhase({GamePhase.lobby});
        update(a.playerId, (x) => x.copyWith(ready: a.ready));
      case SetRules():
        requirePhase({GamePhase.lobby});
        requireHost(a.playerId);
        if (a.rules.startingCash <= 0 || a.rules.turnTimerSec < 0) {
          _fail(ErrorCode.invalidAction);
        }
        rules = a.rules;
        log('rules', 'House rules updated', playerId: a.playerId);
      case Kick():
        requirePhase({GamePhase.lobby});
        requireHost(a.playerId);
        if (a.targetId == a.playerId) _fail(ErrorCode.invalidAction);
        final t = p(a.targetId);
        players.removeWhere((x) => x.id == t.id);
        log('kicked', '${t.name} was removed from the room', playerId: t.id);
      case StartGame():
        _start(a);
      case Roll():
        _roll(a);
      case Buy():
        _buy(a.playerId);
      case DeclineBuy():
        _decline(a);
      case Bid():
        _bid(a);
      case CloseAuction():
        _closeAuction();
      case PayJailFine():
        _payJail(a.playerId);
      case UseJailCard():
        _useJailCard(a.playerId);
      case EndTurn():
        requireCurrent(a.playerId);
        requirePhase({GamePhase.manage});
        if (rollAgain) _fail(ErrorCode.illegalPhase);
        advanceTurn();
      case PayDebt():
        requireCurrent(a.playerId);
        requirePhase({GamePhase.raiseCash});
        final total = debts.fold(0, (s, d) => s + d.amount);
        if (p(a.playerId).cash < total) _fail(ErrorCode.insufficientFunds);
        for (final debt in debts) {
          settle(a.playerId, debt);
        }
        debts.clear();
        log('debt_paid', '${name(a.playerId)} paid ${formatRupees(total)} owed',
            playerId: a.playerId, data: {'amount': total});
        phase = GamePhase.manage;
      case DeclareBankruptcy():
        requireCurrent(a.playerId);
        requirePhase({GamePhase.raiseCash});
        final total = debts.fold(0, (s, d) => s + d.amount);
        if (p(a.playerId).cash >= total) _fail(ErrorCode.invalidAction);
        final creditors = debts.map((d) => d.creditorId).toSet();
        final creditor = creditors.length == 1 ? creditors.first : null;
        _bankrupt(a.playerId, creditor);
      case Build():
        _build(a.playerId, a.tileIndex);
      case SellBuilding():
        _sell(a.playerId, a.tileIndex);
      case Mortgage():
        _mortgage(a.playerId, a.tileIndex);
      case Unmortgage():
        _unmortgage(a.playerId, a.tileIndex);
      case ProposeTrade():
        _propose(a.playerId, a.to, a.give, a.get);
      case AcceptTrade():
        _accept(a.playerId, a.tradeId);
      case RejectTrade():
        final t = _trade(a.tradeId);
        if (t.to != a.playerId) _fail(ErrorCode.notOwner);
        trades.remove(t);
        log('trade_rejected',
            '${name(t.to)} rejected the trade from ${name(t.from)}',
            playerId: t.to, data: {'trade': t.id});
      case CancelTrade():
        final t = _trade(a.tradeId);
        if (t.from != a.playerId) _fail(ErrorCode.notOwner);
        trades.remove(t);
        log('trade_cancelled', '${name(t.from)} withdrew a trade offer',
            playerId: t.from, data: {'trade': t.id});
      case CounterTrade():
        final t = _trade(a.tradeId);
        if (t.to != a.playerId) _fail(ErrorCode.notOwner);
        trades.remove(t);
        _propose(a.playerId, t.from, a.give, a.get, counterOf: t.id);
      case SetConnected():
        final pl = p(a.playerId);
        if (pl.connected == a.connected) _fail(ErrorCode.invalidAction);
        put(pl.copyWith(connected: a.connected));
        if (!a.connected) {
          trades.removeWhere((t) => t.from == pl.id || t.to == pl.id);
        }
        log(a.connected ? 'reconnected' : 'disconnected',
            '${pl.name} ${a.connected ? 'reconnected' : 'disconnected'}',
            playerId: pl.id);
      case ReplaceWithBot():
        final pl = p(a.playerId);
        put(pl.copyWith(isBot: true, botLevel: a.level, connected: true));
        log('bot_seat', '${pl.name} is now played by a bot', playerId: pl.id);
      case EndGameByLimit():
        if (phase == GamePhase.lobby) _fail(ErrorCode.illegalPhase);
        endByNetWorth('time limit reached');
    }
  }

  // ---------------------------------------------------------------- lobby

  void _join(String id, String nick, Token token, {required BotLevel? bot}) {
    requirePhase({GamePhase.lobby});
    if (find(id) != null) _fail(ErrorCode.invalidAction);
    if (players.length >= config.maxPlayers) _fail(ErrorCode.roomFull);
    if (nick.trim().isEmpty || nick.length > 20) _fail(ErrorCode.invalidAction);
    players.add(Player(
      id: id,
      name: nick.trim(),
      token: token,
      isBot: bot != null,
      botLevel: bot,
      ready: bot != null,
    ));
    hostId ??= bot == null ? id : null;
    log('joined',
        '${nick.trim()} joined${bot != null ? ' (${bot.name} bot)' : ''}',
        playerId: id);
  }

  void _leave(String id) {
    final pl = p(id);
    if (phase == GamePhase.lobby) {
      players.removeWhere((x) => x.id == id);
      if (hostId == id) {
        final humans = players.where((x) => !x.isBot);
        hostId = humans.isEmpty ? null : humans.first.id;
      }
      log('left', '${pl.name} left the room', playerId: id);
      return;
    }
    if (pl.bankrupt) _fail(ErrorCode.illegalPhase);
    if (phase == GamePhase.auction) _fail(ErrorCode.illegalPhase);
    log('left', '${pl.name} left the game', playerId: id);
    final wasCurrent = current == id;
    if (wasCurrent) debts.clear();
    _bankrupt(id, null, advance: wasCurrent);
  }

  void _start(StartGame a) {
    requirePhase({GamePhase.lobby});
    requireHost(a.playerId);
    final readyCount =
        players.where((x) => x.ready || x.isBot || x.id == hostId).length;
    if (players.length < 2 || readyCount < 2) _fail(ErrorCode.illegalPhase);

    final order = [...players];
    final joinIndex = {for (var i = 0; i < order.length; i++) order[i].id: i};
    order.sort((x, y) {
      final byRoll =
          (a.openingRolls[y.id] ?? 0).compareTo(a.openingRolls[x.id] ?? 0);
      return byRoll != 0
          ? byRoll
          : joinIndex[x.id]!.compareTo(joinIndex[y.id]!);
    });
    players
      ..clear()
      ..addAll(order.map((x) => x.copyWith(
            cash: rules.startingCash,
            position: 0,
            inJail: false,
            jailTurns: 0,
            getOutCards: const [],
            doublesInRow: 0,
            bankrupt: false,
          )));

    final rng = Random(a.seed);
    final v = s.cards
        .where((c) => c.deck == Deck.vaaippu)
        .map((c) => c.id)
        .toList()
      ..shuffle(rng);
    final u = s.cards
        .where((c) => c.deck == Deck.undiyal)
        .map((c) => c.id)
        .toList()
      ..shuffle(rng);
    vaaippu
      ..clear()
      ..addAll(v);
    undiyal
      ..clear()
      ..addAll(u);

    ownership.clear();
    bank = Bank(
        cash: config.bankCash, houses: config.houses, hotels: config.hotels);
    pot = 0;
    trades.clear();
    debts.clear();
    auction = null;

    if (rules.quickGame) {
      final cities = tiles.where((t) => t.type == TileType.city).toList()
        ..shuffle(rng);
      var k = 0;
      for (final pl in players) {
        for (var n = 0; n < 2 && k < cities.length; n++) {
          ownership
              .add(Ownership(tileIndex: cities[k++].index, ownerId: pl.id));
        }
      }
    }

    startingTotal = players.fold(0, (sum, x) => sum + x.cash) + bank.cash + pot;
    current = players.first.id;
    turnNumber = 1;
    rollAgain = false;
    lastDice = const [];
    phase = GamePhase.awaitingRoll;
    log('started',
        'Game started. Order: ${players.map((x) => x.name).join(', ')}',
        data: {
          'order': [for (final x in players) x.id],
          'openingRolls': a.openingRolls,
        });
    log('turn', "It is ${name(current)}'s turn", playerId: current);
  }

  // ---------------------------------------------------------------- turn

  void _roll(Roll a) {
    requireCurrent(a.playerId);
    if (!(phase == GamePhase.awaitingRoll ||
        (phase == GamePhase.manage && rollAgain))) {
      _fail(ErrorCode.illegalPhase);
    }
    if (!a.hasDice || a.d1 < 1 || a.d1 > 6 || a.d2 < 1 || a.d2 > 6) {
      _fail(ErrorCode.invalidAction);
    }
    final id = a.playerId;
    final isDouble = a.d1 == a.d2;
    final total = a.d1 + a.d2;
    lastDice = [a.d1, a.d2];
    log('rolled',
        '${name(id)} rolled ${a.d1} + ${a.d2} = $total${isDouble ? ' (doubles)' : ''}',
        playerId: id, data: {'d1': a.d1, 'd2': a.d2});
    final pl = p(id);
    rollAgain = false;
    if (pl.inJail) {
      if (isDouble) {
        update(id, (x) => x.copyWith(inJail: false, jailTurns: 0));
        log('jail_free', '${pl.name} rolled doubles and left Jail',
            playerId: id);
        moveBy(id, total);
      } else if (pl.jailTurns + 1 >= 3) {
        update(id, (x) => x.copyWith(inJail: false, jailTurns: 0));
        log('jail_fine',
            '${pl.name} paid the ${formatRupees(config.jailFine)} fine after three tries',
            playerId: id, data: {'amount': config.jailFine});
        charge(id, config.jailFine, fine: true);
        moveBy(id, total);
      } else {
        update(id, (x) => x.copyWith(jailTurns: x.jailTurns + 1));
        log('jail_stay', '${pl.name} stays in Jail', playerId: id);
      }
    } else {
      final doubles = isDouble ? pl.doublesInRow + 1 : 0;
      update(id, (x) => x.copyWith(doublesInRow: doubles));
      if (doubles >= 3) {
        log('speeding', '${pl.name} rolled doubles three times in a row',
            playerId: id);
        sendToJail(id);
      } else {
        moveBy(id, total);
        // Being jailed on landing cancels the extra roll.
        rollAgain = isDouble && !p(id).inJail;
      }
    }
    settlePhase();
  }

  void _buy(String id) {
    requireCurrent(id);
    requirePhase({GamePhase.awaitingBuy});
    final pl = p(id);
    final tile = tiles[pl.position];
    if (!tile.isOwnable || own(tile.index) != null) {
      _fail(ErrorCode.invalidAction);
    }
    if (pl.cash < tile.price) _fail(ErrorCode.insufficientFunds);
    paysBank(id, tile.price);
    putOwn(Ownership(tileIndex: tile.index, ownerId: id));
    log('bought',
        '${pl.name} bought ${tile.name} for ${formatRupees(tile.price)}',
        playerId: id, data: {'tile': tile.index, 'amount': tile.price});
    phase = GamePhase.manage;
  }

  void _decline(DeclineBuy a) {
    requireCurrent(a.playerId);
    requirePhase({GamePhase.awaitingBuy});
    final tile = tiles[p(a.playerId).position];
    log('declined', '${name(a.playerId)} did not buy ${tile.name}',
        playerId: a.playerId, data: {'tile': tile.index});
    if (rules.auctions) {
      auction = Auction(
          tileIndex: tile.index,
          minStep: config.auctionMinStep,
          endsAt: a.endsAt);
      phase = GamePhase.auction;
      log('auction', '${tile.name} is up for auction',
          data: {'tile': tile.index});
    } else {
      phase = GamePhase.manage;
    }
  }

  void _bid(Bid a) {
    requirePhase({GamePhase.auction});
    final pl = requireActive(a.playerId);
    final auc = auction!;
    final minBid = auc.highBid == 0 ? auc.minStep : auc.highBid + auc.minStep;
    if (a.amount < minBid) _fail(ErrorCode.invalidAction);
    if (a.amount > pl.cash) _fail(ErrorCode.insufficientFunds);
    auction = auc.copyWith(
      bids: {...auc.bids, a.playerId: a.amount},
      endsAt: a.endsAt ?? auc.endsAt,
    );
    log('bid', '${pl.name} bid ${formatRupees(a.amount)}',
        playerId: pl.id, data: {'amount': a.amount});
  }

  void _closeAuction() {
    requirePhase({GamePhase.auction});
    final auc = auction!;
    final tile = tiles[auc.tileIndex];
    final winner = auc.highBidder;
    auction = null;
    if (winner != null &&
        !p(winner).bankrupt &&
        p(winner).cash >= auc.highBid) {
      paysBank(winner, auc.highBid);
      putOwn(Ownership(tileIndex: tile.index, ownerId: winner));
      log('auction_won',
          '${name(winner)} won ${tile.name} for ${formatRupees(auc.highBid)}',
          playerId: winner, data: {'tile': tile.index, 'amount': auc.highBid});
    } else {
      log('auction_none', 'Nobody bought ${tile.name}; it stays with the bank',
          data: {'tile': tile.index});
    }
    phase = GamePhase.manage;
  }

  void _payJail(String id) {
    requireCurrent(id);
    requirePhase({GamePhase.awaitingRoll});
    final pl = p(id);
    if (!pl.inJail) _fail(ErrorCode.invalidAction);
    if (pl.cash < config.jailFine) _fail(ErrorCode.insufficientFunds);
    if (rules.freeParkingPot) {
      update(id, (x) => x.copyWith(cash: x.cash - config.jailFine));
      pot += config.jailFine;
    } else {
      paysBank(id, config.jailFine);
    }
    update(id, (x) => x.copyWith(inJail: false, jailTurns: 0));
    log('jail_paid',
        '${pl.name} paid ${formatRupees(config.jailFine)} to leave Jail',
        playerId: id, data: {'amount': config.jailFine});
  }

  void _useJailCard(String id) {
    requireCurrent(id);
    requirePhase({GamePhase.awaitingRoll});
    final pl = p(id);
    if (!pl.inJail || pl.getOutCards.isEmpty) _fail(ErrorCode.invalidAction);
    final cardId = pl.getOutCards.first;
    update(
        id,
        (x) => x.copyWith(
            inJail: false,
            jailTurns: 0,
            getOutCards: x.getOutCards.sublist(1)));
    returnCardToDeck(cardId);
    log('jail_card', '${pl.name} used a get-out-of-jail card', playerId: id);
  }

  // ---------------------------------------------------------------- property

  Ownership _owned(String id, int index) {
    if (index < 0 || index >= tiles.length) _fail(ErrorCode.invalidAction);
    final o = own(index);
    if (o == null || o.ownerId != id) _fail(ErrorCode.notOwner);
    return o;
  }

  void _build(String id, int index) {
    requirePhase(_managePhases);
    final pl = requireActive(id);
    final o = _owned(id, index);
    final tile = tiles[index];
    if (tile.type != TileType.city) _fail(ErrorCode.invalidAction);
    if (!ownsGroup(id, tile.group!)) _fail(ErrorCode.incompleteSet);
    final group = groupTiles(tile.group!).map((t) => own(t.index)!).toList();
    if (group.any((g) => g.mortgaged)) _fail(ErrorCode.mortgaged);
    if (o.houses >= 5) _fail(ErrorCode.invalidAction);
    final minHouses = group.map((g) => g.houses).reduce(min);
    if (o.houses != minHouses) _fail(ErrorCode.unevenBuild);
    if (o.houses == 4) {
      if (bank.hotels < 1) _fail(ErrorCode.noHotelsLeft);
    } else if (bank.houses < 1) {
      _fail(ErrorCode.noHousesLeft);
    }
    if (pl.cash < tile.houseCost) _fail(ErrorCode.insufficientFunds);
    paysBank(id, tile.houseCost);
    if (o.houses == 4) {
      bank = bank.copyWith(hotels: bank.hotels - 1, houses: bank.houses + 4);
    } else {
      bank = bank.copyWith(houses: bank.houses - 1);
    }
    putOwn(o.copyWith(houses: o.houses + 1));
    log('built',
        '${pl.name} built a ${o.houses == 4 ? 'hotel' : 'house'} on ${tile.name}',
        playerId: id, data: {'tile': index, 'houses': o.houses + 1});
  }

  void _sell(String id, int index) {
    requirePhase(_managePhases);
    final pl = requireActive(id);
    final o = _owned(id, index);
    final tile = tiles[index];
    if (o.houses == 0) _fail(ErrorCode.invalidAction);
    final group = groupTiles(tile.group!).map((t) => own(t.index)!).toList();
    final maxHouses = group.map((g) => g.houses).reduce(max);
    if (o.houses != maxHouses) _fail(ErrorCode.unevenBuild);
    if (o.hasHotel) {
      if (bank.houses < 4) _fail(ErrorCode.noHousesLeft);
      bank = bank.copyWith(hotels: bank.hotels + 1, houses: bank.houses - 4);
    } else {
      bank = bank.copyWith(houses: bank.houses + 1);
    }
    bankPays(id, tile.houseCost ~/ 2);
    putOwn(o.copyWith(houses: o.houses - 1));
    log('sold_building',
        '${pl.name} sold a ${o.hasHotel ? 'hotel' : 'house'} on ${tile.name} for ${formatRupees(tile.houseCost ~/ 2)}',
        playerId: id, data: {'tile': index, 'houses': o.houses - 1});
  }

  void _mortgage(String id, int index) {
    requirePhase(_managePhases);
    final pl = requireActive(id);
    final o = _owned(id, index);
    final tile = tiles[index];
    if (o.mortgaged) _fail(ErrorCode.mortgaged);
    if (tile.type == TileType.city &&
        groupTiles(tile.group!).any((t) => (own(t.index)?.houses ?? 0) > 0)) {
      _fail(ErrorCode.hasBuildings);
    }
    putOwn(o.copyWith(mortgaged: true));
    bankPays(id, tile.mortgageValue);
    log('mortgaged',
        '${pl.name} mortgaged ${tile.name} for ${formatRupees(tile.mortgageValue)}',
        playerId: id, data: {'tile': index, 'amount': tile.mortgageValue});
  }

  void _unmortgage(String id, int index) {
    requirePhase(_managePhases);
    final pl = requireActive(id);
    final o = _owned(id, index);
    final tile = tiles[index];
    if (!o.mortgaged) _fail(ErrorCode.invalidAction);
    final cost = freezeView().unmortgageCost(tile);
    if (pl.cash < cost) _fail(ErrorCode.insufficientFunds);
    paysBank(id, cost);
    putOwn(o.copyWith(mortgaged: false));
    log('unmortgaged',
        '${pl.name} unmortgaged ${tile.name} for ${formatRupees(cost)}',
        playerId: id, data: {'tile': index, 'amount': cost});
  }

  // ---------------------------------------------------------------- trades

  Trade _trade(String id) {
    for (final t in trades) {
      if (t.id == id && t.status == TradeStatus.pending) return t;
    }
    _fail(ErrorCode.notFound);
  }

  /// Checks a trade against the current draft; returns whether valid.
  bool _tradeValid(String from, String to, TradeSide give, TradeSide get) {
    final a = find(from);
    final b = find(to);
    if (a == null || b == null || a.id == b.id) return false;
    if (a.bankrupt || b.bankrupt || !a.connected || !b.connected) return false;
    if (give.isEmpty && get.isEmpty) return false;
    if (give.cash < 0 || get.cash < 0 || give.cards < 0 || get.cards < 0) {
      return false;
    }
    if (a.cash < give.cash || b.cash < get.cash) return false;
    if (a.getOutCards.length < give.cards || b.getOutCards.length < get.cards) {
      return false;
    }
    bool ownsAll(String who, List<int> list) =>
        list.toSet().length == list.length &&
        list.every((i) => i >= 0 && i < tiles.length && own(i)?.ownerId == who);
    if (!ownsAll(from, give.tiles) || !ownsAll(to, get.tiles)) return false;
    for (final i in [...give.tiles, ...get.tiles]) {
      final g = tiles[i].group;
      if (tiles[i].type == TileType.city &&
          groupTiles(g!).any((t) => (own(t.index)?.houses ?? 0) > 0)) {
        return false;
      }
    }
    return true;
  }

  void _propose(String from, String to, TradeSide give, TradeSide get,
      {String? counterOf}) {
    if (phase == GamePhase.lobby) _fail(ErrorCode.illegalPhase);
    if (!_tradeValid(from, to, give, get)) _fail(ErrorCode.tradeInvalid);
    final t = Trade(
      id: 't${nextTradeId++}',
      from: from,
      to: to,
      give: give,
      get: get,
      createdAtVersion: s.version + 1,
    );
    trades.add(t);
    log(counterOf == null ? 'trade_proposed' : 'trade_countered',
        '${name(from)} ${counterOf == null ? 'offered' : 'countered with'} a trade to ${name(to)}',
        playerId: from,
        data: {'trade': t.id, if (counterOf != null) 'counterOf': counterOf});
  }

  void _accept(String id, String tradeId) {
    final t = _trade(tradeId);
    if (t.to != id) _fail(ErrorCode.notOwner);
    if (phase == GamePhase.auction) _fail(ErrorCode.illegalPhase);
    if (!_tradeValid(t.from, t.to, t.give, t.get)) {
      _fail(ErrorCode.tradeInvalid);
    }
    transfer(t.from, t.to, t.give.cash);
    transfer(t.to, t.from, t.get.cash);
    for (final i in t.give.tiles) {
      putOwn(own(i)!.copyWith(ownerId: t.to));
    }
    for (final i in t.get.tiles) {
      putOwn(own(i)!.copyWith(ownerId: t.from));
    }
    void moveCards(String a, String b, int n) {
      if (n == 0) return;
      final cards = p(a).getOutCards;
      update(a, (x) => x.copyWith(getOutCards: cards.sublist(n)));
      update(b,
          (x) => x.copyWith(getOutCards: [...x.getOutCards, ...cards.take(n)]));
    }

    moveCards(t.from, t.to, t.give.cards);
    moveCards(t.to, t.from, t.get.cards);
    trades.remove(t);
    log('trade_accepted', '${name(t.to)} accepted a trade with ${name(t.from)}',
        playerId: t.to, data: {'trade': t.id, 'from': t.from, 'to': t.to});
  }

  // ---------------------------------------------------------------- bankruptcy

  /// Hands everything of [id] to [creditor] (or the bank) and removes them.
  void _bankrupt(String id, String? creditor, {bool advance = true}) {
    final pl = p(id);
    // Sell all buildings back to the bank at half cost.
    for (final o in ownership.where((o) => o.ownerId == id).toList()) {
      if (o.houses > 0) {
        final tile = tiles[o.tileIndex];
        bankPays(id, (tile.houseCost ~/ 2) * o.houses);
        bank = o.hasHotel
            ? bank.copyWith(hotels: bank.hotels + 1)
            : bank.copyWith(houses: bank.houses + o.houses);
        putOwn(o.copyWith(houses: 0));
      }
    }
    final cash = p(id).cash;
    if (creditor != null) {
      transfer(id, creditor, cash);
      for (final o in ownership.where((o) => o.ownerId == id).toList()) {
        putOwn(o.copyWith(ownerId: creditor));
      }
      update(
          creditor,
          (x) => x
              .copyWith(getOutCards: [...x.getOutCards, ...p(id).getOutCards]));
    } else {
      paysBank(id, cash);
      ownership.removeWhere((o) => o.ownerId == id);
      for (final c in p(id).getOutCards) {
        returnCardToDeck(c);
      }
    }
    update(
        id,
        (x) => x.copyWith(
            bankrupt: true, cash: 0, getOutCards: const [], inJail: false));
    trades.removeWhere((t) => t.from == id || t.to == id);
    if (auction != null) {
      final bids = Map<String, int>.from(auction!.bids)..remove(id);
      auction = auction!.copyWith(bids: bids);
    }
    log('bankrupt',
        '${pl.name} is bankrupt; assets go to ${creditor == null ? 'the bank' : name(creditor)}',
        playerId: id, data: {'creditor': creditor});
    if (current == id) debts.clear();
    if (advance) {
      advanceTurn();
    } else if (players.where((x) => !x.bankrupt).length <= 1) {
      final last = players.where((x) => !x.bankrupt);
      endGame(last.isEmpty ? null : last.first.id, 'last player standing');
    }
  }
}
