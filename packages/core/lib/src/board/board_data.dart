import 'dart:convert';

import '../json_equality.dart';
import '../models/card.dart';
import '../models/rules.dart';
import '../models/tile.dart';

/// Thrown when board or card JSON fails validation.
class BoardValidationException implements Exception {
  /// Creates the exception with a list of problems.
  BoardValidationException(this.problems);

  /// Human-readable problems, one per entry.
  final List<String> problems;

  @override
  String toString() => 'Invalid board data: ${problems.join('; ')}';
}

/// A validated board theme: tiles, cards and constants.
class BoardData {
  /// Creates board data. Prefer [BoardData.parse].
  BoardData({
    required this.name,
    required List<Tile> tiles,
    required List<GameCard> cards,
    required this.config,
    Map<String, String> groupNames = const {},
  })  : tiles = List.unmodifiable(tiles),
        cards = List.unmodifiable(cards),
        groupNames = Map.unmodifiable(groupNames);

  /// Theme name.
  final String name;

  /// 40 tiles ordered by index.
  final List<Tile> tiles;

  /// All cards of both decks.
  final List<GameCard> cards;

  /// Board constants.
  final GameConfig config;

  /// Display names of groups.
  final Map<String, String> groupNames;

  /// Number of tiles a board must have.
  static const tileCount = 40;

  /// Cards per deck.
  static const cardsPerDeck = 16;

  /// Parses and validates `board.json` and `cards.json` contents.
  ///
  /// Throws [BoardValidationException] naming every problem found.
  factory BoardData.parse(String boardJson, String cardsJson) {
    final problems = <String>[];
    Map<String, Object?> board;
    Map<String, Object?> cardsDoc;
    try {
      board = readMap(jsonDecode(boardJson));
    } catch (e) {
      throw BoardValidationException(['board.json is not a JSON object: $e']);
    }
    try {
      cardsDoc = readMap(jsonDecode(cardsJson));
    } catch (e) {
      throw BoardValidationException(['cards.json is not a JSON object: $e']);
    }

    final groups = board['groups'] == null
        ? <String, Map<String, Object?>>{}
        : readMap(board['groups']).map((k, v) => MapEntry(k, readMap(v)));

    final tiles = <Tile>[];
    for (final raw in readMapList(board['tiles'])) {
      try {
        var tile = Tile.fromJson(raw);
        final g = tile.group;
        if (g != null && groups[g] != null && tile.color == null) {
          tile = Tile.fromJson({...raw, 'color': groups[g]!['color']});
        }
        tiles.add(tile);
      } catch (e) {
        problems.add('tile ${raw['index']}: $e');
      }
    }
    tiles.sort((a, b) => a.index.compareTo(b.index));

    if (tiles.length != tileCount) {
      problems.add('expected $tileCount tiles, found ${tiles.length}');
    }
    final seen = <int>{};
    for (final t in tiles) {
      if (!seen.add(t.index)) problems.add('duplicate tile index ${t.index}');
      if (t.index < 0 || t.index >= tileCount) {
        problems.add('tile index ${t.index} out of range');
      }
      _validateTile(t, problems);
    }
    for (var i = 0; i < tileCount; i++) {
      if (!seen.contains(i)) {
        problems.add('missing tile index $i');
      }
    }
    final corners = tiles.where((t) => t.type == TileType.corner).toList();
    for (final kind in CornerKind.values) {
      final n = corners.where((t) => t.corner == kind).length;
      if (n != 1) problems.add('expected one ${kind.name} corner, found $n');
    }
    final cityGroups = <String, int>{};
    for (final t in tiles.where((t) => t.type == TileType.city)) {
      cityGroups[t.group ?? ''] = (cityGroups[t.group ?? ''] ?? 0) + 1;
    }
    cityGroups.forEach((g, n) {
      if (n < 2) problems.add('group "$g" has only $n city; needs 2 or more');
    });

    final cards = <GameCard>[];
    for (final raw in readMapList(cardsDoc['cards'])) {
      try {
        cards.add(GameCard.fromJson(raw));
      } catch (e) {
        problems.add('card ${raw['id']}: $e');
      }
    }
    final cardIds = <String>{};
    for (final c in cards) {
      if (!cardIds.add(c.id)) problems.add('duplicate card id ${c.id}');
      final e = c.effect;
      switch (e.type) {
        case CardEffectType.moveTo:
          if (e.target < 0 || e.target >= tileCount) {
            problems.add('card ${c.id}: moveTo target ${e.target} invalid');
          }
        case CardEffectType.moveBack:
          if (e.target <= 0) problems.add('card ${c.id}: moveBack needs steps');
        case CardEffectType.collect ||
              CardEffectType.pay ||
              CardEffectType.payEachPlayer ||
              CardEffectType.collectFromEachPlayer:
          if (e.amount <= 0) problems.add('card ${c.id}: amount must be > 0');
        case CardEffectType.repairs:
          if (e.perHouse <= 0 || e.perHotel <= 0) {
            problems.add('card ${c.id}: repairs needs perHouse and perHotel');
          }
        case CardEffectType.goToJail || CardEffectType.getOutOfJail:
          break;
      }
    }
    for (final deck in Deck.values) {
      final n = cards.where((c) => c.deck == deck).length;
      if (n != cardsPerDeck) {
        problems.add('deck ${deck.name} needs $cardsPerDeck cards, found $n');
      }
    }

    if (problems.isNotEmpty) throw BoardValidationException(problems);

    return BoardData(
      name: board['name'] as String? ?? 'Board',
      tiles: tiles,
      cards: cards,
      config: board['config'] == null
          ? const GameConfig()
          : GameConfig.fromJson(readMap(board['config'])),
      groupNames: groups.map((k, v) => MapEntry(k, v['name'] as String? ?? k)),
    );
  }

  static void _validateTile(Tile t, List<String> problems) {
    final where = 'tile ${t.index} (${t.name})';
    switch (t.type) {
      case TileType.city:
        if (t.group == null) problems.add('$where: city needs a group');
        if (t.price <= 0) problems.add('$where: city needs a price');
        if (t.houseCost <= 0) problems.add('$where: city needs houseCost');
        if (t.rent.length != 6) {
          problems.add('$where: city rent needs 6 values');
        }
      case TileType.transport:
        if (t.price <= 0) problems.add('$where: transport needs a price');
        if (t.rent.length != 4) {
          problems.add('$where: transport rent needs 4 values');
        }
      case TileType.utility:
        if (t.price <= 0) problems.add('$where: utility needs a price');
        if (t.rent.length != 2) {
          problems.add('$where: utility rent needs 2 multipliers');
        }
      case TileType.tax:
        if (t.amount <= 0) problems.add('$where: tax needs an amount');
      case TileType.card:
        if (t.deck == null) problems.add('$where: card tile needs a deck');
      case TileType.corner:
        if (t.corner == null) problems.add('$where: corner needs a kind');
    }
  }
}
