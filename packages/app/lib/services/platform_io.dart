import 'dart:async';
import 'dart:io';

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

/// Best LAN IPv4 of this device (hotspot or Wi-Fi), or `null`.
Future<String?> localIp() async {
  try {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    String? fallback;
    for (final i in ifaces) {
      for (final a in i.addresses) {
        if (a.isLoopback || a.isLinkLocal) continue;
        final ip = a.address;
        // Prefer private LAN ranges (hotspots use 192.168.x / 172.20.x).
        if (ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            ip.startsWith('172.')) {
          return ip;
        }
        fallback ??= ip;
      }
    }
    return fallback;
  } catch (_) {
    return null;
  }
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
  final room = server.hub.createRoom(password: password);
  final announcer = DiscoveryAnnouncer(
      info: () => {
            'name': roomName,
            'code': room.code,
            'port': port,
            'players': room.state.players.length,
            'maxPlayers': room.state.config.maxPlayers,
            'hasPassword': password != null && password.isNotEmpty,
          });
  try {
    await announcer.start();
  } catch (_) {}
  await _startForegroundService();
  return LocalHostHandle(
    code: room.code,
    ip: await localIp(),
    port: port,
    stop: () async {
      announcer.stop();
      await server.stop();
      await _stopForegroundService();
    },
  );
}

/// Games announced on the LAN, refreshed as they come and go.
Stream<List<NearbyHost>> discoverNearby() {
  late StreamController<List<NearbyHost>> c;
  DiscoveryListener? listener;
  StreamSubscription<List<NearbyGame>>? sub;
  c = StreamController<List<NearbyHost>>(
    onListen: () async {
      listener = DiscoveryListener();
      try {
        await listener!.start();
        sub = listener!.games.listen((games) => c.add([
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
            ]));
      } catch (e) {
        c.addError(e);
      }
    },
    onCancel: () async {
      await sub?.cancel();
      await listener?.stop();
    },
  );
  return c.stream;
}
