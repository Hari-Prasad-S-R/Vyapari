import '../json_equality.dart';

/// Player tokens.
enum Token { autoRickshaw, ambassador, elephant, cricketBat, kite, teaGlass }

/// Bot difficulty.
enum BotLevel { easy, medium, hard }

const _unset = Object();

/// A seat in the game.
class Player with JsonEquality {
  /// Creates a player.
  Player({
    required this.id,
    required this.name,
    required this.token,
    this.cash = 0,
    this.position = 0,
    this.inJail = false,
    this.jailTurns = 0,
    List<String> getOutCards = const [],
    this.doublesInRow = 0,
    this.isBot = false,
    this.botLevel,
    this.connected = true,
    this.bankrupt = false,
    this.ready = false,
  }) : getOutCards = List.unmodifiable(getOutCards);

  /// Stable player id.
  final String id;

  /// Nickname.
  final String name;

  /// Board token.
  final Token token;

  /// Cash in whole rupees.
  final int cash;

  /// Tile index 0–39.
  final int position;

  /// Whether the player is in jail.
  final bool inJail;

  /// Failed attempts to roll out of jail.
  final int jailTurns;

  /// Ids of held get-out-of-jail cards.
  final List<String> getOutCards;

  /// Doubles rolled in a row this turn.
  final int doublesInRow;

  /// Whether a bot controls this seat.
  final bool isBot;

  /// Bot level when [isBot].
  final BotLevel? botLevel;

  /// Whether the player's device is connected.
  final bool connected;

  /// Whether the player is out of the game.
  final bool bankrupt;

  /// Lobby ready tick.
  final bool ready;

  /// Whether this player may act in the game.
  bool get active => !bankrupt;

  /// Copy with changes.
  Player copyWith({
    String? name,
    Token? token,
    int? cash,
    int? position,
    bool? inJail,
    int? jailTurns,
    List<String>? getOutCards,
    int? doublesInRow,
    bool? isBot,
    Object? botLevel = _unset,
    bool? connected,
    bool? bankrupt,
    bool? ready,
  }) =>
      Player(
        id: id,
        name: name ?? this.name,
        token: token ?? this.token,
        cash: cash ?? this.cash,
        position: position ?? this.position,
        inJail: inJail ?? this.inJail,
        jailTurns: jailTurns ?? this.jailTurns,
        getOutCards: getOutCards ?? this.getOutCards,
        doublesInRow: doublesInRow ?? this.doublesInRow,
        isBot: isBot ?? this.isBot,
        botLevel:
            identical(botLevel, _unset) ? this.botLevel : botLevel as BotLevel?,
        connected: connected ?? this.connected,
        bankrupt: bankrupt ?? this.bankrupt,
        ready: ready ?? this.ready,
      );

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'token': token.name,
        'cash': cash,
        'position': position,
        'inJail': inJail,
        'jailTurns': jailTurns,
        'getOutCards': getOutCards,
        'doublesInRow': doublesInRow,
        'isBot': isBot,
        if (botLevel != null) 'botLevel': botLevel!.name,
        'connected': connected,
        'bankrupt': bankrupt,
        'ready': ready,
      };

  /// Decodes a player.
  factory Player.fromJson(Map<String, Object?> json) => Player(
        id: json['id'] as String,
        name: json['name'] as String,
        token: Token.values.byName(json['token'] as String),
        cash: readInt(json, 'cash'),
        position: readInt(json, 'position'),
        inJail: json['inJail'] as bool,
        jailTurns: readInt(json, 'jailTurns'),
        getOutCards: readStringList(json['getOutCards']),
        doublesInRow: readInt(json, 'doublesInRow'),
        isBot: json['isBot'] as bool,
        botLevel: json['botLevel'] == null
            ? null
            : BotLevel.values.byName(json['botLevel'] as String),
        connected: json['connected'] as bool,
        bankrupt: json['bankrupt'] as bool,
        ready: json['ready'] as bool? ?? false,
      );
}
