import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_server/vyapari_server.dart';

import 'platform_api.dart';

export 'platform_api.dart';

/// Android and iOS can host; desktop builds can too.
bool get canHost => true;

/// LAN discovery is available.
bool get canDiscover => true;

/// QR scanning needs a camera (phones only).
bool get canScan => Platform.isAndroid || Platform.isIOS;

/// Best LAN IPv4 of this device (hotspot or Wi-Fi), or `null`. Mobile-data
/// interfaces are skipped so the lobby never shows a carrier address.
Future<String?> localIp() async {
  try {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return pickLanIp([
      for (final i in ifaces)
        for (final a in i.addresses) (i.name, a.address),
    ]);
  } catch (_) {
    return null;
  }
}

/// Android drops Wi-Fi broadcast and multicast packets unless an app holds a
/// multicast lock; discovery (UDP + mDNS) needs it while listening/hosting.
Future<void> _multicastLock(bool on) async {
  if (!Platform.isAndroid) return;
  try {
    await const MethodChannel('vyapari/settings')
        .invokeMethod<void>('multicastLock', on);
  } catch (_) {}
}

/// Probes [targets] for a Vyapari host on [port] by asking for `/local`.
/// Works on networks that block broadcasts (many mesh routers), because it
/// only uses ordinary direct connections.
Future<List<NearbyHost>> scanLan(List<String> targets,
    {int port = 47800, int parallel = 48}) async {
  final found = <NearbyHost>[];
  final client = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 700);
  var next = 0;
  Future<void> worker() async {
    while (next < targets.length) {
      final ip = targets[next++];
      try {
        final req = await client
            .get(ip, port, '/local')
            .timeout(const Duration(milliseconds: 900));
        final res = await req.close().timeout(const Duration(seconds: 2));
        if (res.statusCode != 200) {
          await res.drain<void>();
          continue;
        }
        final body = jsonDecode(await res.transform(utf8.decoder).join());
        if (body is! Map || body['app'] != 'vyapari') continue;
        for (final r in (body['rooms'] as List? ?? const [])) {
          if (r is! Map) continue;
          final host = r['host'] as String?;
          found.add(NearbyHost(
            name: host == null ? 'Vyapari game' : "$host's game",
            code: r['code'] as String,
            ip: ip,
            port: port,
            players: r['players'] as int? ?? 0,
            maxPlayers: r['maxPlayers'] as int? ?? 8,
            hasPassword: r['hasPassword'] as bool? ?? false,
            via: const {Found.scan},
          ));
        }
      } catch (_) {
        // Nothing listening there.
      }
    }
  }

  await Future.wait([for (var k = 0; k < parallel; k++) worker()]);
  client.close(force: true);
  return found;
}

/// Whether any Wi-Fi/hotspot network is up.
Future<bool> hasLocalNetwork() async => (await localIp()) != null;

/// Opens Android's tethering settings (iOS has no public deep link).
Future<void> openHotspotSettings() async {
  if (!Platform.isAndroid) return;
  try {
    await const MethodChannel('vyapari/settings')
        .invokeMethod<void>('openHotspot');
  } catch (_) {}
}

Future<void> _startForegroundService() async {
  if (!Platform.isAndroid) return;
  try {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'vyapari_host',
        channelName: 'Hosting a game',
        channelDescription:
            'Keeps your Vyapari game running for other players.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions:
          const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    await FlutterForegroundTask.requestNotificationPermission();
    await FlutterForegroundTask.startService(
      serviceId: 4780,
      notificationTitle: 'Vyapari game running',
      notificationText: 'Friends can join while your screen is off',
    );
  } catch (_) {
    // Hosting still works while the app is open.
  }
}

Future<void> _stopForegroundService() async {
  if (!Platform.isAndroid) return;
  try {
    await FlutterForegroundTask.stopService();
  } catch (_) {}
}

/// Starts the game server on this device (port 47800), a room, LAN
/// announcements and (Android) a foreground service.
Future<LocalHostHandle> startLocalHost({
  required BoardData board,
  required String roomName,
  String? password,
  String? resumeCode,
}) async {
  Directory saves;
  try {
    saves = Directory('${(await getApplicationSupportDirectory()).path}/saves');
  } catch (_) {
    saves = Directory('${Directory.systemTemp.path}/vyapari_saves');
  }
  final server = GameServer(board: board, store: JsonFileStore(saves));
  var port = defaultPort;
  try {
    port = await server.start(port: defaultPort);
  } on SocketException {
    port = await server.start(port: 0);
  }
  // After an app restart the host resumes its saved room (same code, same
  // seats) so everyone can rejoin with their session tokens.
  Room? resumed;
  if (resumeCode != null) {
    try {
      resumed = server.hub.resume(resumeCode);
    } catch (_) {}
  }
  final room = resumed ?? server.hub.createRoom(password: password);
  final announcer = DiscoveryAnnouncer(
      info: () => {
            'name': roomName,
            'code': room.code,
            'port': port,
            'players': room.state.players.length,
            'maxPlayers': room.state.config.maxPlayers,
            'hasPassword': password != null && password.isNotEmpty,
          });
  await _multicastLock(true);
  try {
    await announcer.start();
  } catch (_) {}
  // Also announce over mDNS/Bonjour: iPhones and some routers only see this.
  BonsoirBroadcast? mdns;
  try {
    mdns = BonsoirBroadcast(
      service: BonsoirService(
        name: '$roomName ${room.code}',
        type: mdnsServiceType,
        port: port,
        attributes: {
          'code': room.code,
          'name': roomName,
          'max': '${room.state.config.maxPlayers}',
          'pw': password != null && password.isNotEmpty ? '1' : '0',
        },
      ),
    );
    await mdns.initialize();
    await mdns.start();
  } catch (_) {
    mdns = null; // UDP broadcast still works.
  }
  await _startForegroundService();
  return LocalHostHandle(
    code: room.code,
    ip: await localIp(),
    port: port,
    stop: () async {
      announcer.stop();
      await _multicastLock(false);
      try {
        await mdns?.stop();
      } catch (_) {}
      await server.stop();
      await _stopForegroundService();
    },
  );
}

/// Games announced on the LAN over UDP broadcast and mDNS, merged and
/// refreshed as they come and go.
Stream<List<NearbyHost>> discoverNearby() {
  late StreamController<List<NearbyHost>> c;
  DiscoveryListener? listener;
  StreamSubscription<List<NearbyGame>>? udpSub;
  BonsoirDiscovery? mdns;
  StreamSubscription<BonsoirDiscoveryEvent>? mdnsSub;
  var udp = <NearbyHost>[];
  final viaMdns = <String, NearbyHost>{};
  var viaScan = <NearbyHost>[];
  Timer? rescan;
  var scanning = false;
  void emit() {
    if (!c.isClosed) {
      c.add(mergeNearby(udp, viaMdns.values.toList(), viaScan));
    }
  }

  Future<void> scanOnce() async {
    if (scanning || c.isClosed) return;
    scanning = true;
    try {
      final ip = await localIp();
      if (ip != null) {
        viaScan = await scanLan(lanScanTargets(ip));
        emit();
      }
    } finally {
      scanning = false;
    }
  }

  c = StreamController<List<NearbyHost>>(
    onListen: () async {
      var anyStarted = false;
      await _multicastLock(true);
      // Broadcasts may never arrive on mesh Wi-Fi: scan directly as well.
      unawaited(scanOnce());
      rescan = Timer.periodic(const Duration(seconds: 15), (_) => scanOnce());
      try {
        listener = DiscoveryListener();
        await listener!.start();
        anyStarted = true;
        udpSub = listener!.games.listen((games) {
          udp = [
            for (final g in games)
              NearbyHost(
                name: g.name,
                code: g.code,
                ip: g.ip,
                port: g.port,
                players: g.players,
                maxPlayers: g.maxPlayers,
                hasPassword: g.hasPassword,
              ),
          ];
          emit();
        });
      } catch (_) {
        // UDP port busy or blocked; rely on mDNS.
      }
      try {
        mdns = BonsoirDiscovery(type: mdnsServiceType);
        await mdns!.initialize();
        mdnsSub = mdns!.eventStream!.listen((event) {
          switch (event) {
            case BonsoirDiscoveryServiceFoundEvent():
              event.service.resolve(mdns!.serviceResolver);
            case BonsoirDiscoveryServiceResolvedEvent():
              final host = _fromMdns(event.service);
              if (host != null) {
                viaMdns[event.service.name] = host;
                emit();
              }
            case BonsoirDiscoveryServiceLostEvent():
              if (viaMdns.remove(event.service.name) != null) emit();
            default:
              break;
          }
        });
        await mdns!.start();
        anyStarted = true;
      } catch (_) {
        // mDNS unavailable on this device; UDP may still work.
      }
      // The Wi-Fi scan still runs even if UDP and mDNS could not start.
      if (!anyStarted) emit();
    },
    onCancel: () async {
      rescan?.cancel();
      await _multicastLock(false);
      await udpSub?.cancel();
      await listener?.stop();
      await mdnsSub?.cancel();
      try {
        await mdns?.stop();
      } catch (_) {}
    },
  );
  return c.stream;
}

NearbyHost? _fromMdns(BonsoirService s) {
  final code = s.attributes['code'];
  // Prefer an IPv4 address: it is what hotspots and the QR link use.
  final ip = s.hostAddresses.firstWhere(
    (a) => InternetAddress.tryParse(a)?.type == InternetAddressType.IPv4,
    orElse: () => s.hostAddresses.isEmpty ? '' : s.hostAddresses.first,
  );
  if (code == null || ip.isEmpty) return null;
  return NearbyHost(
    name: s.attributes['name'] ?? s.name,
    code: code,
    ip: ip,
    port: s.port,
    players: 0,
    maxPlayers: int.tryParse(s.attributes['max'] ?? '') ?? 8,
    hasPassword: s.attributes['pw'] == '1',
    via: const {Found.mdns},
  );
}
