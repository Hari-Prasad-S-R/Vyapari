import 'dart:typed_data';

import 'package:vyapari_core/vyapari_core.dart';

/// Milliseconds clock, injectable for tests.
typedef Clock = int Function();

/// Wall clock in milliseconds since epoch.
int systemClock() => DateTime.now().millisecondsSinceEpoch;

/// Server tunables. Defaults follow the design document.
class ServerConfig {
  /// Creates a config.
  const ServerConfig({
    this.online = false,
    this.botDelay = const Duration(milliseconds: 700),
    this.auctionTime = const Duration(seconds: 10),
    this.heartbeatTimeout = const Duration(seconds: 20),
    this.heartbeatSweep = const Duration(seconds: 5),
    this.rejoinWindow = const Duration(minutes: 3),
    this.tradeReviewDelay = const Duration(seconds: 3),
    this.voiceInterval = const Duration(seconds: 3),
    this.maxRooms = 1000,
    this.maxFailedJoins = 5,
    this.joinBlockTime = const Duration(minutes: 1),
    this.enableTurnTimer = true,
    this.paceAnimations = true,
  });

  /// Online mode: many rooms, 6-character codes, `hello.create` allowed.
  final bool online;

  /// Delay before a bot acts (0 in tests).
  final Duration botDelay;

  /// Auction closes this long after the last bid.
  final Duration auctionTime;

  /// A connection silent this long is dropped.
  final Duration heartbeatTimeout;

  /// How often heartbeats are checked.
  final Duration heartbeatSweep;

  /// How long a dropped player may rejoin their seat.
  final Duration rejoinWindow;

  /// Humans cannot accept a trade sooner than this after it appears.
  final Duration tradeReviewDelay;

  /// Minimum gap between voice clips per player.
  final Duration voiceInterval;

  /// Room limit per server.
  final int maxRooms;

  /// Wrong codes/passwords before a device is blocked.
  final int maxFailedJoins;

  /// Block length after too many wrong attempts.
  final Duration joinBlockTime;

  /// Whether the per-turn timer runs.
  final bool enableTurnTimer;

  /// Wait for clients to finish animating a move (dice, steps, card pop-up)
  /// before a bot acts, so players can follow what happened. Off in tests.
  final bool paceAnimations;
}

/// One client connection (WebSocket in production, fakes in tests).
abstract interface class Peer {
  /// Remote address used for join rate limiting.
  String get remote;

  /// Sends a text frame.
  void sendText(String text);

  /// Sends a binary frame.
  void sendBinary(Uint8List bytes);

  /// Closes the connection.
  void close();
}

/// Allows one event per [interval] per key.
class RateLimiter {
  /// Creates a limiter.
  RateLimiter(this.interval, this.clock);

  /// Minimum gap.
  final Duration interval;

  /// Clock.
  final Clock clock;
  final Map<String, int> _last = {};

  /// Returns true and records the event if allowed now.
  bool tryAcquire(String key) {
    final now = clock();
    final last = _last[key];
    if (last != null && now - last < interval.inMilliseconds) return false;
    _last[key] = now;
    return true;
  }
}

/// Blocks a device after too many failed join attempts.
class AttemptBlocker {
  /// Creates a blocker.
  AttemptBlocker(
      {required this.maxAttempts,
      required this.blockTime,
      required this.clock});

  /// Failures allowed before blocking.
  final int maxAttempts;

  /// Block duration.
  final Duration blockTime;

  /// Clock.
  final Clock clock;
  final Map<String, List<int>> _fails = {};
  final Map<String, int> _blockedUntil = {};

  /// Whether [key] is blocked now.
  bool isBlocked(String key) {
    final until = _blockedUntil[key];
    if (until == null) return false;
    if (clock() >= until) {
      _blockedUntil.remove(key);
      _fails.remove(key);
      return false;
    }
    return true;
  }

  /// Records a failure; blocks after [maxAttempts] within the block window.
  void fail(String key) {
    final now = clock();
    final list = _fails.putIfAbsent(key, () => [])
      ..removeWhere((t) => now - t > blockTime.inMilliseconds)
      ..add(now);
    if (list.length >= maxAttempts) {
      _blockedUntil[key] = now + blockTime.inMilliseconds;
    }
  }

  /// Clears failures after a successful join.
  void succeed(String key) => _fails.remove(key);
}

/// Bot seat names.
const botNames = [
  'Raju', 'Meena', 'Arjun', 'Priya', 'Kumar', 'Lakshmi', 'Vikram', 'Anjali', //
];

/// Random room code: 4 digits locally, 6 characters online.
String newRoomCode(RandomSource rng, {required bool online}) {
  if (!online) {
    return (1000 + rng.nextInt(9000)).toString();
  }
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return List.generate(6, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
}

/// Random hex token.
String newToken(RandomSource rng, [int bytes = 16]) =>
    rng.nextBytes(bytes).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// How long clients take to show [events]: dice tumble, one hop per tile,
/// a card pop-up, money toasts. Keep in step with the app's board playback.
Duration animationTime(List<GameEvent> events) {
  var ms = 0;
  for (final e in events) {
    switch (e.type) {
      case 'rolled':
        ms += 900;
      case 'moved':
        final steps = (e.data['steps'] as int? ?? 0).abs();
        ms += 250 + steps * 200;
      case 'card':
        ms += 3000;
      case 'jailed':
        ms += 1000;
      case 'rent' ||
            'tax' ||
            'bought' ||
            'salary' ||
            'auction_won' ||
            'pot' ||
            'debt' ||
            'bankrupt':
        ms += 1300;
    }
  }
  return Duration(milliseconds: ms > 12000 ? 12000 : ms);
}
