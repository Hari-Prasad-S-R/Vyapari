import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Injected source of randomness. Core never creates randomness on its own.
abstract interface class RandomSource {
  /// Returns [n] random bytes.
  List<int> nextBytes(int n);

  /// Returns a random int in `[0, max)`.
  int nextInt(int max);
}

/// Cryptographically secure source (`Random.secure`). Used by servers.
class SecureRandomSource implements RandomSource {
  final Random _r = Random.secure();

  @override
  List<int> nextBytes(int n) => List<int>.generate(n, (_) => _r.nextInt(256));

  @override
  int nextInt(int max) => _r.nextInt(max);
}

/// Repeatable source for tests and simulations.
class SeededRandomSource implements RandomSource {
  /// Creates a source from [seed].
  SeededRandomSource(int seed) : _r = Random(seed);
  final Random _r;

  @override
  List<int> nextBytes(int n) => List<int>.generate(n, (_) => _r.nextInt(256));

  @override
  int nextInt(int max) => _r.nextInt(max);
}

/// Published before a roll: `SHA-256(rollKey ‖ rollNumber)`.
class DiceCommit {
  /// Creates a commit.
  const DiceCommit({required this.rollNumber, required this.hash});

  /// Sequence number of the roll this commit binds.
  final int rollNumber;

  /// Hex SHA-256 hash.
  final String hash;

  /// JSON form.
  Map<String, Object?> toJson() => {'rollNumber': rollNumber, 'hash': hash};

  /// Decodes a commit.
  factory DiceCommit.fromJson(Map<String, Object?> json) => DiceCommit(
      rollNumber: json['rollNumber'] as int, hash: json['hash'] as String);
}

/// Published after a roll: the key and the resulting dice.
class DiceReveal {
  /// Creates a reveal.
  const DiceReveal({
    required this.rollNumber,
    required this.key,
    required this.d1,
    required this.d2,
  });

  /// Sequence number.
  final int rollNumber;

  /// Hex roll key.
  final String key;

  /// First die 1–6.
  final int d1;

  /// Second die 1–6.
  final int d2;

  /// Sum of both dice.
  int get total => d1 + d2;

  /// Whether both dice match.
  bool get isDouble => d1 == d2;

  /// JSON form.
  Map<String, Object?> toJson() =>
      {'rollNumber': rollNumber, 'key': key, 'd1': d1, 'd2': d2};

  /// Decodes a reveal.
  factory DiceReveal.fromJson(Map<String, Object?> json) => DiceReveal(
        rollNumber: json['rollNumber'] as int,
        key: json['key'] as String,
        d1: json['d1'] as int,
        d2: json['d2'] as int,
      );
}

/// Server-side fair dice with commit–reveal.
///
/// A secret game key is drawn once per game. Roll *n* uses
/// `rollKey = HMAC-SHA256(gameKey, "roll:n")`; the dice are derived from the
/// roll key, the commit is `SHA-256(rollKey ‖ n)`. Revealing a roll key never
/// exposes the game key, so later rolls stay unpredictable.
class FairDice {
  /// Creates dice with a fresh game key from [source].
  FairDice(RandomSource source) : _gameKey = source.nextBytes(32);

  final List<int> _gameKey;
  int _next = 1;

  /// Commit for the next roll; publish it before accepting the roll intent.
  DiceCommit get nextCommit {
    final key = _rollKey(_next);
    return DiceCommit(rollNumber: _next, hash: commitHash(key, _next));
  }

  /// Rolls the committed dice and returns the reveal.
  DiceReveal roll() {
    final n = _next++;
    final key = _rollKey(n);
    final dice = deriveDice(key);
    return DiceReveal(rollNumber: n, key: _hex(key), d1: dice[0], d2: dice[1]);
  }

  List<int> _rollKey(int n) =>
      Hmac(sha256, _gameKey).convert(utf8.encode('roll:$n')).bytes;

  /// Commit hash for a roll key and number.
  static String commitHash(List<int> rollKey, int rollNumber) =>
      sha256.convert([...rollKey, ...utf8.encode('$rollNumber')]).toString();

  /// Derives two unbiased dice (1–6) from a roll key via rejection sampling.
  static List<int> deriveDice(List<int> rollKey) {
    final out = <int>[];
    var counter = 0;
    while (out.length < 2) {
      final block = sha256.convert([...rollKey, counter++]).bytes;
      for (final b in block) {
        if (b < 252) out.add(b % 6 + 1);
        if (out.length == 2) break;
      }
    }
    return out;
  }

  /// Checks that [reveal] matches [commit] and that the dice follow from the
  /// revealed key.
  static bool verify(DiceCommit commit, DiceReveal reveal) {
    if (commit.rollNumber != reveal.rollNumber) return false;
    final List<int> key;
    try {
      key = _unhex(reveal.key);
    } on FormatException {
      return false;
    }
    if (commitHash(key, reveal.rollNumber) != commit.hash) return false;
    final dice = deriveDice(key);
    return dice[0] == reveal.d1 && dice[1] == reveal.d2;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _unhex(String hex) {
    if (hex.length.isOdd) throw const FormatException('odd hex length');
    return [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
  }
}
