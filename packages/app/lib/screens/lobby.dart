import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import '../state/game_controller.dart';
import '../ui.dart';
import '../widgets/chat.dart';
import '../widgets/talk.dart';
import 'home.dart';

/// Whether the host may start: 2+ players and 2+ ready (host counts).
bool canStart(GameState s) =>
    s.players.length >= 2 &&
    s.players.where((p) => p.ready || p.isBot || p.id == s.hostId).length >= 2;

/// Who joined, house rules (host edits, others read-only), bots and Start.
class LobbyScreen extends ConsumerWidget {
  /// Creates the screen.
  const LobbyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(gameProvider);
    final s = view.state!;
    final game = ref.read(gameProvider.notifier);
    final host = view.isHost;
    final me = view.myPlayer;
    final link = ref.watch(localHostProvider)?.joinUri;
    final wide = MediaQuery.sizeOf(context).width >= 800;

    final code = Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text('Room code'),
          SelectableText(view.roomCode.isEmpty ? s.roomId : view.roomCode,
              key: const ValueKey('room-code'),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                  color: saffron)),
          if (view.hostAddress != null) Text('Host: ${view.hostAddress}'),
          if (link != null) ...[
            const SizedBox(height: 8),
            QrImageView(
              data: link.toString(),
              size: 160,
              backgroundColor: Colors.white,
            ),
            const Text('Scan to join', style: TextStyle(fontSize: 12)),
          ],
        ]),
      ),
    );

    final players = Card(
      child: Column(children: [
        ListTile(
          title: Text('Players (${s.players.length}/${s.config.maxPlayers})',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final p in s.players)
          ListTile(
            key: ValueKey('lobby-player-${p.id}'),
            leading: CircleAvatar(
              backgroundColor: playerColor(s, p.id),
              child: Text(tokenEmoji(p.token)),
            ),
            title: Text('${p.name}${p.id == view.me ? ' (you)' : ''}'),
            subtitle: Text([
              if (p.id == s.hostId) 'Host',
              if (p.isBot) '${p.botLevel?.name ?? ''} bot',
              if (!p.connected) 'disconnected',
            ].join(' · ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                p.ready || p.isBot || p.id == s.hostId
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: p.ready || p.isBot || p.id == s.hostId
                    ? Colors.green
                    : Colors.grey,
              ),
              if (host && p.id != view.me)
                IconButton(
                  tooltip: 'Remove',
                  icon: const Icon(Icons.person_remove),
                  onPressed: () => game.send(PlayerTargetMsg('kick', p.id)),
                ),
            ]),
          ),
        if (host && s.players.length < s.config.maxPlayers)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(spacing: 8, children: [
              for (final l in BotLevel.values)
                OutlinedButton.icon(
                  key: ValueKey('add-bot-${l.name}'),
                  onPressed: () => game.send(AddBotMsg(level: l)),
                  icon: const Icon(Icons.smart_toy),
                  label: Text('Add ${l.name} bot'),
                ),
            ]),
          ),
      ]),
    );

    final r = s.rules;
    void set(HouseRules rules) => game.send(SetRulesMsg(rules));
    final rules = Card(
      child: Column(children: [
        ListTile(
          title: Text('House rules',
              style: Theme.of(context).textTheme.titleMedium),
          subtitle: host ? null : const Text('Only the host can change these'),
        ),
        _rule(host, 'Chai Break pot (taxes go to the middle)', r.freeParkingPot,
            (v) => set(r.copyWith(freeParkingPot: v)), 'rule-pot'),
        _rule(host, 'Double salary for landing on Start', r.doubleOnStart,
            (v) => set(r.copyWith(doubleOnStart: v)), 'rule-start'),
        _rule(host, 'Auctions', r.auctions, (v) => set(r.copyWith(auctions: v)),
            'rule-auctions'),
        _rule(host, 'No rent while in jail', r.noRentInJail,
            (v) => set(r.copyWith(noRentInJail: v)), 'rule-jail'),
        _rule(host, 'Quick game (2 cities each, 60 min)', r.quickGame,
            (v) => set(r.copyWith(quickGame: v)), 'rule-quick'),
        _rule(host, 'Bot plays for disconnected players', r.botCover,
            (v) => set(r.copyWith(botCover: v)), 'rule-cover'),
        ListTile(
          title: const Text('Starting cash'),
          trailing: DropdownButton<int>(
            value: r.startingCash,
            onChanged: host ? (v) => set(r.copyWith(startingCash: v)) : null,
            items: [
              for (final c in {
                1000000,
                1500000,
                2000000,
                2500000,
                r.startingCash
              })
                DropdownMenuItem(value: c, child: Text(formatRupees(c))),
            ],
          ),
        ),
        ListTile(
          title: const Text('Turn timer'),
          trailing: DropdownButton<int>(
            value: r.turnTimerSec,
            onChanged: host ? (v) => set(r.copyWith(turnTimerSec: v)) : null,
            items: [
              for (final t in {0, 30, 60, 90, 120, r.turnTimerSec})
                DropdownMenuItem(
                    value: t, child: Text(t == 0 ? 'Off' : '$t s')),
            ],
          ),
        ),
      ]),
    );

    final ready = me?.ready ?? false;
    final start = canStart(s);
    final actions = Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        OutlinedButton(
          onPressed: () async {
            await ref.read(gameProvider.notifier).leave();
            await ref.read(localHostProvider.notifier).stop();
          },
          child: const Text('Leave'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: host
              ? FilledButton(
                  key: const ValueKey('start-button'),
                  onPressed: start
                      ? () => game.send(const SimpleIntent('start'))
                      : null,
                  child: Text(
                      start ? 'Start game' : 'Waiting for 2+ ready players'),
                )
              : FilledButton.tonal(
                  key: const ValueKey('ready-button'),
                  onPressed: () => game.send(ReadyMsg(ready: !ready)),
                  child: Text(ready ? 'Ready ✓ (tap to undo)' : "I'm ready"),
                ),
        ),
      ]),
    );

    return Scaffold(
      appBar:
          AppBar(title: const Text('Lobby'), automaticallyImplyLeading: false),
      floatingActionButton: view.offline ? null : const CommsButton(),
      body: SafeArea(
        child: Column(children: [
          const SpeakingBanner(),
          const ChatBanner(),
          if (view.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(view.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: ListView(children: [code, players])),
                    Expanded(child: ListView(children: [rules])),
                  ])
                : ListView(children: [
                    code,
                    players,
                    rules,
                    const SizedBox(height: 80)
                  ]),
          ),
          actions,
        ]),
      ),
    );
  }

  Widget _rule(bool host, String label, bool value,
          ValueChanged<bool> onChanged, String key) =>
      SwitchListTile(
        key: ValueKey(key),
        title: Text(label),
        value: value,
        onChanged: host ? onChanged : null,
      );
}
