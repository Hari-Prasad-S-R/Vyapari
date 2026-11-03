import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vyapari_protocol/vyapari_protocol.dart';

/// UDP discovery port.
const discoveryPort = 47801;

/// A game announced on the local network.
class NearbyGame {
  /// Creates an entry.
  const NearbyGame({
    required this.name,
    required this.code,
    required this.ip,
    required this.port,
    required this.players,
    required this.maxPlayers,
    required this.version,
    required this.hasPassword,
    required this.lastHeard,
  });

  /// Host's room name.
  final String name;

  /// Room code.
  final String code;

  /// Host address.
  final String ip;

  /// WebSocket port.
  final int port;

  /// Seated players.
  final int players;

  /// Seat limit.
  final int maxPlayers;

  /// Protocol version.
  final int version;

  /// Whether a password is needed.
  final bool hasPassword;

  /// When the last announcement arrived (ms since epoch).
  final int lastHeard;

  /// Join link for QR codes.
  Uri get joinUri => Uri(
      scheme: 'vyapari',
      host: 'join',
      queryParameters: {'ip': ip, 'port': '$port', 'code': code});
}

/// Broadcasts this host's game every [interval].
class DiscoveryAnnouncer {
  /// Creates an announcer; [info] is read on every broadcast.
  DiscoveryAnnouncer({
    required this.info,
    this.interval = const Duration(seconds: 2),
    this.targetPort = discoveryPort,
    InternetAddress? target,
  }) : target = target ?? InternetAddress('255.255.255.255');

  /// Current announcement fields (name, code, port, players, maxPlayers,
  /// hasPassword).
  final Map<String, Object?> Function() info;

  /// Broadcast period.
  final Duration interval;

  /// Destination port.
  final int targetPort;

  /// Destination address (broadcast by default).
  final InternetAddress target;

  RawDatagramSocket? _socket;
  Timer? _timer;

  /// Starts announcing.
  Future<void> start() async {
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    s.broadcastEnabled = true;
    _socket = s;
    _send();
    _timer = Timer.periodic(interval, (_) => _send());
  }

  void _send() {
    final payload = utf8.encode(jsonEncode({
      'app': 'vyapari',
      'v': protocolVersion,
      ...info(),
    }));
    try {
      _socket?.send(payload, target, targetPort);
    } catch (_) {
      // Network may be down (e.g. hotspot not on yet); try again next tick.
    }
  }

  /// Stops announcing.
  void stop() {
    _timer?.cancel();
    _socket?.close();
    _socket = null;
  }
}

/// Listens for announcements and keeps a list of games heard recently.
class DiscoveryListener {
  /// Creates a listener.
  DiscoveryListener({
    this.port = discoveryPort,
    this.expiry = const Duration(seconds: 6),
  });

  /// Port to listen on.
  final int port;

  /// Games not heard for this long are dropped.
  final Duration expiry;

  final Map<String, NearbyGame> _games = {};
  final _controller = StreamController<List<NearbyGame>>.broadcast();
  RawDatagramSocket? _socket;
  Timer? _prune;

  /// Current list, updated on every change.
  Stream<List<NearbyGame>> get games => _controller.stream;

  /// Snapshot of current games.
  List<NearbyGame> get current => _games.values.toList();

  /// Starts listening.
  Future<void> start() async {
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port,
        reuseAddress: true);
    _socket = s;
    s.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = s.receive();
      if (d == null) return;
      _handle(d.data, d.address.address);
    });
    _prune = Timer.periodic(const Duration(seconds: 1), (_) => _expire());
  }

  void _handle(List<int> data, String ip) {
    try {
      final m = jsonDecode(utf8.decode(data));
      if (m is! Map || m['app'] != 'vyapari') return;
      final g = NearbyGame(
        name: m['name'] as String? ?? 'Vyapari game',
        code: m['code'] as String,
        ip: ip,
        port: m['port'] as int? ?? 47800,
        players: m['players'] as int? ?? 0,
        maxPlayers: m['maxPlayers'] as int? ?? 8,
        version: m['v'] as int? ?? 0,
        hasPassword: m['hasPassword'] as bool? ?? false,
        lastHeard: DateTime.now().millisecondsSinceEpoch,
      );
      _games['$ip:${g.port}:${g.code}'] = g;
      _controller.add(current);
    } catch (_) {
      // Ignore foreign or malformed datagrams.
    }
  }

  void _expire() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final before = _games.length;
    _games.removeWhere((_, g) => now - g.lastHeard > expiry.inMilliseconds);
    if (_games.length != before) _controller.add(current);
  }

  /// Stops listening.
  Future<void> stop() async {
    _prune?.cancel();
    _socket?.close();
    await _controller.close();
  }
}
