import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';

void main() {
  test('a commit and its reveal verify', () {
    final dice = FairDice(SecureRandomSource());
    for (var i = 0; i < 50; i++) {
      final commit = dice.nextCommit;
      final reveal = dice.roll();
      expect(FairDice.verify(commit, reveal), isTrue);
      expect(reveal.d1, inInclusiveRange(1, 6));
      expect(reveal.d2, inInclusiveRange(1, 6));
    }
  });

  test('a tampered roll fails verification', () {
    final dice = FairDice(SecureRandomSource());
    final commit = dice.nextCommit;
    final r = dice.roll();
    final fake = DiceReveal(
        rollNumber: r.rollNumber, key: r.key, d1: r.d1 % 6 + 1, d2: r.d2);
    expect(FairDice.verify(commit, fake), isFalse);
    final badKey = DiceReveal(
        rollNumber: r.rollNumber,
        key: '00${r.key.substring(2)}',
        d1: r.d1,
        d2: r.d2);
    expect(FairDice.verify(commit, badKey), isFalse);
    final wrongNumber = DiceReveal(
        rollNumber: r.rollNumber + 1, key: r.key, d1: r.d1, d2: r.d2);
    expect(FairDice.verify(commit, wrongNumber), isFalse);
  });

  test('a fixed seed repeats results', () {
    List<int> rolls(int seed) {
      final d = FairDice(SeededRandomSource(seed));
      return [for (var i = 0; i < 20; i++) d.roll().total];
    }

    expect(rolls(42), rolls(42));
    expect(rolls(42), isNot(rolls(43)));
  });

  test('1,000,000 rolls: each face 16.7% ± 0.2%', () {
    final d = FairDice(SeededRandomSource(2026));
    final counts = List.filled(7, 0);
    const n = 1000000;
    for (var i = 0; i < n; i++) {
      final r = d.roll();
      counts[r.d1]++;
      counts[r.d2]++;
    }
    for (var face = 1; face <= 6; face++) {
      final share = counts[face] / (2 * n);
      expect(share, closeTo(1 / 6, 0.002), reason: 'face $face');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
