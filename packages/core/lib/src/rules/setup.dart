import '../board/board_data.dart';
import '../models/game_state.dart';
import '../models/misc.dart';
import '../models/rules.dart';

/// Creates an empty lobby for [board].
GameState newLobby({
  required String roomId,
  required BoardData board,
  HouseRules rules = const HouseRules(),
}) =>
    GameState(
      roomId: roomId,
      tiles: board.tiles,
      cards: board.cards,
      bank: Bank(
        cash: board.config.bankCash,
        houses: board.config.houses,
        hotels: board.config.hotels,
      ),
      decks: Decks(),
      rules: rules.copyWith(startingCash: rules.startingCash),
      config: board.config,
    );
