/// Vyapari core: pure Dart models, rules engine, fair dice and bots.
///
/// No Flutter, no `dart:io`, no clocks or randomness except injected.
library;

export 'src/board/board_data.dart';
export 'src/bots/bots.dart';
export 'src/dice/fair_dice.dart';
export 'src/json_equality.dart' show JsonEquality;
export 'src/models/card.dart';
export 'src/models/game_state.dart';
export 'src/models/misc.dart';
export 'src/models/player.dart';
export 'src/models/rules.dart';
export 'src/models/tile.dart';
export 'src/money.dart';
export 'src/rules/actions.dart';
export 'src/rules/engine.dart';
export 'src/rules/queries.dart';
export 'src/rules/setup.dart';
export 'src/sim/simulator.dart';
