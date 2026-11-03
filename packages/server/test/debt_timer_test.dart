import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';
import 'package:vyapari_server/vyapari_server.dart';

import 'support.dart';

void main() {
  test('a short payer who lets the timer run out has cash raised for them',
      () async {
    final hub = RoomHub(board: india(), config: testConfig);
    final room = hub.createRoom();
    final conns = <Connection>[];
    for (var i = 0; i < 3; i++) {
      final c = hub.connect(FakePeer('10.2.0.$i'));
      say(c, Hello(name: 'P$i', token: Token.values[i]), room: room.code);
      say(c, const ReadyMsg(ready: true));
      conns.add(c);
    }
    say(conns[0], const SetRulesMsg(HouseRules(turnTimerSec: 1)));
    say(conns[0], const SimpleIntent('start'));
    final mover = room.state.currentPlayer!;
    final debtor = room.state.players.firstWhere((p) => p.id != mover).id;

    // Next roll is a non-double 3, landing the mover on Undiyal (17) with
    // the wedding card on top; the debtor has ₹1,000 and one city.
    var seed = 0;
    while (true) {
      final r = FairDice(SeededRandomSource(seed)).roll();
      if (r.total == 3 && !r.isDouble) break;
      seed++;
    }
    room.dice = FairDice(SeededRandomSource(seed));
    var s = room.state;
    s = s.copyWith(
      players: [
        for (final p in s.players)
          p.id == mover
              ? p.copyWith(position: 14)
              : p.id == debtor
                  ? p.copyWith(cash: 1000)
                  : p,
      ],
      ownership: [Ownership(tileIndex: 5, ownerId: debtor)],
      decks: Decks(
          vaaippu: s.decks.vaaippu,
          undiyal: ['u07', ...s.decks.undiyal.where((c) => c != 'u07')]),
    );
    room.state = s;
    final total = s.totalMoney;
    say(conns.firstWhere((c) => c.playerId == mover),
        const SimpleIntent('roll'));
    expect(room.state.phase, GamePhase.raiseCash);
    expect(room.state.actingPlayer, debtor);

    // The debtor does nothing; after the 1 s timer the autopilot mortgages
    // the city and pays.
    for (var i = 0; i < 40 && room.state.phase == GamePhase.raiseCash; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(room.state.phase, GamePhase.manage);
    expect(room.state.currentPlayer, mover);
    expect(room.state.ownershipOf(5)!.mortgaged, isTrue);
    expect(room.state.player(debtor)!.cash, 1000 + 100000 - 50000);
    expect(room.state.totalMoney, total);
    hub.dispose();
  });
}
