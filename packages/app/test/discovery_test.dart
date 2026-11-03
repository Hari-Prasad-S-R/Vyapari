import 'package:flutter_test/flutter_test.dart';
import 'package:vyapari_app/services/platform_api.dart';

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
}
