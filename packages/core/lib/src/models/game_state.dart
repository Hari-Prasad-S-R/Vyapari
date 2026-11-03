import '../json_equality.dart';
import 'card.dart';
import 'misc.dart';
import 'player.dart';
import 'rules.dart';
import 'tile.dart';

/// Turn phase (see `design.md` §6).
enum GamePhase {
  /// Players joining, host setting rules.
  lobby,

  /// Current player must roll (or use jail options).
  awaitingRoll,

  /// Current player landed on an unowned property: buy or decline.
  awaitingBuy,

  /// A property is being auctioned.
  auction,

  /// Current player may build, mortgage, trade, then roll again or end turn.
  manage,

  /// Current player owes more than their cash.
  raiseCash,

  /// The game has finished.
  gameOver,
}

const _unset = Object();

/// The whole game as one immutable value.
class GameState with JsonEquality {
  /// Creates a state.
  GameState({
    required this.roomId,
    this.version = 0,
    this.phase = GamePhase.lobby,
    List<Player> players = const [],
    required List<Tile> tiles,
    required List<GameCard> cards,
    List<Ownership> ownership = const [],
    this.currentPlayer,
    this.hostId,
    required this.bank,
    required this.decks,
    this.freeParkingPot = 0,
    this.rules = const HouseRules(),
    this.config = const GameConfig(),
    List<GameEvent> log = const [],
    this.auction,
    List<Trade> trades = const [],
    List<Debt> debts = const [],
    List<int> auctionQueue = const [],
    this.resumePhase,
    this.rollAgain = false,
    List<int> lastDice = const [],
    this.turnNumber = 0,
    this.winnerId,
    this.startingTotal = 0,
    this.nextTradeId = 1,
  })  : players = List.unmodifiable(players),
        tiles = List.unmodifiable(tiles),
        cards = List.unmodifiable(cards),
        ownership = List.unmodifiable(ownership),
        log = List.unmodifiable(log),
        trades = List.unmodifiable(trades),
        debts = List.unmodifiable(debts),
        auctionQueue = List.unmodifiable(auctionQueue),
        lastDice = List.unmodifiable(lastDice);

  /// Room code.
  final String roomId;

  /// Increments on every accepted action.
  final int version;

  /// Current phase.
  final GamePhase phase;

  /// Players in turn order (join order while in the lobby).
  final List<Player> players;

  /// Static board tiles.
  final List<Tile> tiles;

  /// All cards of both decks.
  final List<GameCard> cards;

  /// Owned tiles only.
  final List<Ownership> ownership;

  /// Id of the player whose turn it is.
  final String? currentPlayer;

  /// Host player id.
  final String? hostId;

  /// Bank cash and buildings.
  final Bank bank;

  /// Deck draw orders.
  final Decks decks;

  /// Free Parking pot.
  final int freeParkingPot;

  /// House rules.
  final HouseRules rules;

  /// Board constants.
  final GameConfig config;

  /// Recent events, oldest first (capped).
  final List<GameEvent> log;

  /// Running auction, if any.
  final Auction? auction;

  /// Pending trades.
  final List<Trade> trades;

  /// Unpaid debts, settled one debtor at a time in list order.
  final List<Debt> debts;

  /// Tiles of a player bankrupt to the bank, waiting to be auctioned.
  final List<int> auctionQueue;

  /// Phase to return to when the bank's auctions finish.
  final GamePhase? resumePhase;

  /// Whether the current player rolled doubles and must roll again.
  final bool rollAgain;

  /// Last dice rolled.
  final List<int> lastDice;

  /// Turns played so far.
  final int turnNumber;

  /// Winner when the game is over.
  final String? winnerId;

  /// Total money at game start (players + bank + pot).
  final int startingTotal;

  /// Counter for trade ids.
  final int nextTradeId;

  /// Finds a player by id.
  Player? player(String? id) {
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Ownership of a tile, if owned.
  Ownership? ownershipOf(int tileIndex) {
    for (final o in ownership) {
      if (o.tileIndex == tileIndex) return o;
    }
    return null;
  }

  /// Players still in the game.
  List<Player> get activePlayers => players.where((p) => !p.bankrupt).toList();

  /// Total money in the system.
  int get totalMoney =>
      players.fold(0, (sum, p) => sum + p.cash) + bank.cash + freeParkingPot;

  /// Card by id.
  GameCard card(String id) => cards.firstWhere((c) => c.id == id);

  GameState._raw({
    required this.roomId,
    required this.version,
    required this.phase,
    required this.players,
    required this.tiles,
    required this.cards,
    required this.ownership,
    required this.currentPlayer,
    required this.hostId,
    required this.bank,
    required this.decks,
    required this.freeParkingPot,
    required this.rules,
    required this.config,
    required this.log,
    required this.auction,
    required this.trades,
    required this.debts,
    required this.auctionQueue,
    required this.resumePhase,
    required this.rollAgain,
    required this.lastDice,
    required this.turnNumber,
    required this.winnerId,
    required this.startingTotal,
    required this.nextTradeId,
  });

  /// Copy with changes. Unchanged lists are shared, not copied.
  GameState copyWith({
    int? version,
    GamePhase? phase,
    List<Player>? players,
    List<Ownership>? ownership,
    Object? currentPlayer = _unset,
    Object? hostId = _unset,
    Bank? bank,
    Decks? decks,
    int? freeParkingPot,
    HouseRules? rules,
    List<GameEvent>? log,
    Object? auction = _unset,
    List<Trade>? trades,
    List<Debt>? debts,
    List<int>? auctionQueue,
    Object? resumePhase = _unset,
    bool? rollAgain,
    List<int>? lastDice,
    int? turnNumber,
    Object? winnerId = _unset,
    int? startingTotal,
    int? nextTradeId,
  }) =>
      GameState._raw(
        roomId: roomId,
        version: version ?? this.version,
        phase: phase ?? this.phase,
        players: players == null ? this.players : List.unmodifiable(players),
        tiles: tiles,
        cards: cards,
        ownership:
            ownership == null ? this.ownership : List.unmodifiable(ownership),
        currentPlayer: identical(currentPlayer, _unset)
            ? this.currentPlayer
            : currentPlayer as String?,
        hostId: identical(hostId, _unset) ? this.hostId : hostId as String?,
        bank: bank ?? this.bank,
        decks: decks ?? this.decks,
        freeParkingPot: freeParkingPot ?? this.freeParkingPot,
        rules: rules ?? this.rules,
        config: config,
        log: log == null ? this.log : List.unmodifiable(log),
        auction:
            identical(auction, _unset) ? this.auction : auction as Auction?,
        trades: trades == null ? this.trades : List.unmodifiable(trades),
        debts: debts == null ? this.debts : List.unmodifiable(debts),
        auctionQueue: auctionQueue == null
            ? this.auctionQueue
            : List.unmodifiable(auctionQueue),
        resumePhase: identical(resumePhase, _unset)
            ? this.resumePhase
            : resumePhase as GamePhase?,
        rollAgain: rollAgain ?? this.rollAgain,
        lastDice:
            lastDice == null ? this.lastDice : List.unmodifiable(lastDice),
        turnNumber: turnNumber ?? this.turnNumber,
        winnerId:
            identical(winnerId, _unset) ? this.winnerId : winnerId as String?,
        startingTotal: startingTotal ?? this.startingTotal,
        nextTradeId: nextTradeId ?? this.nextTradeId,
      );

  @override
  Map<String, Object?> toJson() => {
        'roomId': roomId,
        'version': version,
        'phase': phase.name,
        'players': [for (final p in players) p.toJson()],
        'tiles': [for (final t in tiles) t.toJson()],
        'cards': [for (final c in cards) c.toJson()],
        'ownership': [for (final o in ownership) o.toJson()],
        'currentPlayer': currentPlayer,
        'hostId': hostId,
        'bank': bank.toJson(),
        'decks': decks.toJson(),
        'freeParkingPot': freeParkingPot,
        'rules': rules.toJson(),
        'config': config.toJson(),
        'log': [for (final e in log) e.toJson()],
        'auction': auction?.toJson(),
        'trades': [for (final t in trades) t.toJson()],
        'debts': [for (final d in debts) d.toJson()],
        'auctionQueue': auctionQueue,
        'resumePhase': resumePhase?.name,
        'rollAgain': rollAgain,
        'lastDice': lastDice,
        'turnNumber': turnNumber,
        'winnerId': winnerId,
        'startingTotal': startingTotal,
        'nextTradeId': nextTradeId,
      };

  /// Decodes a state.
  factory GameState.fromJson(Map<String, Object?> json) => GameState(
        roomId: json['roomId'] as String,
        version: readInt(json, 'version'),
        phase: GamePhase.values.byName(json['phase'] as String),
        players: readMapList(json['players']).map(Player.fromJson).toList(),
        tiles: readMapList(json['tiles']).map(Tile.fromJson).toList(),
        cards: readMapList(json['cards']).map(GameCard.fromJson).toList(),
        ownership:
            readMapList(json['ownership']).map(Ownership.fromJson).toList(),
        currentPlayer: json['currentPlayer'] as String?,
        hostId: json['hostId'] as String?,
        bank: Bank.fromJson(readMap(json['bank'])),
        decks: Decks.fromJson(readMap(json['decks'])),
        freeParkingPot: readIntOr(json, 'freeParkingPot', 0),
        rules: HouseRules.fromJson(readMap(json['rules'])),
        config: GameConfig.fromJson(readMap(json['config'])),
        log: readMapList(json['log']).map(GameEvent.fromJson).toList(),
        auction: json['auction'] == null
            ? null
            : Auction.fromJson(readMap(json['auction'])),
        trades: readMapList(json['trades']).map(Trade.fromJson).toList(),
        debts: readMapList(json['debts']).map(Debt.fromJson).toList(),
        auctionQueue: readIntList(json['auctionQueue']),
        resumePhase: json['resumePhase'] == null
            ? null
            : GamePhase.values.byName(json['resumePhase'] as String),
        rollAgain: json['rollAgain'] as bool? ?? false,
        lastDice: readIntList(json['lastDice']),
        turnNumber: readIntOr(json, 'turnNumber', 0),
        winnerId: json['winnerId'] as String?,
        startingTotal: readIntOr(json, 'startingTotal', 0),
        nextTradeId: readIntOr(json, 'nextTradeId', 1),
      );
}
