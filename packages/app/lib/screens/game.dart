import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import '../state/game_controller.dart';
import '../ui.dart';
import '../widgets/board.dart';
import '../widgets/chat.dart';
import '../widgets/talk.dart';
import 'home.dart';
import 'trade.dart';

/// Whether the engine would accept [a] now (used to enable buttons).
bool legal(GameState s, GameAction a) =>
    apply(a is Roll && !a.hasDice ? Roll(a.playerId, 1, 2) : a, s).ok;

/// Whether [me] may roll now (tap the dice).
bool canRollNow(GameState s, String me) =>
    s.actingPlayer == me && legal(s, Roll.intent(me));

/// Hint under the dice when [me] can roll.
String rollHint(GameState s, String me) {
  final p = s.player(me);
  if (p != null && p.inJail) return 'Tap the dice to try for doubles';
  if (s.phase == GamePhase.manage && s.rollAgain) {
    return 'Doubles! Tap to roll again';
  }
  return 'Your turn: tap the dice';
}

/// True while the board is still replaying moves; turn buttons wait.
final boardBusyProvider = NotifierProvider<BoardBusy, bool>(BoardBusy.new);

/// Holds [boardBusyProvider].
class BoardBusy extends Notifier<bool> {
  @override
  bool build() => false;

  /// Updates the flag.
  void set(bool v) {
    if (state != v) state = v;
  }
}

/// Turn actions legal for [me] right now, in display order (rolling is
/// done by tapping the dice).
List<(String, GameAction)> turnActions(GameState s, String me) {
  final p = s.player(me);
  if (p == null || p.bankrupt) return const [];
  final out = <(String, GameAction)>[];
  void add(String label, GameAction a) {
    if (legal(s, a)) out.add((label, a));
  }

  final tile = s.tiles[p.position];
  if (s.phase == GamePhase.awaitingRoll && p.inJail) {
    add('Pay ${formatRupees(s.config.jailFine)}', PayJailFine(me));
    add('Use card', UseJailCard(me));
  }
  add('Buy ${tile.name} ${formatRupees(tile.price)}', Buy(me));
  if (s.phase == GamePhase.awaitingBuy) {
    add(s.rules.auctions ? 'Auction' : 'Skip', DeclineBuy(me));
  }
  add('Pay ${formatRupees(s.debtOf(me))}', PayDebt(me));
  add('Declare bankruptcy', DeclareBankruptcy(me));
  add('End turn', EndTurn(me));
  return out;
}

/// The board, turn actions and panels.
class GameScreen extends ConsumerWidget {
  /// Creates the screen.
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(gameProvider);
    final s = view.state!;
    final me = view.me!;
    final width = MediaQuery.sizeOf(context).width;
    final size = sizeClassOf(width);
    final auc = s.auction;
    final board = BoardView(
      state: s,
      feed: view.feed,
      emotes: view.emotes,
      canRoll: canRollNow(s, me),
      onRoll: () => ref.read(gameProvider.notifier).act(Roll.intent(me)),
      rollHint: rollHint(s, me),
      onBusy: (b) => ref.read(boardBusyProvider.notifier).set(b),
      centreExtra: auc == null
          ? null
          : _AuctionInfo(
              key: const ValueKey('auction-info'),
              text: 'Auction: ${s.tiles[auc.tileIndex].name}\n'
                  '${auc.highBidder == null ? 'No bids yet' : 'High bid ${formatRupees(auc.highBid)} by ${s.player(auc.highBidder)?.name}'}'),
    );
    final actionBar = ActionBar(state: s, me: me);
    final incoming = s.trades.where((t) => t.to == me).toList();

    Widget body;
    switch (size) {
      case SizeClass.phone:
        body = Column(children: [
          _TopBar(view: view),
          Expanded(
              child: Padding(padding: const EdgeInsets.all(4), child: board)),
          _PhoneTabs(view: view),
          actionBar,
          const SizedBox(height: 100), // room for the talk button and its label
        ]);
      case SizeClass.medium:
        body = Row(children: [
          Expanded(
              flex: 3,
              child: Column(children: [
                _TopBar(view: view),
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.all(6), child: board)),
                actionBar,
              ])),
          SizedBox(width: min(360, width * 0.38), child: _SideTabs(view: view)),
        ]);
      case SizeClass.large:
        body = Row(children: [
          SizedBox(width: 280, child: PlayersPanel(view: view)),
          Expanded(
              child: Column(children: [
            _TopBar(view: view),
            Expanded(
                child: Padding(padding: const EdgeInsets.all(8), child: board)),
            actionBar,
          ])),
          SizedBox(
            width: 340,
            child: Column(children: [
              Expanded(child: MyCities(view: view)),
              const Divider(height: 1),
              Expanded(child: LogView(view: view)),
            ]),
          ),
        ]);
    }

    return Scaffold(
      floatingActionButton: view.offline ? null : const CommsButton(),
      body: SafeArea(
        child: Stack(children: [
          body,
          const Positioned(
              top: 6,
              left: 8,
              right: 8,
              child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                SpeakingBanner(),
                SizedBox(height: 4),
                ChatBanner(),
              ]))),
          if (incoming.isNotEmpty)
            Positioned(
              top: 48,
              left: 8,
              right: 8,
              child: Center(child: _OfferBanner(trade: incoming.first)),
            ),
          if (view.paused ||
              view.status == ConnStatus.reconnecting ||
              view.status == ConnStatus.closed)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (view.status != ConnStatus.closed)
                          const CircularProgressIndicator()
                        else
                          const Icon(Icons.wifi_off, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          switch (view.status) {
                            ConnStatus.reconnecting =>
                              'Connection lost. Reconnecting…\nYour seat is kept for 3 minutes.',
                            ConnStatus.closed => view.error ?? 'Disconnected',
                            _ => view.notice ?? 'Game paused',
                          },
                          key: const ValueKey('connection-overlay'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        if (view.status != ConnStatus.connected &&
                            !view.offline)
                          FilledButton.icon(
                            key: const ValueKey('reconnect-now'),
                            onPressed: () => ref
                                .read(gameProvider.notifier)
                                .forceReconnect(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reconnect now'),
                          ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () async {
                            await ref.read(gameProvider.notifier).leave();
                            await ref.read(localHostProvider.notifier).stop();
                          },
                          child: const Text('Leave game'),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.view});
  final GameView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = view.state!;
    final cur = s.player(s.currentPlayer);
    final me = view.myPlayer;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          if (me != null) ...[
            Text(tokenEmoji(me.token), style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 6),
            CashText(me.cash,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              view.myTurn ? 'Your turn' : "${cur?.name ?? ''}'s turn",
              key: const ValueKey('turn-label'),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: 'Voice',
            onPressed: () => showVoiceSettings(context, ref),
            icon: const Icon(Icons.headset_mic),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (v) async {
              final game = ref.read(gameProvider.notifier);
              if (v == 'save') game.send(const SimpleIntent('save_game'));
              if (v == 'leave') {
                await game.leave();
                await ref.read(localHostProvider.notifier).stop();
              }
            },
            itemBuilder: (_) => [
              if (view.isHost && !view.offline)
                const PopupMenuItem(value: 'save', child: Text('Save game')),
              const PopupMenuItem(value: 'leave', child: Text('Leave game')),
            ],
          ),
        ]),
      ),
    );
  }
}

/// Phase-driven buttons: only legal moves are shown.
class ActionBar extends ConsumerWidget {
  /// Creates the bar.
  const ActionBar({super.key, required this.state, required this.me});

  /// State.
  final GameState state;

  /// My id.
  final String me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.read(gameProvider.notifier);
    final s = state;
    final buttons = <Widget>[];
    // Turn buttons wait until the board has finished showing the move.
    final busy = ref.watch(boardBusyProvider);
    if (s.actingPlayer == me && !busy) {
      for (final (label, a) in turnActions(s, me)) {
        final primary = a is Buy || a is PayDebt || a is EndTurn;
        buttons.add(primary
            ? FilledButton(
                key: ValueKey('act-${a.runtimeType}'),
                onPressed: () => game.act(a),
                child: Text(label))
            : OutlinedButton(
                key: ValueKey('act-${a.runtimeType}'),
                onPressed: () => game.act(a),
                child: Text(label)));
      }
    }
    final auc = s.auction;
    if (auc != null && !(s.player(me)?.bankrupt ?? true)) {
      final base = auc.highBid == 0 ? 0 : auc.highBid;
      for (final step in [auc.minStep, 50000, 100000]) {
        final amount = max(base + step, auc.minStep);
        final bid = Bid(me, amount);
        if (legal(s, bid) && auc.highBidder != me) {
          buttons.add(FilledButton.tonal(
              key: ValueKey('bid-$step'),
              onPressed: () => game.act(bid),
              child: Text('Bid ${formatRupees(amount)}')));
        }
      }
    }
    final error = ref.watch(gameProvider.select((g) => g.error));
    if (s.phase == GamePhase.raiseCash && s.debts.isNotEmpty) {
      final debtor = s.actingPlayer;
      final creditor = s.debts.first.creditorId;
      final to =
          creditor == null ? 'the bank' : s.player(creditor)?.name ?? '?';
      buttons.insert(
          0,
          Text(
              debtor == me
                  ? 'You owe ${formatRupees(s.debtOf(me))} to $to — sell or mortgage in My cities, then pay'
                  : '${s.player(debtor)?.name ?? '?'} is raising ${formatRupees(s.debtOf(debtor))} to pay $to',
              key: const ValueKey('raise-cash-banner'),
              style: TextStyle(
                  color: debtor == me
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurfaceVariant)));
    }
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (error != null)
            Text(error,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...buttons,
              _EmoteBar(),
              OutlinedButton.icon(
                key: const ValueKey('trade-button'),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TradeScreen())),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Trade'),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

class _EmoteBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<Emote>(
        tooltip: 'Emote',
        onSelected: (e) => ref.read(gameProvider.notifier).send(EmoteMsg(e)),
        itemBuilder: (_) => [
          for (final e in Emote.values)
            PopupMenuItem(
                value: e,
                child: Text(e.label, style: const TextStyle(fontSize: 18))),
        ],
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.emoji_emotions_outlined),
        ),
      );
}

/// Auction status with a countdown that restarts on every new bid (the
/// server closes the auction 10 s after the last bid).
class _AuctionInfo extends StatefulWidget {
  const _AuctionInfo({super.key, required this.text});
  final String text;

  @override
  State<_AuctionInfo> createState() => _AuctionInfoState();
}

class _AuctionInfoState extends State<_AuctionInfo> {
  static const _seconds = 10;
  int _left = _seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(_AuctionInfo old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _restart();
  }

  void _restart() {
    _timer?.cancel();
    _left = _seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left = max(0, _left - 1));
      if (_left == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12)),
        child: Text('${widget.text}\nCloses in $_left s',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      );
}

/// Cash, token and status of every player.
class PlayersPanel extends StatelessWidget {
  /// Creates the panel.
  const PlayersPanel({super.key, required this.view});

  /// View.
  final GameView view;

  @override
  Widget build(BuildContext context) {
    final s = view.state!;
    return ListView(children: [
      for (final p in s.players)
        ListTile(
          key: ValueKey('panel-${p.id}'),
          selected: p.id == s.currentPlayer,
          leading: CircleAvatar(
              backgroundColor: playerColor(s, p.id),
              child: Text(tokenEmoji(p.token))),
          title: Text('${p.name}${p.id == view.me ? ' (you)' : ''}',
              style: TextStyle(
                  decoration: p.bankrupt ? TextDecoration.lineThrough : null)),
          subtitle: Text([
            if (p.bankrupt) 'bankrupt',
            if (p.inJail) 'in jail',
            if (p.isBot) 'bot',
            if (!p.connected) 'offline',
            '${s.ownedBy(p.id).length} cities',
          ].join(' · ')),
          trailing: CashText(p.cash),
        ),
    ]);
  }
}

/// My cities with Build, Sell, Mortgage and Unmortgage (enabled only when
/// legal).
class MyCities extends ConsumerWidget {
  /// Creates the sheet.
  const MyCities({super.key, required this.view});

  /// View.
  final GameView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = view.state!;
    final me = view.me!;
    final game = ref.read(gameProvider.notifier);
    final mine = s.ownedBy(me)
      ..sort((a, b) => a.tileIndex.compareTo(b.tileIndex));
    if (mine.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('You own no cities yet')));
    }
    Widget btn(String label, GameAction a, int tile) => TextButton(
          key: ValueKey('${a.runtimeType}-$tile'),
          onPressed: legal(s, a) ? () => game.act(a) : null,
          child: Text(label),
        );
    return ListView(children: [
      for (final o in mine)
        Builder(builder: (context) {
          final t = s.tiles[o.tileIndex];
          return ListTile(
            dense: true,
            leading: Container(width: 14, height: 36, color: hexColor(t.color)),
            title: Text(t.name),
            subtitle: Text([
              if (o.mortgaged) 'mortgaged',
              if (o.houses == 5)
                'hotel'
              else if (o.houses > 0)
                '${o.houses} house(s)',
              if (t.type == TileType.city && !o.mortgaged)
                'rent ${formatRupees(s.rentFor(t.index, 7))}',
            ].join(' · ')),
            trailing: Wrap(children: [
              if (t.type == TileType.city)
                btn('Build', Build(me, t.index), t.index),
              if (o.houses > 0) btn('Sell', SellBuilding(me, t.index), t.index),
              if (!o.mortgaged) btn('Mortgage', Mortgage(me, t.index), t.index),
              if (o.mortgaged)
                btn('Unmortgage', Unmortgage(me, t.index), t.index),
            ]),
          );
        }),
    ]);
  }
}

/// Activity log and the Verify dice view.
class LogView extends StatelessWidget {
  /// Creates the log.
  const LogView({super.key, required this.view});

  /// View.
  final GameView view;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(children: [
          const TabBar(tabs: [
            Tab(text: 'Activity'),
            Tab(text: 'Chat'),
            Tab(text: 'Verify dice'),
          ]),
          Expanded(
            child: TabBarView(children: [
              ListView(
                key: const ValueKey('activity-log'),
                reverse: true,
                children: [
                  for (final e in view.state!.log.reversed)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      child: Text(e.text, style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
              const ChatPanel(),
              DiceVerifyView(dice: view.dice),
            ]),
          ),
        ]),
      );
}

/// Every roll with its commit, reveal and pass/fail (NFR-3).
class DiceVerifyView extends StatelessWidget {
  /// Creates the view.
  const DiceVerifyView({super.key, required this.dice});

  /// Commits and reveals.
  final List<(DiceCommit?, DiceReveal)> dice;

  @override
  Widget build(BuildContext context) {
    if (dice.isEmpty) return const Center(child: Text('No rolls yet'));
    return ListView(children: [
      for (final (c, r) in dice.reversed)
        ListTile(
          dense: true,
          leading: Icon(
            c != null && FairDice.verify(c, r)
                ? Icons.verified
                : Icons.help_outline,
            color: c != null && FairDice.verify(c, r)
                ? Colors.green
                : Colors.orange,
          ),
          title: Text('Roll #${r.rollNumber}: ${r.d1} + ${r.d2}'),
          subtitle: Text(
            c == null
                ? 'Commit not seen (joined later)'
                : '${FairDice.verify(c, r) ? 'Pass' : 'FAIL'} · commit ${c.hash.substring(0, 12)}… · key ${r.key.substring(0, 12)}…',
            style: const TextStyle(fontSize: 11),
          ),
        ),
    ]);
  }
}

class _PhoneTabs extends StatelessWidget {
  const _PhoneTabs({required this.view});
  final GameView view;

  void _sheet(BuildContext context, Widget Function() child) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => Consumer(builder: (context, ref, _) {
          // Rebuild with fresh state while open.
          ref.watch(gameProvider);
          return SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.6, child: child());
        }),
      );

  @override
  Widget build(BuildContext context) => Consumer(builder: (context, ref, _) {
        GameView v() => ref.read(gameProvider);
        Widget tab(String key, IconData icon, String label,
                Widget Function() child) =>
            Expanded(
              child: TextButton.icon(
                key: ValueKey(key),
                onPressed: () => _sheet(context, child),
                icon: Icon(icon),
                label:
                    Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
            );
        return Row(children: [
          tab('tab-players', Icons.people, 'Players',
              () => PlayersPanel(view: v())),
          tab('tab-cities', Icons.location_city, 'Cities',
              () => MyCities(view: v())),
          tab('tab-log', Icons.list, 'Log', () => LogView(view: v())),
        ]);
      });
}

class _SideTabs extends StatelessWidget {
  const _SideTabs({required this.view});
  final GameView view;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Column(children: [
          const TabBar(tabs: [
            Tab(text: 'Players'),
            Tab(text: 'My cities'),
            Tab(text: 'Log')
          ]),
          Expanded(
            child: TabBarView(children: [
              PlayersPanel(view: view),
              MyCities(view: view),
              LogView(view: view),
            ]),
          ),
        ]),
      );
}

class _OfferBanner extends StatelessWidget {
  const _OfferBanner({required this.trade});
  final Trade trade;

  @override
  Widget build(BuildContext context) => Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: InkWell(
          key: const ValueKey('offer-banner'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => showIncomingOffer(context, trade.id),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.handshake),
              SizedBox(width: 8),
              Text('New trade offer — tap to review'),
            ]),
          ),
        ),
      );
}
