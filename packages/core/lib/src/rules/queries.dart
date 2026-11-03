import '../models/game_state.dart';
import '../models/misc.dart';
import '../models/tile.dart';

/// Read-only helpers over a [GameState], shared by the engine, bots and UI.
extension GameQueries on GameState {
  /// Index of the jail tile.
  int get jailIndex =>
      tiles.firstWhere((t) => t.corner == CornerKind.jail).index;

  /// Tiles in [group].
  List<Tile> groupTiles(String group) =>
      tiles.where((t) => t.group == group).toList();

  /// Ownership records owned by [playerId].
  List<Ownership> ownedBy(String playerId) =>
      ownership.where((o) => o.ownerId == playerId).toList();

  /// Whether [playerId] owns every city in [group].
  bool ownsFullGroup(String playerId, String group) =>
      groupTiles(group).every((t) => ownershipOf(t.index)?.ownerId == playerId);

  /// Whether any tile in [group] has buildings.
  bool groupHasBuildings(String group) =>
      groupTiles(group).any((t) => (ownershipOf(t.index)?.houses ?? 0) > 0);

  /// Rent due when landing on [tileIndex] with [diceTotal], ignoring who
  /// lands (0 if unowned or mortgaged).
  int rentFor(int tileIndex, int diceTotal) {
    final tile = tiles[tileIndex];
    final o = ownershipOf(tileIndex);
    if (o == null || o.mortgaged) return 0;
    switch (tile.type) {
      case TileType.city:
        if (o.houses > 0) return tile.rent[o.houses];
        final base = tile.rent[0];
        return ownsFullGroup(o.ownerId, tile.group!) ? base * 2 : base;
      case TileType.transport:
        final n = groupTiles(tile.group!)
            .where((t) => ownershipOf(t.index)?.ownerId == o.ownerId)
            .length;
        return tile.rent[n - 1];
      case TileType.utility:
        final n = groupTiles(tile.group!)
            .where((t) => ownershipOf(t.index)?.ownerId == o.ownerId)
            .length;
        return diceTotal * tile.rent[n - 1] * config.utilityUnit;
      case TileType.tax || TileType.card || TileType.corner:
        return 0;
    }
  }

  /// Cost to lift the mortgage on [tile].
  int unmortgageCost(Tile tile) =>
      tile.mortgageValue +
      (tile.mortgageValue * config.unmortgageInterestPct + 99) ~/ 100;

  /// Net worth: cash + property value (mortgage value if mortgaged) +
  /// building cost.
  int netWorth(String playerId) {
    final p = player(playerId);
    if (p == null || p.bankrupt) return 0;
    var worth = p.cash;
    for (final o in ownedBy(playerId)) {
      final t = tiles[o.tileIndex];
      worth += o.mortgaged ? t.mortgageValue : t.price;
      worth += o.houses * t.houseCost;
    }
    return worth;
  }

  /// Most a player could raise by selling all buildings and mortgaging.
  int liquidationValue(String playerId) {
    final p = player(playerId);
    if (p == null) return 0;
    var v = p.cash;
    for (final o in ownedBy(playerId)) {
      final t = tiles[o.tileIndex];
      v += o.houses * (t.houseCost ~/ 2);
      if (!o.mortgaged) v += t.mortgageValue;
    }
    return v;
  }

  /// Player who must act now: the first debtor while cash is being raised,
  /// nobody during an auction (anyone may bid), else the current player.
  String? get actingPlayer => switch (phase) {
        GamePhase.raiseCash when debts.isNotEmpty => debts.first.debtorId,
        GamePhase.auction || GamePhase.lobby || GamePhase.gameOver => null,
        _ => currentPlayer,
      };

  /// Total that [playerId] owes.
  int debtOf(String? playerId) => debts
      .where((d) => d.debtorId == playerId)
      .fold(0, (s, d) => s + d.amount);

  /// Total owed by the player now raising cash.
  int get totalDebt => debtOf(debts.isEmpty ? null : debts.first.debtorId);

  /// Active players ranked by net worth (highest first).
  List<String> get ranking {
    final ids = activePlayers.map((p) => p.id).toList();
    ids.sort((a, b) => netWorth(b).compareTo(netWorth(a)));
    return ids;
  }
}
