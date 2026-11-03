import 'dart:io';

import 'package:vyapari_core/vyapari_core.dart';

/// Repo root, found by walking up to the `assets` folder.
Directory repoRoot() {
  var dir = Directory.current;
  while (!Directory('${dir.path}/assets/boards/india').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('repo root not found');
    dir = parent;
  }
  return dir;
}

/// Raw JSON of the India board files.
(String board, String cards) indiaJson() {
  final root = repoRoot().path;
  return (
    File('$root/assets/boards/india/board.json').readAsStringSync(),
    File('$root/assets/boards/india/cards.json').readAsStringSync(),
  );
}

/// The validated India board.
BoardData india() {
  final (b, c) = indiaJson();
  return BoardData.parse(b, c);
}

/// Applies [a] and expects success.
GameState ok(GameAction a, GameState s) {
  final r = apply(a, s);
  if (!r.ok) {
    throw StateError('${a.runtimeType} rejected: ${r.error} in ${s.phase}');
  }
  return r.state;
}

/// A started game with [n] players p0..p(n-1) in that order, p0 to move.
GameState startedGame({int n = 3, HouseRules rules = const HouseRules()}) {
  var s = newLobby(roomId: '1234', board: india(), rules: rules);
  for (var i = 0; i < n; i++) {
    s = ok(JoinGame('p$i', name: 'P$i', token: Token.values[i % 6]), s);
    s = ok(SetReady('p$i', ready: true), s);
  }
  return ok(
      StartGame('p0',
          seed: 7, openingRolls: {for (var i = 0; i < n; i++) 'p$i': 12 - i}),
      s);
}

/// Replaces player [id] using [f].
GameState withPlayer(GameState s, String id, Player Function(Player) f) =>
    s.copyWith(players: [for (final p in s.players) p.id == id ? f(p) : p]);

/// Gives [id] ownership of [tiles].
GameState withOwned(GameState s, String id, List<int> tiles,
        {int houses = 0, bool mortgaged = false}) =>
    s.copyWith(ownership: [
      ...s.ownership.where((o) => !tiles.contains(o.tileIndex)),
      for (final t in tiles)
        Ownership(
            tileIndex: t, ownerId: id, houses: houses, mortgaged: mortgaged),
    ]);

/// Puts [deck]'s card [cardId] on top.
GameState withTopCard(GameState s, Deck deck, String cardId) {
  List<String> reorder(List<String> d) =>
      [cardId, ...d.where((c) => c != cardId)];
  return s.copyWith(
    decks: Decks(
      vaaippu:
          deck == Deck.vaaippu ? reorder(s.decks.vaaippu) : s.decks.vaaippu,
      undiyal:
          deck == Deck.undiyal ? reorder(s.decks.undiyal) : s.decks.undiyal,
    ),
  );
}

/// Cash of [id].
int cash(GameState s, String id) => s.player(id)!.cash;

/// Index of the tile named [name].
int tileNamed(GameState s, String name) =>
    s.tiles.firstWhere((t) => t.name == name).index;
