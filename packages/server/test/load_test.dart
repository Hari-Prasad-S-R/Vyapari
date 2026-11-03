@Tags(['load'])
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';
import 'package:vyapari_server/vyapari_server.dart';

import 'support.dart';

/// Online capacity (NFR-8 / VY-35): N rooms on one server, each with one
/// WebSocket client and 3 bots, all playing at once.
/// Run: `VYAPARI_LOAD_ROOMS=1000 dart test -t load`.
void main() {
  final rooms =
      int.tryParse(Platform.environment['VYAPARI_LOAD_ROOMS'] ?? '') ?? 200;

  test('$rooms concurrent rooms finish with no errors', () async {
    final server = GameServer(
      board: india(),
      config: const ServerConfig(
        online: true,
        botDelay: Duration.zero,
        auctionTime: Duration(milliseconds: 100),
        tradeReviewDelay: Duration.zero,
        maxRooms: 5000,
      ),
    );
    final port =
        await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    final sw = Stopwatch()..start();
    final clients = <TestClient>[];
    for (var i = 0; i < rooms; i++) {
      final c = await TestClient.connect(port, 'L$i');
      c.send(const Hello(name: 'Load', token: Token.kite, create: true));
      clients.add(c);
    }
    for (final c in clients) {
      await c.waitFor(() => c.playerId != null,
          timeout: const Duration(seconds: 60));
      c.send(const SetRulesMsg(HouseRules(maxTurns: 40, turnTimerSec: 0)));
      for (var b = 0; b < 3; b++) {
        c.send(const AddBotMsg());
      }
    }
    for (final c in clients) {
      await c.waitFor(() => c.state!.players.length == 4,
          timeout: const Duration(seconds: 60));
      c.send(const SimpleIntent('start'));
      c.autoplay(MediumBot(SeededRandomSource(clients.indexOf(c))));
    }
    for (final c in clients) {
      await c.waitFor(() => c.state!.phase == GamePhase.gameOver,
          timeout: const Duration(minutes: 10));
    }
    sw.stop();
    final errors = clients.expand((c) => c.errors).toList();
    final byCode = <String, int>{};
    for (final e in errors) {
      byCode[e.code.wire] = (byCode[e.code.wire] ?? 0) + 1;
    }
    final leaks = clients
        .where((c) => c.state!.totalMoney != c.state!.startingTotal)
        .length;
    // ignore: avoid_print
    print('rooms=$rooms finished in ${sw.elapsed.inSeconds}s, '
        'rejected intents=$byCode, money leaks=$leaks, '
        'server rooms=${server.hub.rooms.length}');
    expect(server.hub.rooms.length, rooms);
    expect(leaks, 0);
    // Headless clients race the bots, so some intents arrive stale; the
    // server must refuse those with a rule reason — never anything else.
    const stale = {
      ErrorCode.illegalPhase,
      ErrorCode.invalidAction,
      ErrorCode.notYourTurn,
      ErrorCode.unevenBuild,
      ErrorCode.insufficientFunds,
      ErrorCode.notFound,
      ErrorCode.tradeInvalid,
    };
    expect(errors.where((e) => !stale.contains(e.code)), isEmpty);
    for (final c in clients) {
      await c.close();
    }
    await server.stop();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
