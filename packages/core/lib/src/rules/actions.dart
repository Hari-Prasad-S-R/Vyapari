import '../models/misc.dart';
import '../models/player.dart';
import '../models/rules.dart';

/// Reason codes for rejected actions and protocol errors.
enum ErrorCode {
  notYourTurn,
  illegalPhase,
  insufficientFunds,
  notOwner,
  incompleteSet,
  unevenBuild,
  noHousesLeft,
  noHotelsLeft,
  mortgaged,
  hasBuildings,
  tradeInvalid,
  hostOnly,
  roomFull,
  badCode,
  badPassword,
  rateLimited,
  versionMismatch,
  unknownMessage,
  malformed,
  invalidAction,
  notFound;

  /// Wire name, e.g. `not_your_turn`.
  String get wire =>
      name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

  /// Parses a wire name; returns [unknownMessage] if not recognised.
  static ErrorCode fromWire(String wire) => ErrorCode.values.firstWhere(
        (c) => c.wire == wire,
        orElse: () => ErrorCode.unknownMessage,
      );
}

/// An action for the rules engine. Clients send intents; the server turns
/// them into actions (filling in dice and seeds) before calling `apply`.
sealed class GameAction {
  const GameAction(this.playerId);

  /// Acting player (for system actions, the affected player).
  final String playerId;

  /// Whether only the server may issue this action.
  bool get isSystem => false;
}

// ---- Lobby ----

/// A human joins the lobby.
class JoinGame extends GameAction {
  /// Creates the action.
  const JoinGame(super.playerId, {required this.name, required this.token});

  /// Nickname.
  final String name;

  /// Chosen token.
  final Token token;
}

/// A player leaves (lobby: seat removed; in game: forfeits to the bank).
class LeaveGame extends GameAction {
  /// Creates the action.
  const LeaveGame(super.playerId);
}

/// Toggle the lobby ready tick.
class SetReady extends GameAction {
  /// Creates the action.
  const SetReady(super.playerId, {required this.ready});

  /// New ready value.
  final bool ready;
}

/// Host changes house rules.
class SetRules extends GameAction {
  /// Creates the action.
  const SetRules(super.playerId, this.rules);

  /// New rules.
  final HouseRules rules;
}

/// Host adds a bot seat.
class AddBot extends GameAction {
  /// Creates the action.
  const AddBot(super.playerId,
      {required this.botId,
      required this.name,
      required this.token,
      required this.level});

  /// Id of the new bot seat.
  final String botId;

  /// Bot name.
  final String name;

  /// Bot token.
  final Token token;

  /// Difficulty.
  final BotLevel level;
}

/// Host removes a player from the lobby.
class Kick extends GameAction {
  /// Creates the action.
  const Kick(super.playerId, this.targetId);

  /// Player to remove.
  final String targetId;
}

/// Host starts the game. [seed] shuffles decks; [openingRolls] sets order.
class StartGame extends GameAction {
  /// Creates the action.
  const StartGame(super.playerId,
      {required this.seed, this.openingRolls = const {}});

  /// Server-generated seed for deck shuffles and quick-game cities.
  final int seed;

  /// Opening roll totals per player (highest goes first).
  final Map<String, int> openingRolls;
}

// ---- Turn ----

/// Roll the dice. Clients send [Roll.intent]; the server fills the dice.
class Roll extends GameAction {
  /// Creates a roll with server dice.
  const Roll(super.playerId, this.d1, this.d2);

  /// A roll request without dice (from a client or bot).
  const Roll.intent(String playerId) : this(playerId, 0, 0);

  /// First die.
  final int d1;

  /// Second die.
  final int d2;

  /// Whether the server has filled in the dice.
  bool get hasDice => d1 != 0 && d2 != 0;
}

/// Buy the tile the current player stands on.
class Buy extends GameAction {
  /// Creates the action.
  const Buy(super.playerId);
}

/// Decline to buy (starts an auction if enabled).
class DeclineBuy extends GameAction {
  /// Creates the action.
  const DeclineBuy(super.playerId, {this.endsAt});

  /// Auction deadline set by the server.
  final int? endsAt;
}

/// Bid in the running auction.
class Bid extends GameAction {
  /// Creates the action.
  const Bid(super.playerId, this.amount, {this.endsAt});

  /// Bid amount.
  final int amount;

  /// New deadline set by the server.
  final int? endsAt;
}

/// Server closes the auction when its timer runs out.
class CloseAuction extends GameAction {
  /// Creates the action.
  const CloseAuction(super.playerId);

  @override
  bool get isSystem => true;
}

/// Pay the jail fine before rolling.
class PayJailFine extends GameAction {
  /// Creates the action.
  const PayJailFine(super.playerId);
}

/// Use a get-out-of-jail card.
class UseJailCard extends GameAction {
  /// Creates the action.
  const UseJailCard(super.playerId);
}

/// End the turn.
class EndTurn extends GameAction {
  /// Creates the action.
  const EndTurn(super.playerId);
}

/// Pay all outstanding debts.
class PayDebt extends GameAction {
  /// Creates the action.
  const PayDebt(super.playerId);
}

/// Give up when debts cannot be paid.
class DeclareBankruptcy extends GameAction {
  /// Creates the action.
  const DeclareBankruptcy(super.playerId);
}

// ---- Property management ----

/// Build one house (or a hotel on four houses).
class Build extends GameAction {
  /// Creates the action.
  const Build(super.playerId, this.tileIndex);

  /// Tile to build on.
  final int tileIndex;
}

/// Sell one building back at half cost.
class SellBuilding extends GameAction {
  /// Creates the action.
  const SellBuilding(super.playerId, this.tileIndex);

  /// Tile to sell from.
  final int tileIndex;
}

/// Mortgage a tile for half its price.
class Mortgage extends GameAction {
  /// Creates the action.
  const Mortgage(super.playerId, this.tileIndex);

  /// Tile to mortgage.
  final int tileIndex;
}

/// Lift a mortgage (value + interest).
class Unmortgage extends GameAction {
  /// Creates the action.
  const Unmortgage(super.playerId, this.tileIndex);

  /// Tile to unmortgage.
  final int tileIndex;
}

// ---- Trades ----

/// Propose a trade to another player.
class ProposeTrade extends GameAction {
  /// Creates the action.
  const ProposeTrade(super.playerId,
      {required this.to, required this.give, required this.get});

  /// Receiver.
  final String to;

  /// What the proposer gives.
  final TradeSide give;

  /// What the proposer gets.
  final TradeSide get;
}

/// Receiver accepts a trade.
class AcceptTrade extends GameAction {
  /// Creates the action.
  const AcceptTrade(super.playerId, this.tradeId);

  /// Trade id.
  final String tradeId;
}

/// Receiver rejects a trade.
class RejectTrade extends GameAction {
  /// Creates the action.
  const RejectTrade(super.playerId, this.tradeId);

  /// Trade id.
  final String tradeId;
}

/// Proposer withdraws a trade.
class CancelTrade extends GameAction {
  /// Creates the action.
  const CancelTrade(super.playerId, this.tradeId);

  /// Trade id.
  final String tradeId;
}

/// Receiver answers with a different offer (sides from their view).
class CounterTrade extends GameAction {
  /// Creates the action.
  const CounterTrade(super.playerId, this.tradeId,
      {required this.give, required this.get});

  /// Trade being countered.
  final String tradeId;

  /// What the counter-proposer gives.
  final TradeSide give;

  /// What the counter-proposer gets.
  final TradeSide get;
}

// ---- System ----

/// Server marks a player connected or disconnected.
class SetConnected extends GameAction {
  /// Creates the action.
  const SetConnected(super.playerId, {required this.connected});

  /// New connection status.
  final bool connected;

  @override
  bool get isSystem => true;
}

/// Server hands a seat to a bot (e.g. rejoin window expired).
class ReplaceWithBot extends GameAction {
  /// Creates the action.
  const ReplaceWithBot(super.playerId, {this.level = BotLevel.medium});

  /// Bot level for the seat.
  final BotLevel level;

  @override
  bool get isSystem => true;
}

/// Server ends the game (time limit); highest net worth wins.
class EndGameByLimit extends GameAction {
  /// Creates the action.
  const EndGameByLimit(super.playerId);

  @override
  bool get isSystem => true;
}
