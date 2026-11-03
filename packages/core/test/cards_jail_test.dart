import 'package:test/test.dart';
import 'package:vyapari_core/vyapari_core.dart';

import 'helpers.dart';

/// Lands p0 on a card tile of [deck] with [cardId] on top.
GameState drawFor(GameState s, Deck deck, String cardId) {
  s = withTopCard(s, deck, cardId);
  // Vaaippu on 7 (from 4), Undiyal on 17 (from 14); roll 1 + 2.
  final from = deck == Deck.vaaippu ? 4 : 14;
  s = withPlayer(s, 'p0', (p) => p.copyWith(position: from));
  return ok(const Roll('p0', 1, 2), s);
}

void main() {
  group('every card in cards.json', () {
    final board = india();
    for (final card in board.cards) {
      test('${card.id}: ${card.effect.type.name}', () {
        var s = startedGame(n: 3);
        if (card.effect.type == CardEffectType.repairs) {
          s = withOwned(s, 'p0', [1, 3], houses: 2);
          s = withOwned(s, 'p0', [37, 39], houses: 5);
        }
        final before = s;
        s = drawFor(s, card.deck, card.id);
        expect(s.totalMoney, s.startingTotal);
        final e = card.effect;
        final p0 = s.player('p0')!;
        final start = before.player('p0')!.cash;
        final from = card.deck == Deck.vaaippu ? 7 : 17;
        switch (e.type) {
          case CardEffectType.collect:
            expect(p0.cash, start + e.amount);
          case CardEffectType.pay:
            expect(p0.cash, start - e.amount);
          case CardEffectType.payEachPlayer:
            expect(p0.cash, start - 2 * e.amount);
            expect(cash(s, 'p1'), cash(before, 'p1') + e.amount);
          case CardEffectType.collectFromEachPlayer:
            expect(p0.cash, start + 2 * e.amount);
          case CardEffectType.moveTo:
            expect(p0.position, e.target);
            final passed = e.target < from;
            if (passed) expect(p0.cash, greaterThanOrEqualTo(start + 200000));
          case CardEffectType.moveBack:
            expect(p0.position, (from - e.target + 40) % 40);
          case CardEffectType.goToJail:
            expect(p0.inJail, isTrue);
            expect(p0.position, 10);
          case CardEffectType.getOutOfJail:
            expect(p0.getOutCards, [card.id]);
            final deck =
                card.deck == Deck.vaaippu ? s.decks.vaaippu : s.decks.undiyal;
            expect(deck, isNot(contains(card.id)));
          case CardEffectType.repairs:
            expect(p0.cash, start - 4 * e.perHouse - 2 * e.perHotel);
        }
      });
    }
  });

  test('move to Start collects salary', () {
    var s = startedGame();
    final before = cash(s, 'p0');
    s = drawFor(s, Deck.vaaippu, 'v01');
    expect(s.player('p0')!.position, 0);
    expect(cash(s, 'p0'), before + 200000);
  });

  test('held get-out card is not drawn until used', () {
    var s = startedGame();
    s = drawFor(s, Deck.vaaippu, 'v08');
    expect(s.decks.vaaippu, hasLength(15));
    expect(s.decks.vaaippu, isNot(contains('v08')));
    s = ok(const EndTurn('p0'), s);
    // Cycle the deck fully: drawn cards go to the bottom, v08 never appears.
    for (var i = 0; i < 20; i++) {
      expect(s.decks.vaaippu.first, isNot('v08'));
      s = s.copyWith(
          decks: Decks(
              vaaippu: [...s.decks.vaaippu.skip(1), s.decks.vaaippu.first],
              undiyal: s.decks.undiyal));
    }
    // Use it from jail: it returns to the bottom of the deck.
    s = s.copyWith(currentPlayer: 'p0', phase: GamePhase.awaitingRoll);
    s = withPlayer(s, 'p0', (p) => p.copyWith(inJail: true, position: 10));
    s = ok(const UseJailCard('p0'), s);
    expect(s.player('p0')!.inJail, isFalse);
    expect(s.decks.vaaippu.last, 'v08');
  });

  test('deck order repeats with a fixed seed', () {
    expect(startedGame().decks.vaaippu, startedGame().decks.vaaippu);
  });

  group('jail', () {
    GameState jailed({int tries = 0}) {
      final s = startedGame(rules: const HouseRules(auctions: false));
      return withPlayer(s, 'p0',
          (p) => p.copyWith(inJail: true, position: 10, jailTurns: tries));
    }

    test('doubles in jail: leave and move, no extra roll', () {
      var s = jailed();
      s = ok(const Roll('p0', 2, 2), s);
      expect(s.player('p0')!.inJail, isFalse);
      expect(s.player('p0')!.position, 14);
      expect(s.rollAgain, isFalse);
    });

    test('failed try stays in jail and ends the turn', () {
      var s = jailed();
      s = ok(const Roll('p0', 1, 2), s);
      expect(s.player('p0')!.inJail, isTrue);
      expect(s.player('p0')!.jailTurns, 1);
      expect(s.phase, GamePhase.manage);
      s = ok(const EndTurn('p0'), s);
    });

    test('third failed try pays the fine and moves by that roll', () {
      var s = jailed(tries: 2);
      final before = cash(s, 'p0');
      s = ok(const Roll('p0', 1, 2), s);
      expect(s.player('p0')!.inJail, isFalse);
      expect(s.player('p0')!.position, 13);
      expect(cash(s, 'p0'), before - 50000);
    });

    test('pay fine or use card, then roll normally', () {
      var s = jailed();
      final before = cash(s, 'p0');
      s = ok(const PayJailFine('p0'), s);
      expect(cash(s, 'p0'), before - 50000);
      expect(s.phase, GamePhase.awaitingRoll);
      s = ok(const Roll('p0', 1, 2), s);
      expect(s.player('p0')!.position, 13);

      var t = jailed();
      expect(apply(const UseJailCard('p0'), t).error, ErrorCode.invalidAction);
      t = withPlayer(t, 'p0', (p) => p.copyWith(getOutCards: ['u05']));
      t = t.copyWith(
          decks: Decks(
              vaaippu: t.decks.vaaippu,
              undiyal: t.decks.undiyal.where((c) => c != 'u05').toList()));
      t = ok(const UseJailCard('p0'), t);
      expect(t.player('p0')!.inJail, isFalse);
    });

    test('just visiting does nothing', () {
      var s = startedGame();
      s = withPlayer(s, 'p0', (p) => p.copyWith(position: 7));
      final before = cash(s, 'p0');
      s = ok(const Roll('p0', 1, 2), s);
      expect(s.player('p0')!.position, 10);
      expect(s.player('p0')!.inJail, isFalse);
      expect(cash(s, 'p0'), before);
    });
  });
}
