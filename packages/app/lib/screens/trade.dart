import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import '../state/game_controller.dart';
import '../ui.dart';

/// Rough value of a trade side: list prices, cash, ₹50,000 per card.
int sideValue(GameState s, TradeSide side) =>
    side.cash +
    side.cards * 50000 +
    side.tiles.fold(0, (v, i) => v + s.tiles[i].price);

/// Whether one side is worth more than 5× the other.
bool isLopsided(GameState s, TradeSide give, TradeSide get) {
  final a = sideValue(s, give);
  final b = sideValue(s, get);
  if (a == 0 && b == 0) return false;
  return a > 5 * b || b > 5 * a;
}

/// Build an offer: pick a player, then what I give and what I get.
class TradeScreen extends ConsumerStatefulWidget {
  /// Creates the screen; [counterOf] prefills a counter-offer.
  const TradeScreen({super.key, this.counterOf});

  /// Trade being countered.
  final Trade? counterOf;

  @override
  ConsumerState<TradeScreen> createState() => _TradeScreenState();
}

class _TradeScreenState extends ConsumerState<TradeScreen> {
  String? _to;
  final Set<int> _give = {};
  final Set<int> _get = {};
  int _giveCash = 0;
  int _getCash = 0;
  int _giveCards = 0;
  int _getCards = 0;

  @override
  void initState() {
    super.initState();
    final c = widget.counterOf;
    if (c != null) {
      // Counter from the receiver's view: swap the sides.
      _to = c.from;
      _give.addAll(c.get.tiles);
      _get.addAll(c.give.tiles);
      _giveCash = c.get.cash;
      _getCash = c.give.cash;
      _giveCards = c.get.cards;
      _getCards = c.give.cards;
    }
  }

  TradeSide get giveSide =>
      TradeSide(cash: _giveCash, tiles: _give.toList(), cards: _giveCards);
  TradeSide get getSide =>
      TradeSide(cash: _getCash, tiles: _get.toList(), cards: _getCards);

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(gameProvider);
    final s = view.state!;
    final me = view.myPlayer!;
    final others = s.players
        .where((p) => p.id != me.id && !p.bankrupt && p.connected)
        .toList();
    final them = s.player(_to);
    final offer =
        ProposeTrade(me.id, to: _to ?? '', give: giveSide, get: getSide);
    final valid = _to != null && apply(offer, s).ok;
    final lopsided = isLopsided(s, giveSide, getSide);

    Widget column(String title, Player? who, Set<int> picked, int cash,
        ValueChanged<int> onCash, int cards, ValueChanged<int> onCards) {
      final owned = who == null ? <Ownership>[] : s.ownedBy(who.id);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (who == null) const Text('Pick a player first'),
            for (final o in owned)
              Builder(builder: (context) {
                final t = s.tiles[o.tileIndex];
                final blocked = t.group != null &&
                    s.groupHasBuildings(t.group!) &&
                    t.type == TileType.city;
                return CheckboxListTile(
                  key: ValueKey('$title-${t.index}'),
                  dense: true,
                  value: picked.contains(t.index),
                  onChanged: blocked
                      ? null
                      : (v) => setState(() => v == true
                          ? picked.add(t.index)
                          : picked.remove(t.index)),
                  secondary: Container(
                      width: 10, height: 30, color: hexColor(t.color)),
                  title: Text(t.name),
                  subtitle: Text(blocked
                      ? 'Sell buildings first'
                      : '${formatRupees(t.price)}${o.mortgaged ? ' · mortgaged' : ''}'),
                );
              }),
            if (who != null) ...[
              Text('Cash: ${formatRupees(cash)}'),
              Slider(
                key: ValueKey('$title-cash'),
                value: min(cash, who.cash).toDouble(),
                max: max(1, who.cash).toDouble(),
                divisions: max(1, who.cash ~/ 10000),
                onChanged: (v) => onCash((v ~/ 10000) * 10000),
              ),
              if (who.getOutCards.isNotEmpty)
                Row(children: [
                  const Expanded(child: Text('Get-out-of-jail cards')),
                  IconButton(
                      onPressed: cards > 0 ? () => onCards(cards - 1) : null,
                      icon: const Icon(Icons.remove)),
                  Text('$cards'),
                  IconButton(
                      onPressed: cards < who.getOutCards.length
                          ? () => onCards(cards + 1)
                          : null,
                      icon: const Icon(Icons.add)),
                ]),
            ],
          ]),
        ),
      );
    }

    final give = column(
        'I give',
        me,
        _give,
        _giveCash,
        (v) => setState(() => _giveCash = v),
        _giveCards,
        (v) => setState(() => _giveCards = v));
    final get = column(
        'I get',
        them,
        _get,
        _getCash,
        (v) => setState(() => _getCash = v),
        _getCards,
        (v) => setState(() => _getCards = v));
    final wide = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.counterOf == null ? 'Propose a trade' : 'Counter-offer')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('trade-player'),
          initialValue: _to,
          decoration: const InputDecoration(
              labelText: 'Trade with', border: OutlineInputBorder()),
          items: [
            for (final p in others)
              DropdownMenuItem(
                  value: p.id, child: Text('${tokenEmoji(p.token)} ${p.name}')),
          ],
          onChanged: widget.counterOf != null
              ? null
              : (v) => setState(() {
                    _to = v;
                    _get.clear();
                    _getCash = 0;
                    _getCards = 0;
                  }),
        ),
        const SizedBox(height: 8),
        if (wide)
          Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: give), Expanded(child: get)])
        else ...[give, get],
        if (lopsided)
          const Card(
            key: ValueKey('lopsided-warning'),
            color: Color(0xFFFFF3E0),
            child: ListTile(
              leading: Icon(Icons.warning_amber, color: Colors.orange),
              title: Text('Lopsided deal'),
              subtitle: Text(
                  'One side is worth more than 5× the other. Double-check before sending.'),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('send-offer'),
          onPressed: valid
              ? () {
                  final game = ref.read(gameProvider.notifier);
                  final c = widget.counterOf;
                  game.send(c == null
                      ? TradeProposeMsg(to: _to!, give: giveSide, get: getSide)
                      : TradeCounterMsg(c.id, give: giveSide, get: getSide));
                  Navigator.pop(context);
                }
              : null,
          child: Text(
              widget.counterOf == null ? 'Send offer' : 'Send counter-offer'),
        ),
      ]),
    );
  }
}

/// Opens the review sheet for incoming trade [tradeId].
Future<void> showIncomingOffer(BuildContext context, String tradeId) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OfferReview(tradeId: tradeId),
    );

/// Review an incoming offer. Accept is disabled for 3 s after the offer
/// appears or changes (FR-TRADE-3).
class OfferReview extends ConsumerStatefulWidget {
  /// Creates the sheet.
  const OfferReview(
      {super.key,
      required this.tradeId,
      this.delay = const Duration(seconds: 3)});

  /// Trade id.
  final String tradeId;

  /// Review delay.
  final Duration delay;

  @override
  ConsumerState<OfferReview> createState() => _OfferReviewState();
}

class _OfferReviewState extends ConsumerState<OfferReview> {
  Timer? _timer;
  String? _seenKey;
  bool _canAccept = false;
  int _left = 3;

  void _restart(String key) {
    _seenKey = key;
    _timer?.cancel();
    _canAccept = false;
    _left = widget.delay.inSeconds;
    final start = clock.now();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      final elapsed = clock.now().difference(start);
      if (!mounted) return t.cancel();
      setState(() {
        _left = max(0, (widget.delay - elapsed).inMilliseconds ~/ 1000 + 1);
        if (elapsed >= widget.delay) {
          _canAccept = true;
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(gameProvider);
    final s = view.state!;
    final t = s.trades.where((t) => t.id == widget.tradeId).firstOrNull;
    if (t == null) {
      return const SizedBox(
          height: 160,
          child: Center(child: Text('This offer is no longer open')));
    }
    final key =
        '${t.id}:${t.createdAtVersion}:${t.give.toJson()}:${t.get.toJson()}';
    if (key != _seenKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && key != _seenKey) setState(() => _restart(key));
      });
    }
    final from = s.player(t.from);
    final game = ref.read(gameProvider.notifier);
    String describe(TradeSide side) => [
          for (final i in side.tiles) s.tiles[i].name,
          if (side.cash > 0) formatRupees(side.cash),
          if (side.cards > 0) '${side.cards} get-out card(s)',
        ].join(', ');
    final lopsided = isLopsided(s, t.give, t.get);
    final ready = _canAccept && key == _seenKey;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Offer from ${from?.name ?? '?'}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                  'You get: ${describe(t.give).isEmpty ? 'nothing' : describe(t.give)}'),
              Text(
                  'You give: ${describe(t.get).isEmpty ? 'nothing' : describe(t.get)}'),
              if (lopsided)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                      '⚠ Lopsided: one side is worth more than 5× the other',
                      style: TextStyle(color: Colors.orange)),
                ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('offer-reject'),
                    onPressed: () {
                      game.send(TradeAnswerMsg('trade_reject', t.id));
                      Navigator.pop(context);
                    },
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('offer-counter'),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TradeScreen(counterOf: t)));
                    },
                    child: const Text('Counter'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('offer-accept'),
                    onPressed: ready
                        ? () {
                            game.send(TradeAnswerMsg('trade_accept', t.id));
                            Navigator.pop(context);
                          }
                        : null,
                    child: Text(ready ? 'Accept' : 'Accept ($_left)'),
                  ),
                ),
              ]),
            ]),
      ),
    );
  }
}
