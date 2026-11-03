import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import '../services/voice.dart';
import '../state/game_controller.dart';
import '../state/profile.dart';
import '../ui.dart';

/// Floating push-to-talk button: hold to record (15 s max), release to
/// send; tap to pick who hears.
class TalkButton extends ConsumerWidget {
  /// Creates the button.
  const TalkButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(voiceProvider);
    final game = ref.watch(gameProvider);
    final names = {
      for (final p in game.state?.players ?? <Player>[]) p.id: p.name
    };
    final label = v.recipients.isEmpty
        ? 'Everyone'
        : v.recipients.map((id) => names[id] ?? '?').join(', ');
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Hold to talk to $label',
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (v.message != null)
              Container(
                constraints: const BoxConstraints(maxWidth: 220),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(v.message!,
                    style: TextStyle(
                        color: scheme.onErrorContainer, fontSize: 12)),
              ),
            Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(v.recipients.isEmpty ? '📢 $label' : '🔒 $label',
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              key: const ValueKey('talk-button'),
              onTap: () => showRecipientPicker(context, ref),
              onLongPressStart: (_) =>
                  ref.read(voiceProvider.notifier).startTalking(),
              onLongPressEnd: (_) =>
                  ref.read(voiceProvider.notifier).stopAndSend(),
              child: SizedBox(
                width: 68,
                height: 68,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox(
                    width: 68,
                    height: 68,
                    child: CircularProgressIndicator(
                      value: v.recording
                          ? v.elapsedMs / maxClip.inMilliseconds
                          : 0,
                      strokeWidth: 5,
                      color: Colors.redAccent,
                    ),
                  ),
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: v.recording ? Colors.redAccent : saffron,
                    child: Icon(v.recording ? Icons.mic : Icons.mic_none,
                        color: Colors.white, size: 30),
                  ),
                  if (v.recording)
                    Positioned(
                      bottom: 0,
                      child: Text(
                          '${((maxClip.inMilliseconds - v.elapsedMs) / 1000).ceil()}s',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ]),
              ),
            ),
          ]),
    );
  }
}

/// Bottom sheet to choose Broadcast, one player, or a group of 2–3.
Future<void> showRecipientPicker(BuildContext context, WidgetRef ref) {
  final game = ref.read(gameProvider);
  final others = (game.state?.players ?? const <Player>[])
      .where((p) => p.id != game.me && !p.isBot)
      .toList();
  var chosen = {...ref.read(voiceProvider).recipients};
  final lastGroup = ref.read(profileProvider).lastGroup;
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => StatefulBuilder(builder: (context, setState) {
      void apply() {
        ref.read(voiceProvider.notifier).setRecipients(chosen.toList());
        if (chosen.length > 1) {
          ref.read(profileProvider.notifier).setLastGroup(chosen.toList());
        }
      }

      return SafeArea(
        child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              Text('Who hears you?',
                  style: Theme.of(context).textTheme.titleMedium),
              ListTile(
                key: const ValueKey('recipient-broadcast'),
                leading: Icon(chosen.isEmpty
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked),
                title: const Text('📢 Everyone (broadcast)'),
                onTap: () => setState(() {
                  chosen = {};
                  apply();
                }),
              ),
              if (lastGroup.length > 1 &&
                  lastGroup.every((id) => others.any((p) => p.id == id)))
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(
                      'Last group: ${lastGroup.map((id) => others.firstWhere((p) => p.id == id).name).join(', ')}'),
                  onTap: () => setState(() {
                    chosen = {...lastGroup};
                    apply();
                  }),
                ),
              const Divider(),
              const Text('Private to 1–3 players:'),
              for (final p in others)
                CheckboxListTile(
                  key: ValueKey('recipient-${p.id}'),
                  value: chosen.contains(p.id),
                  title: Text('${tokenEmoji(p.token)} ${p.name}'),
                  onChanged: (on) => setState(() {
                    if (on == true && chosen.length < 3) {
                      chosen.add(p.id);
                    } else {
                      chosen.remove(p.id);
                    }
                    apply();
                  }),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done')),
              ),
            ]),
      );
    }),
  );
}

/// Top banner while a clip plays: sender, token and a "private" badge.
class SpeakingBanner extends ConsumerWidget {
  /// Creates the banner.
  const SpeakingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(voiceProvider.select((v) => v.speaking));
    final s = ref.watch(gameProvider.select((g) => g.state));
    if (h == null || s == null) return const SizedBox.shrink();
    final p = s.player(h.from);
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.graphic_eq, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 6),
          Text(
              '${p == null ? '' : tokenEmoji(p.token)} ${p?.name ?? 'Someone'} is speaking',
              style: const TextStyle(color: Colors.white)),
          if (h.isPrivate) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(6)),
              child: const Text('private',
                  style: TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Per-player mute, mute all, volume, replay last 5 and host room-mute.
Future<void> showVoiceSettings(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final v = ref.watch(voiceProvider);
        final game = ref.watch(gameProvider);
        final s = game.state;
        final ctl = ref.read(voiceProvider.notifier);
        return SafeArea(
          child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(12),
              children: [
                Text('Voice', style: Theme.of(context).textTheme.titleMedium),
                SwitchListTile(
                  title: const Text('Mute everyone'),
                  value: v.muteAll,
                  onChanged: ctl.setMuteAll,
                ),
                Row(children: [
                  const Icon(Icons.volume_up),
                  Expanded(
                    child: Slider(
                        value: v.volume.toDouble(), onChanged: ctl.setVolume),
                  ),
                ]),
                for (final p in (s?.players ?? const <Player>[])
                    .where((p) => p.id != game.me && !p.isBot))
                  ListTile(
                    title: Text('${tokenEmoji(p.token)} ${p.name}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: v.muted.contains(p.id)
                            ? 'Unmute for me'
                            : 'Mute for me',
                        icon: Icon(v.muted.contains(p.id)
                            ? Icons.volume_off
                            : Icons.volume_up),
                        onPressed: () => ctl.toggleMute(p.id),
                      ),
                      if (game.isHost)
                        IconButton(
                          tooltip: 'Mute for the whole room',
                          icon: const Icon(Icons.block),
                          onPressed: () => ref.read(gameProvider.notifier).send(
                              PlayerTargetMsg('mute_player', p.id, flag: true)),
                        ),
                    ]),
                  ),
                const Divider(),
                Text('Replay recent clips',
                    style: Theme.of(context).textTheme.titleSmall),
                if (v.recent.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(8), child: Text('No clips yet')),
                for (final f in v.recent.reversed)
                  ListTile(
                    leading: const Icon(Icons.replay),
                    title: Text(s?.player(f.header.from)?.name ?? 'Someone'),
                    subtitle: Text(
                        '${(f.header.durationMs / 1000).toStringAsFixed(1)} s${f.header.isPrivate ? ' · private' : ''}'),
                    onTap: () => ctl.replay(f),
                  ),
              ]),
        );
      }),
    );
