import '../json_equality.dart';
import 'tile.dart';

/// What a card does when drawn.
enum CardEffectType {
  collect,
  pay,
  payEachPlayer,
  collectFromEachPlayer,
  moveTo,
  moveBack,
  goToJail,
  getOutOfJail,
  repairs,
}

/// Typed effect of a card.
class CardEffect with JsonEquality {
  /// Creates an effect.
  const CardEffect({
    required this.type,
    this.amount = 0,
    this.target = 0,
    this.perHouse = 0,
    this.perHotel = 0,
  });

  /// Effect kind.
  final CardEffectType type;

  /// Rupee amount for money effects.
  final int amount;

  /// Tile index for `moveTo`, steps for `moveBack`.
  final int target;

  /// Repair cost per house.
  final int perHouse;

  /// Repair cost per hotel.
  final int perHotel;

  @override
  Map<String, Object?> toJson() => {
        'type': type.name,
        if (amount != 0) 'amount': amount,
        if (target != 0) 'target': target,
        if (perHouse != 0) 'perHouse': perHouse,
        if (perHotel != 0) 'perHotel': perHotel,
      };

  /// Decodes an effect.
  factory CardEffect.fromJson(Map<String, Object?> json) => CardEffect(
        type: enumByName(CardEffectType.values, json['type'], 'card effect'),
        amount: readIntOr(json, 'amount', 0),
        target: readIntOr(json, 'target', 0),
        perHouse: readIntOr(json, 'perHouse', 0),
        perHotel: readIntOr(json, 'perHotel', 0),
      );
}

/// A Vaaippu or Undiyal card from `cards.json`.
class GameCard with JsonEquality {
  /// Creates a card.
  const GameCard({
    required this.id,
    required this.deck,
    required this.text,
    required this.effect,
  });

  /// Unique card id, e.g. `v01`.
  final String id;

  /// Deck the card belongs to.
  final Deck deck;

  /// Original card text shown to players.
  final String text;

  /// Effect applied on draw.
  final CardEffect effect;

  @override
  Map<String, Object?> toJson() => {
        'id': id,
        'deck': deck.name,
        'text': text,
        'effect': effect.toJson(),
      };

  /// Decodes a card.
  factory GameCard.fromJson(Map<String, Object?> json) => GameCard(
        id: json['id'] as String,
        deck: enumByName(Deck.values, json['deck'], 'deck'),
        text: json['text'] as String,
        effect: CardEffect.fromJson(readMap(json['effect'])),
      );
}
