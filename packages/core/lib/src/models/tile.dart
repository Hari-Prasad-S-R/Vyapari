import '../json_equality.dart';

/// Kind of board tile.
enum TileType { city, transport, utility, tax, card, corner }

/// Corner tile kinds.
enum CornerKind { start, jail, freeParking, goToJail }

/// Card deck names.
enum Deck { vaaippu, undiyal }

/// A static board tile loaded from `board.json`.
class Tile with JsonEquality {
  /// Creates a tile.
  Tile({
    required this.index,
    required this.type,
    required this.name,
    this.group,
    this.color,
    this.price = 0,
    List<int> rent = const [],
    this.houseCost = 0,
    int? mortgageValue,
    this.amount = 0,
    this.deck,
    this.corner,
  })  : rent = List.unmodifiable(rent),
        mortgageValue = mortgageValue ?? price ~/ 2;

  /// Position 0–39.
  final int index;

  /// Tile kind.
  final TileType type;

  /// Display name.
  final String name;

  /// Colour group id for cities (e.g. `g1`), `transport` or `utility`.
  final String? group;

  /// Hex colour for the group band, e.g. `#8B4513`.
  final String? color;

  /// Purchase price in rupees (0 if not ownable).
  final int price;

  /// City: [base, 1h, 2h, 3h, 4h, hotel]. Transport: rent by count owned.
  /// Utility: dice multipliers for one / both owned.
  final List<int> rent;

  /// Cost of one house (cities only).
  final int houseCost;

  /// Mortgage value (half the price by default).
  final int mortgageValue;

  /// Tax amount for tax tiles.
  final int amount;

  /// Deck to draw from for card tiles.
  final Deck? deck;

  /// Corner kind for corner tiles.
  final CornerKind? corner;

  /// Whether a player can own this tile.
  bool get isOwnable =>
      type == TileType.city ||
      type == TileType.transport ||
      type == TileType.utility;

  @override
  Map<String, Object?> toJson() => {
        'index': index,
        'type': type.name,
        'name': name,
        if (group != null) 'group': group,
        if (color != null) 'color': color,
        if (price != 0) 'price': price,
        if (rent.isNotEmpty) 'rent': rent,
        if (houseCost != 0) 'houseCost': houseCost,
        if (price != 0) 'mortgageValue': mortgageValue,
        if (amount != 0) 'amount': amount,
        if (deck != null) 'deck': deck!.name,
        if (corner != null) 'corner': corner!.name,
      };

  /// Decodes a tile. Throws [FormatException] on unknown enum names.
  factory Tile.fromJson(Map<String, Object?> json) => Tile(
        index: readInt(json, 'index'),
        type: _enumByName(TileType.values, json['type'], 'tile type'),
        name: json['name'] as String,
        group: json['group'] as String?,
        color: json['color'] as String?,
        price: readIntOr(json, 'price', 0),
        rent: readIntList(json['rent']),
        houseCost: readIntOr(json, 'houseCost', 0),
        mortgageValue: json['mortgageValue'] as int?,
        amount: readIntOr(json, 'amount', 0),
        deck: json['deck'] == null
            ? null
            : _enumByName(Deck.values, json['deck'], 'deck'),
        corner: json['corner'] == null
            ? null
            : _enumByName(CornerKind.values, json['corner'], 'corner'),
      );
}

T _enumByName<T extends Enum>(List<T> values, Object? name, String what) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('Unknown $what "$name"');
}

/// Looks up an enum value by name, throwing [FormatException] if unknown.
T enumByName<T extends Enum>(List<T> values, Object? name, String what) =>
    _enumByName(values, name, what);
