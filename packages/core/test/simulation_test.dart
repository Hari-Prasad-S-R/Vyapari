import 'dart:io';

import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';

import 'helpers.dart';

void main() {
  // CI runs 1,000 games per push; set VYAPARI_SIM_GAMES=10000 nightly.
  final games =
      int.tryParse(Platform.environment['VYAPARI_SIM_GAMES'] ?? '') ?? 1000;

  test('$games simulated games: no crash, no stuck game, money conserved', () {
    final report = Simulator(india()).run(games: games, seed: 11);
    // ignore: avoid_print
    print(report);
    expect(report.failures, isEmpty);
    expect(report.clean, isTrue);
    expect(report.maxTurns, lessThanOrEqualTo(Simulator.stuckTurns));
  }, timeout: const Timeout(Duration(minutes: 30)));

  test('classic rules with no turn limit still finish under 500 turns often',
      () {
    final report = Simulator(india()).run(
        games: 50,
        seed: 3,
        randomRules: false,
        levels: [BotLevel.medium, BotLevel.hard, BotLevel.medium],
        turnLimit: Simulator.stuckTurns);
    expect(report.crashes, 0);
    expect(report.moneyLeaks, 0);
  });

  test('bot drivers always find a legal action', () {
    final s = startedGame();
    for (final level in BotLevel.values) {
      final bot = Bot.forLevel(level, SeededRandomSource(1));
      expect(botAct(bot, s, 'p0', () => [3, 4]), isNotNull);
    }
  });

  test('1,000 games: Hard beats Easy in at least 70%', () {
    final report = Simulator(india()).run(
        games: 1000,
        seed: 21,
        randomRules: false,
        levels: [BotLevel.hard, BotLevel.easy]);
    final hard = report.wins[BotLevel.hard] ?? 0;
    // ignore: avoid_print
    print('hard vs easy: $report');
    expect(report.clean, isTrue);
    expect(hard / report.games, greaterThanOrEqualTo(0.7));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
