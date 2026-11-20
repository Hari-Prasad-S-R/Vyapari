/// How a nearby game was found.
enum Found {
  /// UDP broadcast announcement.
  udp,

  /// mDNS / Bonjour.
  mdns,

  /// Direct scan of the Wi-Fi for a host (works when routers block
  /// broadcasts, as many mesh systems do).
  scan,
}

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

/// Merges games heard over UDP, mDNS and a Wi-Fi scan. The same host (room
/// code + port) appears once; UDP or scan data wins over mDNS because it
/// carries the live player count.
List<NearbyHost> mergeNearby(List<NearbyHost> udp, List<NearbyHost> mdns,
    [List<NearbyHost> scan = const []]) {
  final out = <String, NearbyHost>{};
  for (final g in [...mdns, ...scan]) {
    final key = '${g.code}:${g.port}';
    final other = out[key];
    out[key] = NearbyHost(
      name: g.name,
      code: g.code,
      ip: g.ip,
      port: g.port,
      players: g.via.contains(Found.mdns) && other != null
          ? other.players
          : g.players,
      maxPlayers: g.maxPlayers,
      hasPassword: g.hasPassword,
      via: {...g.via, ...?other?.via},
    );
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

/// Interface names that carry mobile data, VPNs or virtual links, never the
/// Wi-Fi or hotspot players join through.
final _notLan = RegExp(
    r'^(rmnet|ccmni|pdp_ip|clat|v4-rmnet|tun|ppp|dummy|ipsec|utun|ifb|vEthernet|docker|veth|br-)',
    caseSensitive: false);

/// Interface names of Wi-Fi and hotspot links (Android, iOS, desktop).
final _lanFirst = RegExp(
    r'^(wlan|swlan|ap|softap|wifi|wl|en0|bridge|Wi-?Fi|Ethernet|eth)',
    caseSensitive: false);

/// Picks the address other phones should use to reach this device from a
/// list of (interface name, IPv4 address). Mobile-data addresses (often a
/// carrier 10.x address) are skipped; Wi-Fi/hotspot interfaces come first,
/// then 192.168.x, then other private ranges.
String? pickLanIp(List<(String, String)> candidates) {
  int score((String, String) c) {
    final (name, ip) = c;
    if (_notLan.hasMatch(name)) return -1;
    if (ip.startsWith('127.') || ip.startsWith('169.254.')) return -1;
    var s = 0;
    if (_lanFirst.hasMatch(name)) s += 10;
    if (ip.startsWith('192.168.')) {
      s += 5;
    } else if (ip.startsWith('172.')) {
      s += 3;
    } else if (ip.startsWith('10.')) {
      s += 2;
    }
    return s;
  }

  final ranked = candidates.where((c) => score(c) >= 0).toList()
    ..sort((a, b) => score(b).compareTo(score(a)));
  return ranked.isEmpty ? null : ranked.first.$2;
}

/// Addresses to probe for a host when broadcasts are blocked: the /22 block
/// around [ownIp] (covers home routers using /24 and mesh systems such as
/// TP-Link Deco that use 192.168.68.0/22), minus [ownIp] itself.
List<String> lanScanTargets(String ownIp) {
  final parts = ownIp.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return const [];
  final a = parts[0]!, b = parts[1]!, c = parts[2]!;
  final base = c & ~3;
  final out = <String>[];
  // Own /24 first, so the usual case is found fastest.
  for (final third in [
    c,
    for (var k = base; k < base + 4; k++)
      if (k != c) k
  ]) {
    for (var d = 1; d < 255; d++) {
      final ip = '$a.$b.$third.$d';
      if (ip != ownIp) out.add(ip);
    }
  }
  return out;
}
