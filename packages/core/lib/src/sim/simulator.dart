import 'dart:math';

import '../board/board_data.dart';
import '../bots/bots.dart';
import '../dice/fair_dice.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../models/rules.dart';
import '../rules/actions.dart';
import '../rules/engine.dart';
import '../rules/queries.dart';
import '../rules/setup.dart';

/// Outcome of one simulated game.
class GameOutcome {
  /// Creates an outcome.
  GameOutcome({
    required this.finished,
    required this.turns,
    required this.actions,
    this.winnerLevel,
    this.failure,
  });

  /// Whether the game reached game over.
  final bool finished;

  /// Turns played.
  final int turns;

  /// Actions applied.
  final int actions;

  /// Level of the winning bot.
  final BotLevel? winnerLevel;

  /// Failure description (crash, stuck, money leak).
  final String? failure;
}

/// Aggregate results of a simulation run.
class SimulationReport {
  /// Games run.
  int games = 0;

  /// Games that threw.
  int crashes = 0;

  /// Games that stopped making progress or exceeded the turn cap.
  int stuck = 0;

  /// Games where total money changed.
  int moneyLeaks = 0;

  /// Most turns any game took.
  int maxTurns = 0;

  /// Wins per bot level.
  final Map<BotLevel, int> wins = {};

  /// First few failure descriptions.
  final List<String> failures = [];

  /// Whether every game was clean.
  bool get clean => crashes == 0 && stuck == 0 && moneyLeaks == 0;

  @override
  String toString() =>
      'games=$games crashes=$crashes stuck=$stuck leaks=$moneyLeaks '
      'maxTurns=$maxTurns wins=$wins';
}

/// Runs bot-only games through the rules engine.
class Simulator {
  /// Creates a simulator for [board].
  Simulator(this.board);

  /// Board to play on.
  final BoardData board;

  /// Hard cap; a game needing more turns counts as stuck.
  static const stuckTurns = 500;

  /// Runs [games] games. Each game uses 2–8 bots with random levels (or
  /// [levels] if given) and random house rules when [randomRules] is set.
  /// [turnLimit] plays the role of a time limit so games end.
  SimulationReport run({
    required int games,
    int seed = 1,
    bool randomRules = true,
    List<BotLevel>? levels,
    int turnLimit = 400,
  }) {
    final report = SimulationReport();
    for (var g = 0; g < games; g++) {
      final rng = Random(seed * 1000003 + g);
      final count = levels?.length ?? 2 + rng.nextInt(7);
      final lv = levels ??
          List.generate(count,
              (_) => BotLevel.values[rng.nextInt(BotLevel.values.length)]);
      final rules = randomRules
          ? HouseRules(
              freeParkingPot: rng.nextBool(),
              doubleOnStart: rng.nextBool(),
              auctions: rng.nextBool(),
              noRentInJail: rng.nextBool(),
              quickGame: rng.nextInt(4) == 0,
              maxTurns: turnLimit,
            )
          : HouseRules(maxTurns: turnLimit);
      final outcome =
          playOne(levels: lv, rules: rules, seed: rng.nextInt(1 << 31));
      report.games++;
      report.maxTurns = max(report.maxTurns, outcome.turns);
      if (outcome.winnerLevel != null) {
        report.wins[outcome.winnerLevel!] =
            (report.wins[outcome.winnerLevel!] ?? 0) + 1;
      }
      final f = outcome.failure;
      if (f != null) {
        if (f.startsWith('crash')) report.crashes++;
        if (f.startsWith('stuck')) report.stuck++;
        if (f.startsWith('leak')) report.moneyLeaks++;
        if (report.failures.length < 10) report.failures.add('game $g: $f');
      }
    }
    return report;
  }

  /// Plays a single game and checks money conservation after every action.
  GameOutcome playOne({
    required List<BotLevel> levels,
    required HouseRules rules,
    required int seed,
  }) {
    final rng = SeededRandomSource(seed);
    final diceRng = Random(seed ^ 0x5bd1e995);
    List<int> roll() => [diceRng.nextInt(6) + 1, diceRng.nextInt(6) + 1];
    var s = newLobby(roomId: 'sim', board: board, rules: rules);
    final bots = <String, Bot>{};
    var actions = 0;
    String? failure;
    try {
      for (var i = 0; i < levels.length; i++) {
        final id = 'p$i';
        s = _must(JoinGame(id, name: 'Bot $i', token: Token.values[i % 6]), s);
        s = _must(SetReady(id, ready: true), s);
        bots[id] = Bot.forLevel(levels[i], rng);
      }
      s = _must(SetRules('p0', rules), s);
      s = _must(
          StartGame('p0', seed: seed, openingRolls: {
            for (final id in bots.keys) id: diceRng.nextInt(11) + 2,
          }),
          s);
      for (final id in bots.keys) {
        s = _must(
            ReplaceWithBot(id, level: levels[int.parse(id.substring(1))]), s);
      }
      final total = s.startingTotal;

      while (s.phase != GamePhase.gameOver) {
        if (s.turnNumber > stuckTurns) {
          failure = 'stuck: exceeded $stuckTurns turns';
          break;
        }
        if (actions > 200000) {
          failure = 'stuck: too many actions';
          break;
        }
        ApplyResult? r;
        if (s.phase == GamePhase.auction) {
          for (final id in _auctionOrder(s)) {
            r = botAct(bots[id]!, s, id, roll);
            if (r != null) break;
          }
          r ??= apply(CloseAuction(s.currentPlayer!), s);
        } else {
          for (final t in s.trades) {
            r = botAct(bots[t.to]!, s, t.to, roll);
            if (r != null) break;
          }
          final actor = s.actingPlayer ?? s.currentPlayer!;
          r ??= botAct(bots[actor]!, s, actor, roll);
        }
        if (r == null || !r.ok) {
          failure = 'stuck: no legal action in ${s.phase.name}';
          break;
        }
        s = r.state;
        actions++;
        if (s.totalMoney != total) {
          failure = 'leak: total ${s.totalMoney} != $total after '
              '${r.events.map((e) => e.type).join(',')}';
          break;
        }
      }
    } catch (e, st) {
      failure = 'crash: $e\n$st';
    }
    final winner = s.winnerId;
    return GameOutcome(
      finished: s.phase == GamePhase.gameOver,
      turns: s.turnNumber,
      actions: actions,
      winnerLevel:
          winner == null ? null : levels[int.parse(winner.substring(1))],
      failure: failure,
    );
  }

  static List<String> _auctionOrder(GameState s) {
    final ids = s.players.where((p) => !p.bankrupt).map((p) => p.id).toList();
    final i = ids.indexOf(s.currentPlayer!);
    return [...ids.skip(i), ...ids.take(i)];
  }

  static GameState _must(GameAction a, GameState s) {
    final r = apply(a, s);
    if (!r.ok) {
      throw StateError('setup action ${a.runtimeType} failed: ${r.error}');
    }
    return r.state;
  }
}
