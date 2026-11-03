import '../json_equality.dart';

/// Host-selectable house rules.
class HouseRules with JsonEquality {
  /// Creates house rules; defaults are the classic rules.
  const HouseRules({
    this.freeParkingPot = false,
    this.doubleOnStart = false,
    this.auctions = true,
    this.noRentInJail = false,
    this.quickGame = false,
    this.turnTimerSec = 60,
    this.startingCash = 1500000,
    this.botCover = true,
    this.timeLimitMin,
    this.maxTurns,
  });

  /// Taxes and fines go to a pot collected on Free Parking.
  final bool freeParkingPot;

  /// Double salary for landing exactly on Start.
  final bool doubleOnStart;

  /// Declined purchases go to auction.
  final bool auctions;

  /// Jailed owners collect no rent.
  final bool noRentInJail;

  /// Two random cities each and a 60-minute limit.
  final bool quickGame;

  /// Seconds per turn before the server ends it (0 = off).
  final int turnTimerSec;

  /// Starting cash per player.
  final int startingCash;

  /// While a player is disconnected a bot plays their turn (else auto-skip).
  final bool botCover;

  /// Game time limit in minutes (quick game uses 60). Enforced by the server.
  final int? timeLimitMin;

  /// Optional turn limit; highest net worth wins when reached.
  final int? maxTurns;

  /// Effective time limit in minutes.
  int? get effectiveTimeLimitMin => timeLimitMin ?? (quickGame ? 60 : null);

  /// Copy with changes.
  HouseRules copyWith({
    bool? freeParkingPot,
    bool? doubleOnStart,
    bool? auctions,
    bool? noRentInJail,
    bool? quickGame,
    int? turnTimerSec,
    int? startingCash,
    bool? botCover,
    int? timeLimitMin,
    int? maxTurns,
  }) =>
      HouseRules(
        freeParkingPot: freeParkingPot ?? this.freeParkingPot,
        doubleOnStart: doubleOnStart ?? this.doubleOnStart,
        auctions: auctions ?? this.auctions,
        noRentInJail: noRentInJail ?? this.noRentInJail,
        quickGame: quickGame ?? this.quickGame,
        turnTimerSec: turnTimerSec ?? this.turnTimerSec,
        startingCash: startingCash ?? this.startingCash,
        botCover: botCover ?? this.botCover,
        timeLimitMin: timeLimitMin ?? this.timeLimitMin,
        maxTurns: maxTurns ?? this.maxTurns,
      );

  @override
  Map<String, Object?> toJson() => {
        'freeParkingPot': freeParkingPot,
        'doubleOnStart': doubleOnStart,
        'auctions': auctions,
        'noRentInJail': noRentInJail,
        'quickGame': quickGame,
        'turnTimerSec': turnTimerSec,
        'startingCash': startingCash,
        'botCover': botCover,
        if (timeLimitMin != null) 'timeLimitMin': timeLimitMin,
        if (maxTurns != null) 'maxTurns': maxTurns,
      };

  /// Decodes house rules; missing fields take defaults.
  factory HouseRules.fromJson(Map<String, Object?> json) => HouseRules(
        freeParkingPot: json['freeParkingPot'] as bool? ?? false,
        doubleOnStart: json['doubleOnStart'] as bool? ?? false,
        auctions: json['auctions'] as bool? ?? true,
        noRentInJail: json['noRentInJail'] as bool? ?? false,
        quickGame: json['quickGame'] as bool? ?? false,
        turnTimerSec: readIntOr(json, 'turnTimerSec', 60),
        startingCash: readIntOr(json, 'startingCash', 1500000),
        botCover: json['botCover'] as bool? ?? true,
        timeLimitMin: json['timeLimitMin'] as int?,
        maxTurns: json['maxTurns'] as int?,
      );
}

/// Board-level constants loaded from `board.json`.
class GameConfig with JsonEquality {
  /// Creates config with the documented defaults.
  const GameConfig({
    this.startingCash = 1500000,
    this.salary = 200000,
    this.jailFine = 50000,
    this.unmortgageInterestPct = 10,
    this.houses = 32,
    this.hotels = 12,
    this.utilityUnit = 1000,
    this.auctionMinStep = 10000,
    this.bankCash = 200000000,
    this.maxPlayers = 8,
  });

  /// Default starting cash.
  final int startingCash;

  /// Salary for passing Start.
  final int salary;

  /// Jail fine.
  final int jailFine;

  /// Unmortgage interest in percent.
  final int unmortgageInterestPct;

  /// Houses in the bank.
  final int houses;

  /// Hotels in the bank.
  final int hotels;

  /// Rupees per utility pip (dice × multiplier × unit).
  final int utilityUnit;

  /// Minimum auction raise.
  final int auctionMinStep;

  /// Notional bank cash at start (used for conservation checks).
  final int bankCash;

  /// Maximum seats.
  final int maxPlayers;

  @override
  Map<String, Object?> toJson() => {
        'startingCash': startingCash,
        'salary': salary,
        'jailFine': jailFine,
        'unmortgageInterestPct': unmortgageInterestPct,
        'houses': houses,
        'hotels': hotels,
        'utilityUnit': utilityUnit,
        'auctionMinStep': auctionMinStep,
        'bankCash': bankCash,
        'maxPlayers': maxPlayers,
      };

  /// Decodes config; missing fields take defaults.
  factory GameConfig.fromJson(Map<String, Object?> json) => GameConfig(
        startingCash: readIntOr(json, 'startingCash', 1500000),
        salary: readIntOr(json, 'salary', 200000),
        jailFine: readIntOr(json, 'jailFine', 50000),
        unmortgageInterestPct: readIntOr(json, 'unmortgageInterestPct', 10),
        houses: readIntOr(json, 'houses', 32),
        hotels: readIntOr(json, 'hotels', 12),
        utilityUnit: readIntOr(json, 'utilityUnit', 1000),
        auctionMinStep: readIntOr(json, 'auctionMinStep', 10000),
        bankCash: readIntOr(json, 'bankCash', 200000000),
        maxPlayers: readIntOr(json, 'maxPlayers', 8),
      );
}

/// Something that happened, used for animation and the activity log.
class GameEvent with JsonEquality {
  /// Creates an event.
  GameEvent(this.type,
      {this.playerId, Map<String, Object?> data = const {}, this.text = ''})
      : data = Map.unmodifiable(data);

  /// Event kind, e.g. `rolled`, `bought`, `rent`.
  final String type;

  /// Main player involved.
  final String? playerId;

  /// Extra details (JSON-safe values only).
  final Map<String, Object?> data;

  /// Human-readable log line.
  final String text;

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        if (playerId != null) 'playerId': playerId,
        if (data.isNotEmpty) 'data': data,
        'text': text,
      };

  /// Decodes an event.
  factory GameEvent.fromJson(Map<String, Object?> json) => GameEvent(
        json['type'] as String,
        playerId: json['playerId'] as String?,
        data: json['data'] == null ? const {} : readMap(json['data']),
        text: json['text'] as String? ?? '',
      );
}
