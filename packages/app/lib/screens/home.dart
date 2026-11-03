import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import '../app.dart';
import '../services/platform.dart';
import '../services/transport.dart';
import '../state/game_controller.dart';
import '../state/profile.dart';
import '../ui.dart';
import 'help.dart';
import 'join.dart';

/// The running local host, if this device hosts.
final localHostProvider = NotifierProvider<LocalHostNotifier, LocalHostHandle?>(
    LocalHostNotifier.new);

/// Holds the [LocalHostHandle] while hosting.
class LocalHostNotifier extends Notifier<LocalHostHandle?> {
  @override
  LocalHostHandle? build() => null;

  /// Sets or clears the handle.
  void set(LocalHostHandle? h) => state = h;

  /// Stops hosting.
  Future<void> stop() async {
    final h = state;
    state = null;
    await h?.stop();
  }
}

/// Name, token and the four ways to play.
class HomeScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _checkName() {
    if (ref.read(profileProvider).name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick a nickname first')));
      return false;
    }
    return true;
  }

  Future<void> _playBots() async {
    if (!_checkName()) return;
    final choice = await showDialog<(int, BotLevel)>(
      context: context,
      builder: (context) => const _BotsDialog(),
    );
    if (choice == null || !mounted) return;
    final board = await ref.read(boardProvider.future);
    final profile = ref.read(profileProvider);
    final game = ref.read(gameProvider.notifier);
    await game.playOffline(OfflineTransport(board),
        name: profile.name, token: profile.token);
    for (var i = 0; i < choice.$1; i++) {
      game.send(AddBotMsg(level: choice.$2));
    }
  }

  Future<void> _host() async {
    if (!_checkName()) return;
    if (!await hasLocalNetwork() && mounted) {
      final go = await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const HotspotGuide()));
      if (go != true) return;
    }
    if (!mounted) return;
    final password = await showDialog<String?>(
        context: context, builder: (context) => const _HostDialog());
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final board = await ref.read(boardProvider.future);
      final profile = ref.read(profileProvider);
      final handle = await startLocalHost(
          board: board,
          roomName: "${profile.name}'s game",
          password: password.isEmpty ? null : password);
      ref.read(localHostProvider.notifier).set(handle);
      final ok = await ref.read(gameProvider.notifier).connect(
            Uri.parse('ws://127.0.0.1:${handle.port}/ws'),
            code: handle.code,
            name: profile.name,
            token: profile.token,
            password: password.isEmpty ? null : password,
            hosting: true,
            hostAddress: '${handle.ip ?? 'no network'}:${handle.port}',
          );
      if (!ok) await handle.stop();
      if (mounted && defaultTargetPlatform == TargetPlatform.iOS) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Keep Vyapari open while hosting — leaving pauses the game.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not host: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    if (_name.text.isEmpty && profile.name.isNotEmpty) {
      _name.text = profile.name;
    }
    final error = ref.watch(gameProvider.select((g) => g.error));
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Vyapari',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .displayMedium
                            ?.copyWith(
                                color: saffron, fontWeight: FontWeight.w800)),
                    const Text('Buy cities. Build. Trade. Win.',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    TextField(
                      key: const ValueKey('name-field'),
                      controller: _name,
                      maxLength: 20,
                      decoration: const InputDecoration(
                          labelText: 'Nickname', border: OutlineInputBorder()),
                      onChanged: (v) =>
                          ref.read(profileProvider.notifier).setName(v),
                    ),
                    const Text('Token'),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final t in Token.values)
                        ChoiceChip(
                          key: ValueKey('token-${t.name}'),
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                          label: Text('${tokenEmoji(t)} ${tokenName(t)}'),
                          selected: profile.token == t,
                          onSelected: (_) =>
                              ref.read(profileProvider.notifier).setToken(t),
                        ),
                    ]),
                    const SizedBox(height: 24),
                    if (canHost)
                      FilledButton.icon(
                        key: const ValueKey('host-button'),
                        onPressed: _busy ? null : _host,
                        icon: const Icon(Icons.wifi_tethering),
                        label: const Text('Host a game'),
                      ),
                    if (canDiscover) ...[
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          if (_checkName()) {
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => const JoinScreen(
                                    initialTab: JoinTab.nearby)));
                          }
                        },
                        icon: const Icon(Icons.radar),
                        label: const Text('Join nearby'),
                      ),
                    ],
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      key: const ValueKey('join-online'),
                      onPressed: () {
                        if (_checkName()) {
                          Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => const JoinScreen(
                                  initialTab: JoinTab.online)));
                        }
                      },
                      icon: const Icon(Icons.public),
                      label: const Text('Join online'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const ValueKey('play-bots'),
                      onPressed: _playBots,
                      icon: const Icon(Icons.smart_toy),
                      label: const Text('Play vs bots'),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const HelpScreen())),
                      child: const Text('How to play · How to host'),
                    ),
                    Text('Version $appVersion',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _BotsDialog extends StatefulWidget {
  const _BotsDialog();

  @override
  State<_BotsDialog> createState() => _BotsDialogState();
}

class _BotsDialogState extends State<_BotsDialog> {
  int _count = 3;
  BotLevel _level = BotLevel.medium;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Play vs bots'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Expanded(child: Text('Bots')),
            IconButton(
                onPressed: _count > 1 ? () => setState(() => _count--) : null,
                icon: const Icon(Icons.remove)),
            Text('$_count'),
            IconButton(
                onPressed: _count < 7 ? () => setState(() => _count++) : null,
                icon: const Icon(Icons.add)),
          ]),
          SegmentedButton<BotLevel>(
            segments: const [
              ButtonSegment(value: BotLevel.easy, label: Text('Easy')),
              ButtonSegment(value: BotLevel.medium, label: Text('Medium')),
              ButtonSegment(value: BotLevel.hard, label: Text('Hard')),
            ],
            selected: {_level},
            onSelectionChanged: (s) => setState(() => _level = s.first),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              key: const ValueKey('bots-go'),
              onPressed: () => Navigator.pop(context, (_count, _level)),
              child: const Text('Play')),
        ],
      );
}

class _HostDialog extends StatefulWidget {
  const _HostDialog();

  @override
  State<_HostDialog> createState() => _HostDialogState();
}

class _HostDialogState extends State<_HostDialog> {
  final _pw = TextEditingController();

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Host a game'),
        content: TextField(
          controller: _pw,
          maxLength: 12,
          decoration: const InputDecoration(
              labelText: 'Room password (optional)',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _pw.text.trim()),
              child: const Text('Start hosting')),
        ],
      );
}

/// Shown when Host is tapped with no Wi-Fi or hotspot (FR-NET-3).
class HotspotGuide extends StatelessWidget {
  /// Creates the guide.
  const HotspotGuide({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Turn on your hotspot')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Icon(Icons.wifi_tethering, size: 64, color: saffron),
          const SizedBox(height: 12),
          const Text(
            'No Wi-Fi or hotspot found. Your friends join over your phone\'s '
            'hotspot — no internet or mobile data needed.',
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          const _Step(1, 'Open Settings → Network → Hotspot & tethering.'),
          const _Step(2, 'Turn on Wi-Fi hotspot. Mobile data can stay off.'),
          const _Step(3, 'Ask friends to join your hotspot Wi-Fi.'),
          const _Step(4, 'Come back here and tap "I turned it on".'),
          const SizedBox(height: 20),
          if (defaultTargetPlatform == TargetPlatform.android)
            OutlinedButton.icon(
              onPressed: openHotspotSettings,
              icon: const Icon(Icons.settings),
              label: const Text('Open hotspot settings'),
            ),
          const SizedBox(height: 10),
          FilledButton(
            key: const ValueKey('hotspot-done'),
            onPressed: () async {
              final ok = await hasLocalNetwork();
              if (!context.mounted) return;
              if (ok) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content:
                        Text('Still no network — check the hotspot is on.')));
              }
            },
            child: const Text('I turned it on'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Host anyway (only this device can join)'),
          ),
        ]),
      );
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.text);
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(child: Text('$n')),
        title: Text(text),
      );
}
