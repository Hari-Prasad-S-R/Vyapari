/// A game found on the local network.
class NearbyHost {
  /// Creates an entry.
  const NearbyHost({
    required this.name,
    required this.code,
    required this.ip,
    required this.port,
    required this.players,
    required this.maxPlayers,
    required this.hasPassword,
  });

  /// Room name.
  final String name;

  /// Room code.
  final String code;

  /// Host IP.
  final String ip;

  /// Port.
  final int port;

  /// Seated players.
  final int players;

  /// Seat limit.
  final int maxPlayers;

  /// Password needed.
  final bool hasPassword;
}

/// A server running on this device.
class LocalHostHandle {
  /// Creates a handle.
  LocalHostHandle({
    required this.code,
    required this.ip,
    required this.port,
    required this.stop,
  });

  /// Room code.
  final String code;

  /// This device's LAN IP (null if no network).
  final String? ip;

  /// Port.
  final int port;

  /// Stops server, discovery and the foreground service.
  final Future<void> Function() stop;

  /// Join link encoded in the lobby QR code.
  Uri get joinUri => Uri(scheme: 'vyapari', host: 'join', queryParameters: {
        'ip': ip ?? '127.0.0.1',
        'port': '$port',
        'code': code
      });
}

/// Parses a `vyapari://join?ip=…&port=…&code=…` link.
({String ip, int port, String code})? parseJoinUri(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null || uri.scheme != 'vyapari' || uri.host != 'join') return null;
  final ip = uri.queryParameters['ip'];
  final code = uri.queryParameters['code'];
  final port = int.tryParse(uri.queryParameters['port'] ?? '') ?? 47800;
  if (ip == null || code == null) return null;
  return (ip: ip, port: port, code: code);
}
