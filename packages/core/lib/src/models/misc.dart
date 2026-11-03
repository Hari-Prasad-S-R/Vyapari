import '../json_equality.dart';

const _unset = Object();

/// Mutable part of an owned tile.
class Ownership with JsonEquality {
  /// Creates an ownership record.
  const Ownership({
    required this.tileIndex,
    required this.ownerId,
    this.houses = 0,
    this.mortgaged = false,
  });

  /// Tile index.
  final int tileIndex;

  /// Owner player id.
  final String ownerId;

  /// 0–4 houses, 5 = hotel.
  final int houses;

  /// Whether the tile is mortgaged.
  final bool mortgaged;

  /// Whether a hotel stands here.
  bool get hasHotel => houses == 5;

  /// Copy with changes.
  Ownership copyWith({String? ownerId, int? houses, bool? mortgaged}) =>
      Ownership(
        tileIndex: tileIndex,
        ownerId: ownerId ?? this.ownerId,
        houses: houses ?? this.houses,
        mortgaged: mortgaged ?? this.mortgaged,
      );

  @override
  Map<String, Object?> toJson() => {
        'tileIndex': tileIndex,
        'ownerId': ownerId,
        'houses': houses,
        'mortgaged': mortgaged,
      };

  /// Decodes an ownership record.
  factory Ownership.fromJson(Map<String, Object?> json) => Ownership(
        tileIndex: readInt(json, 'tileIndex'),
        ownerId: json['ownerId'] as String,
        houses: readInt(json, 'houses'),
        mortgaged: json['mortgaged'] as bool,
      );
}

/// The bank: cash and building stock.
class Bank with JsonEquality {
  /// Creates a bank.
  const Bank({required this.cash, this.houses = 32, this.hotels = 12});

  /// Bank cash. The bank never runs out, so this may go negative; it only
  /// exists so total money can be checked for conservation.
  final int cash;

  /// Houses left.
  final int houses;

  /// Hotels left.
  final int hotels;

  /// Copy with changes.
  Bank copyWith({int? cash, int? houses, int? hotels}) => Bank(
        cash: cash ?? this.cash,
        houses: houses ?? this.houses,
        hotels: hotels ?? this.hotels,
      );

  @override
  Map<String, Object?> toJson() =>
      {'cash': cash, 'houses': houses, 'hotels': hotels};

  /// Decodes a bank.
  factory Bank.fromJson(Map<String, Object?> json) => Bank(
        cash: readInt(json, 'cash'),
        houses: readInt(json, 'houses'),
        hotels: readInt(json, 'hotels'),
      );
}

/// Draw order of both decks; the first id is the top card.
class Decks with JsonEquality {
  /// Creates decks.
  Decks({List<String> vaaippu = const [], List<String> undiyal = const []})
      : vaaippu = List.unmodifiable(vaaippu),
        undiyal = List.unmodifiable(undiyal);

  /// Vaaippu draw order.
  final List<String> vaaippu;

  /// Undiyal draw order.
  final List<String> undiyal;

  @override
  Map<String, Object?> toJson() => {'vaaippu': vaaippu, 'undiyal': undiyal};

  /// Decodes decks.
  factory Decks.fromJson(Map<String, Object?> json) => Decks(
        vaaippu: readStringList(json['vaaippu']),
        undiyal: readStringList(json['undiyal']),
      );
}

/// One side of a trade.
class TradeSide with JsonEquality {
  /// Creates a trade side.
  TradeSide({this.cash = 0, List<int> tiles = const [], this.cards = 0})
      : tiles = List.unmodifiable(tiles);

  /// Cash offered.
  final int cash;

  /// Tile indexes offered.
  final List<int> tiles;

  /// Number of get-out-of-jail cards offered.
  final int cards;

  /// Whether nothing is offered.
  bool get isEmpty => cash == 0 && tiles.isEmpty && cards == 0;

  @override
  Map<String, Object?> toJson() =>
      {'cash': cash, 'tiles': tiles, 'cards': cards};

  /// Decodes a trade side.
  factory TradeSide.fromJson(Map<String, Object?> json) => TradeSide(
        cash: readIntOr(json, 'cash', 0),
        tiles: readIntList(json['tiles']),
        cards: readIntOr(json, 'cards', 0),
      );
}

/// Trade status.
enum TradeStatus { pending, accepted, rejected, countered, cancelled }

/// A player-to-player trade offer.
class Trade with JsonEquality {
  /// Creates a trade.
  Trade({
    required this.id,
    required this.from,
    required this.to,
    required this.give,
    required this.get,
    this.status = TradeStatus.pending,
    required this.createdAtVersion,
  });

  /// Trade id.
  final String id;

  /// Proposer id.
  final String from;

  /// Receiver id.
  final String to;

  /// What the proposer gives.
  final TradeSide give;

  /// What the proposer gets.
  final TradeSide get;

  /// Status.
  final TradeStatus status;

  /// State version when proposed (or last changed).
  final int createdAtVersion;

  /// Copy with a new status.
  Trade withStatus(TradeStatus status) => Trade(
        id: id,
        from: from,
        to: to,
        give: give,
        get: get,
        status: status,
        createdAtVersion: createdAtVersion,
      );

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'give': give.toJson(),
        'get': get.toJson(),
        'status': status.name,
        'createdAtVersion': createdAtVersion,
      };

  /// Decodes a trade.
  factory Trade.fromJson(Map<String, Object?> json) => Trade(
        id: json['id'] as String,
        from: json['from'] as String,
        to: json['to'] as String,
        give: TradeSide.fromJson(readMap(json['give'])),
        get: TradeSide.fromJson(readMap(json['get'])),
        status: TradeStatus.values.byName(json['status'] as String),
        createdAtVersion: readInt(json, 'createdAtVersion'),
      );
}

/// A running auction.
class Auction with JsonEquality {
  /// Creates an auction.
  Auction({
    required this.tileIndex,
    Map<String, int> bids = const {},
    this.endsAt,
    this.minStep = 10000,
  }) : bids = Map.unmodifiable(bids);

  /// Tile being auctioned.
  final int tileIndex;

  /// Highest bid per player.
  final Map<String, int> bids;

  /// Server clock deadline in ms since epoch (set by the server; the engine
  /// never reads clocks).
  final int? endsAt;

  /// Minimum raise.
  final int minStep;

  /// Current highest bid amount (0 if none).
  int get highBid => bids.values.fold(0, (best, b) => b > best ? b : best);

  /// Player with the highest bid, earliest wins ties (map insertion order).
  String? get highBidder {
    String? who;
    var best = 0;
    bids.forEach((id, amount) {
      if (amount > best) {
        best = amount;
        who = id;
      }
    });
    return who;
  }

  /// Copy with changes.
  Auction copyWith({Map<String, int>? bids, Object? endsAt = _unset}) =>
      Auction(
        tileIndex: tileIndex,
        bids: bids ?? this.bids,
        endsAt: identical(endsAt, _unset) ? this.endsAt : endsAt as int?,
        minStep: minStep,
      );

  @override
  Map<String, Object?> toJson() => {
        'tileIndex': tileIndex,
        'bids': bids,
        if (endsAt != null) 'endsAt': endsAt,
        'minStep': minStep,
      };

  /// Decodes an auction.
  factory Auction.fromJson(Map<String, Object?> json) => Auction(
        tileIndex: readInt(json, 'tileIndex'),
        bids: readMap(json['bids']).cast<String, int>(),
        endsAt: json['endsAt'] as int?,
        minStep: readIntOr(json, 'minStep', 10000),
      );
}

/// Money a player owes but could not pay yet.
class Debt with JsonEquality {
  /// Creates a debt.
  const Debt({
    required this.debtorId,
    required this.amount,
    this.creditorId,
    this.toPot = false,
  });

  /// Player who owes.
  final String debtorId;

  /// Amount owed.
  final int amount;

  /// Creditor player id, or `null` for the bank.
  final String? creditorId;

  /// Whether the money goes to the Free Parking pot instead of the bank.
  final bool toPot;

  @override
  Map<String, Object?> toJson() => {
        'debtorId': debtorId,
        'amount': amount,
        if (creditorId != null) 'creditorId': creditorId,
        if (toPot) 'toPot': true,
      };

  /// Decodes a debt.
  factory Debt.fromJson(Map<String, Object?> json) => Debt(
        debtorId: json['debtorId'] as String,
        amount: readInt(json, 'amount'),
        creditorId: json['creditorId'] as String?,
        toPot: json['toPot'] as bool? ?? false,
      );
}

/// A player's device session, used to rejoin the same seat.
class Session with JsonEquality {
  /// Creates a session.
  const Session({
    required this.playerId,
    required this.token,
    this.deviceName = '',
    required this.lastSeen,
  });

  /// Seat id.
  final String playerId;

  /// Secret session token.
  final String token;

  /// Device label.
  final String deviceName;

  /// Last heartbeat, ms since epoch.
  final int lastSeen;

  /// Copy with a new heartbeat time.
  Session seenAt(int ms) => Session(
        playerId: playerId,
        token: token,
        deviceName: deviceName,
        lastSeen: ms,
      );

  @override
  Map<String, Object?> toJson() => {
        'playerId': playerId,
        'token': token,
        'deviceName': deviceName,
        'lastSeen': lastSeen,
      };

  /// Decodes a session.
  factory Session.fromJson(Map<String, Object?> json) => Session(
        playerId: json['playerId'] as String,
        token: json['token'] as String,
        deviceName: json['deviceName'] as String? ?? '',
        lastSeen: readInt(json, 'lastSeen'),
      );
}
