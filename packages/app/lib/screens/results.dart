import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import '../state/game_controller.dart';
import '../ui.dart';
import 'home.dart';

/// Winner, net-worth ranking, Rematch and Home.
class ResultsScreen extends ConsumerWidget {
  /// Creates the screen.
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(gameProvider);
    final s = view.state!;
    final winner = s.player(s.winnerId);
    final ranked = [...s.players]..sort((a, b) {
        if (a.id == s.winnerId) return -1;
        if (b.id == s.winnerId) return 1;
        if (a.bankrupt != b.bankrupt) return a.bankrupt ? 1 : -1;
        return s.netWorth(b.id).compareTo(s.netWorth(a.id));
      });
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
                padding: const EdgeInsets.all(20),
                shrinkWrap: true,
                children: [
                  const Text('🏆',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 64)),
                  Text(
                    winner == null ? 'Game over' : '${winner.name} wins!',
                    key: const ValueKey('winner'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  for (var i = 0; i < ranked.length; i++)
                    ListTile(
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text(
                          '${tokenEmoji(ranked[i].token)} ${ranked[i].name}'),
                      subtitle: Text(ranked[i].bankrupt
                          ? 'Bankrupt'
                          : '${s.ownedBy(ranked[i].id).length} cities'),
                      trailing: Text(formatRupees(s.netWorth(ranked[i].id)),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(height: 16),
                  if (view.isHost)
                    FilledButton(
                      key: const ValueKey('rematch'),
                      onPressed: () => ref
                          .read(gameProvider.notifier)
                          .send(const SimpleIntent('rematch')),
                      child: const Text('Rematch'),
                    )
                  else
                    const Text('Waiting for the host to start a rematch…',
                        textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () async {
                      await ref.read(gameProvider.notifier).leave();
                      await ref.read(localHostProvider.notifier).stop();
                    },
                    child: const Text('Home'),
                  ),
                ]),
          ),
        ),
      ),
    );
  }
}
