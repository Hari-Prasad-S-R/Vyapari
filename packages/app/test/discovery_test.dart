import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:vyapari_app/services/platform_io.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_server/vyapari_server.dart';

NearbyHost host(String code, int port, Found via,
        {int players = 0, String ip = '192.168.43.1'}) =>
    NearbyHost(
      name: 'Game $code',
      code: code,
      ip: ip,
      port: port,
      players: players,
      maxPlayers: 8,
      hasPassword: false,
      via: {via},
    );

void main() {
  test('a host heard over UDP and mDNS appears once, with the live count', () {
    final merged = mergeNearby(
      [host('4821', 47800, Found.udp, players: 3)],
      [
        host('4821', 47800, Found.mdns),
        host('1111', 47800, Found.mdns, ip: '10.0.0.5')
      ],
    );
    expect(merged, hasLength(2));
    final both = merged.firstWhere((g) => g.code == '4821');
    expect(both.players, 3);
    expect(both.via, {Found.udp, Found.mdns});
    final onlyMdns = merged.firstWhere((g) => g.code == '1111');
    expect(onlyMdns.via, {Found.mdns});
    expect(onlyMdns.ip, '10.0.0.5');
  });

  test('UDP-only hosts are kept (Android hotspot without multicast)', () {
    final merged =
        mergeNearby([host('9999', 47800, Found.udp, players: 2)], const []);
    expect(merged.single.via, {Found.udp});
  });

  test('QR join links parse', () {
    final l =
        parseJoinUri('vyapari://join?ip=192.168.43.1&port=47800&code=4821')!;
    expect(l.ip, '192.168.43.1');
    expect(l.port, 47800);
    expect(l.code, '4821');
    expect(parseJoinUri('https://example.com'), isNull);
  });

  group('host IP choice', () {
    test('Wi-Fi beats mobile data even when mobile data is listed first', () {
      expect(
          pickLanIp([
            ('rmnet_data0', '10.45.12.9'), // carrier address
            ('wlan0', '192.168.68.57'),
          ]),
          '192.168.68.57');
    });

    test('hotspot interface is used when hosting a hotspot', () {
      expect(
          pickLanIp([
            ('ccmni1', '10.20.30.40'),
            ('swlan0', '192.168.43.1'),
          ]),
          '192.168.43.1');
    });

    test('iPhone personal hotspot bridge, not cellular', () {
      expect(
          pickLanIp([
            ('pdp_ip0', '10.1.2.3'),
            ('bridge100', '172.20.10.1'),
          ]),
          '172.20.10.1');
    });

    test('only mobile data: nothing to offer', () {
      expect(pickLanIp([('rmnet_data0', '10.45.12.9')]), isNull);
    });
  });

  test('scan covers the whole /22 a mesh router uses, own /24 first', () {
    final t = lanScanTargets('192.168.68.65');
    expect(t.first, '192.168.68.1');
    expect(t, contains('192.168.71.254'));
    expect(t, isNot(contains('192.168.68.65')));
    expect(t, isNot(contains('192.168.72.1')));
    expect(t.length, 4 * 254 - 1);
    expect(lanScanTargets('not an ip'), isEmpty);
  });

  test('scan results merge with mDNS and keep the live player count', () {
    final merged = mergeNearby(
      const [],
      [host('4821', 47800, Found.mdns)],
      [host('4821', 47800, Found.scan, players: 4)],
    );
    expect(merged.single.players, 4);
    expect(merged.single.via, {Found.mdns, Found.scan});
  });

  test('a Wi-Fi scan finds a real local host without any broadcast', () async {
    final board = BoardData.parse(
      File('assets/boards/india/board.json').readAsStringSync(),
      File('assets/boards/india/cards.json').readAsStringSync(),
    );
    final server = GameServer(board: board);
    final port =
        await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    final room = server.hub.createRoom(password: 'chai');
    addTearDown(server.stop);
    final found = await scanLan(['127.0.0.2', '127.0.0.1'], port: port);
    expect(found.single.code, room.code);
    expect(found.single.ip, '127.0.0.1');
    expect(found.single.hasPassword, isTrue);
    expect(found.single.via, {Found.scan});
  });
}
