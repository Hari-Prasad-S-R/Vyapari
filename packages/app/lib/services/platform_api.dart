/// How a nearby game was found.
enum Found { udp, mdns }

/// mDNS / Bonjour service type for Vyapari hosts.
const mdnsServiceType = '_vyapari._tcp';

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
    this.via = const {Found.udp},
  });

  /// Discovery methods that heard this host.
  final Set<Found> via;

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

/// Merges games heard over UDP and mDNS. The same host (room code + port)
/// appears once; UDP data wins because it carries the live player count.
List<NearbyHost> mergeNearby(List<NearbyHost> udp, List<NearbyHost> mdns) {
  final out = <String, NearbyHost>{};
  for (final g in mdns) {
    out['${g.code}:${g.port}'] = g;
  }
  for (final g in udp) {
    final key = '${g.code}:${g.port}';
    final other = out[key];
    out[key] = NearbyHost(
      name: g.name,
      code: g.code,
      ip: g.ip,
      port: g.port,
      players: g.players,
      maxPlayers: g.maxPlayers,
      hasPassword: g.hasPassword,
      via: {...g.via, ...?other?.via},
    );
  }
  final list = out.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  return list;
}
