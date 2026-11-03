import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/platform.dart';
import '../state/game_controller.dart';
import '../state/profile.dart';

/// Join screen tabs.
enum JoinTab { nearby, online, address }

/// Default online server: the page's own origin on web, else none.
String defaultServerUrl() {
  final base = Uri.base;
  if (base.scheme == 'http' || base.scheme == 'https') {
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${base.authority}/ws';
  }
  return '';
}

/// Nearby games, online room code, and manual IP join.
class JoinScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const JoinScreen({super.key, this.initialTab = JoinTab.online});

  /// Tab to open first.
  final JoinTab initialTab;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _ip = TextEditingController();
  final _port = TextEditingController(text: '47800');
  late final TextEditingController _server =
      TextEditingController(text: defaultServerUrl());
  bool _busy = false;

  List<JoinTab> get _tabs => [
        if (canDiscover) JoinTab.nearby,
        JoinTab.online,
        if (canHost) JoinTab.address
      ];

  @override
  void dispose() {
    for (final c in [_code, _password, _ip, _port, _server]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _join(Uri uri, String code,
      {bool create = false, String? password}) async {
    setState(() => _busy = true);
    final profile = ref.read(profileProvider);
    final ok = await ref.read(gameProvider.notifier).connect(
          uri,
          code: code.trim().toUpperCase(),
          name: profile.name,
          token: profile.token,
          create: create,
          password: (password ?? _password.text).trim().isEmpty
              ? null
              : (password ?? _password.text).trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Uri? _serverUri() {
    final u = Uri.tryParse(_server.text.trim());
    if (u == null || !(u.scheme == 'ws' || u.scheme == 'wss')) return null;
    return u.path.isEmpty ? u.replace(path: '/ws') : u;
  }

  Future<void> _scan() async {
    final text = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));
    final link = text == null ? null : parseJoinUri(text);
    if (link == null || !mounted) return;
    await _join(Uri.parse('ws://${link.ip}:${link.port}/ws'), link.code);
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(gameProvider.select((g) => g.error));
    final tabs = _tabs;
    final initial = tabs.indexOf(widget.initialTab).clamp(0, tabs.length - 1);
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initial,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Join a game'),
          actions: [
            if (canScan)
              IconButton(
                  tooltip: 'Scan QR',
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner)),
          ],
          bottom: TabBar(tabs: [
            for (final t in tabs)
              Tab(
                  text: switch (t) {
                JoinTab.nearby => 'Nearby',
                JoinTab.online => 'Room code',
                JoinTab.address => 'IP address',
              }),
          ]),
        ),
        body: Column(children: [
          if (error != null)
            MaterialBanner(
              key: const ValueKey('join-error'),
              content: Text(error),
              leading: const Icon(Icons.error_outline),
              actions: [
                TextButton(
                    onPressed: () =>
                        ref.read(gameProvider.notifier).clearError(),
                    child: const Text('OK')),
              ],
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: TabBarView(children: [
              for (final t in tabs)
                switch (t) {
                  JoinTab.nearby => _nearby(),
                  JoinTab.online => _online(),
                  JoinTab.address => _address(),
                },
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _nearby() => StreamBuilder<List<NearbyHost>>(
        stream: discoverNearby(),
        builder: (context, snap) {
          final games = snap.data ?? const [];
          if (snap.hasError) {
            return Center(child: Text('Discovery failed: ${snap.error}'));
          }
          if (games.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Looking for games on this Wi-Fi or hotspot…',
                      textAlign: TextAlign.center),
                ]),
              ),
            );
          }
          return ListView(children: [
            for (final g in games)
              ListTile(
                leading: const Icon(Icons.casino),
                title: Text(g.name),
                subtitle: Text(
                    'Room ${g.code} · ${g.via.contains(Found.udp) ? '${g.players}/${g.maxPlayers} players' : 'found via Bonjour'} · ${g.ip}'),
                trailing: g.hasPassword
                    ? const Icon(Icons.lock)
                    : const Icon(Icons.chevron_right),
                onTap: () async {
                  String? pw;
                  if (g.hasPassword) {
                    pw = await _askPassword();
                    if (pw == null) return;
                  }
                  await _join(Uri.parse('ws://${g.ip}:${g.port}/ws'), g.code,
                      password: pw);
                },
              ),
          ]);
        },
      );

  Future<String?> _askPassword() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Room password'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text),
              child: const Text('Join')),
        ],
      ),
    );
  }

  Widget _online() {
    final servers = ref.watch(profileProvider).servers;
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        key: const ValueKey('server-field'),
        controller: _server,
        decoration: InputDecoration(
          labelText: 'Server (wss://…/ws)',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'Save server',
            icon: const Icon(Icons.bookmark_add),
            onPressed: () {
              final u = _serverUri();
              if (u != null) {
                ref
                    .read(profileProvider.notifier)
                    .addServer(SavedServer(u.host, u.toString()));
              }
            },
          ),
        ),
      ),
      if (servers.isNotEmpty)
        Wrap(spacing: 6, children: [
          for (final s in servers)
            InputChip(
              label: Text(s.name),
              onPressed: () => setState(() => _server.text = s.url),
              onDeleted: () =>
                  ref.read(profileProvider.notifier).removeServer(s.url),
            ),
        ]),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('code-field'),
        controller: _code,
        textCapitalization: TextCapitalization.characters,
        maxLength: 6,
        decoration: const InputDecoration(
            labelText: 'Room code', border: OutlineInputBorder()),
      ),
      TextField(
        controller: _password,
        decoration: const InputDecoration(
            labelText: 'Password (if the room has one)',
            border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const ValueKey('join-button'),
        onPressed: _busy
            ? null
            : () {
                final u = _serverUri();
                if (u == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Enter a ws:// or wss:// server address')));
                  return;
                }
                _join(u, _code.text);
              },
        child: const Text('Join'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        key: const ValueKey('create-button'),
        onPressed: _busy
            ? null
            : () {
                final u = _serverUri();
                if (u != null) _join(u, '', create: true);
              },
        child: const Text('Create a new room'),
      ),
      const SizedBox(height: 16),
      _PublicRooms(
          serverUri: _serverUri(),
          onJoin: (code) {
            final u = _serverUri();
            if (u != null) _join(u, code);
          }),
    ]);
  }

  Widget _address() => ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _ip,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Host IP (e.g. 192.168.43.1)',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _port,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'Port', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(
              labelText: 'Room code', border: OutlineInputBorder()),
        ),
        TextField(
          controller: _password,
          decoration: const InputDecoration(
              labelText: 'Password (optional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _join(
                  Uri.parse('ws://${_ip.text.trim()}:${_port.text.trim()}/ws'),
                  _code.text),
          child: const Text('Join'),
        ),
      ]);
}

class _PublicRooms extends StatefulWidget {
  const _PublicRooms({required this.serverUri, required this.onJoin});
  final Uri? serverUri;
  final void Function(String code) onJoin;

  @override
  State<_PublicRooms> createState() => _PublicRoomsState();
}

class _PublicRoomsState extends State<_PublicRooms> {
  List<Map<String, Object?>>? _rooms;

  Future<void> _load() async {
    final ws = widget.serverUri;
    if (ws == null) return;
    final http0 = ws.replace(
        scheme: ws.scheme == 'wss' ? 'https' : 'http', path: '/rooms');
    try {
      final r = await http.get(http0).timeout(const Duration(seconds: 4));
      setState(() =>
          _rooms = (jsonDecode(r.body) as List).cast<Map<String, Object?>>());
    } catch (_) {
      setState(() => _rooms = const []);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Expanded(child: Text('Open rooms')),
          TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh')),
        ]),
        if (_rooms != null && _rooms!.isEmpty)
          const Text('No open rooms right now'),
        for (final r in _rooms ?? const <Map<String, Object?>>[])
          ListTile(
            title: Text('Room ${r['code']}'),
            subtitle: Text(
                'Host ${r['host'] ?? '?'} · ${r['players']}/${r['maxPlayers']} players'),
            trailing: const Icon(Icons.login),
            onTap: () => widget.onJoin(r['code'] as String),
          ),
      ]);
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan the host\'s QR code')),
        body: MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v != null && parseJoinUri(v) != null) {
                _done = true;
                Navigator.pop(context, v);
                return;
              }
            }
          },
        ),
      );
}
