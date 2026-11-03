import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import '../services/voice.dart';
import '../state/game_controller.dart';
import '../ui.dart';
import 'talk.dart';

/// Whether this device types chat instead of push-to-talk. iPhones (app
/// and Safari) cannot reliably play the Opus clips other phones send, so
/// they get typed chat; everyone else keeps voice and reads chat.
final textChatProvider =
    Provider<bool>((ref) => defaultTargetPlatform == TargetPlatform.iOS);

/// Talk button, or chat button on devices that type.
class CommsButton extends ConsumerWidget {
  /// Creates the button.
  const CommsButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ref.watch(textChatProvider) ? const ChatButton() : const TalkButton();
}

/// Floating chat button with a count of messages since it was last opened.
class ChatButton extends ConsumerStatefulWidget {
  /// Creates the button.
  const ChatButton({super.key});

  @override
  ConsumerState<ChatButton> createState() => _ChatButtonState();
}

class _ChatButtonState extends ConsumerState<ChatButton> {
  int _seen = 0;

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(gameProvider.select((g) => g.chat.length));
    final unread = count - _seen;
    return Badge(
      isLabelVisible: unread > 0,
      label: Text('$unread'),
      child: FloatingActionButton(
        key: const ValueKey('chat-button'),
        backgroundColor: saffron,
        tooltip: 'Chat',
        onPressed: () async {
          await showChatSheet(context);
          if (mounted) {
            setState(() => _seen = ref.read(gameProvider).chat.length);
          }
        },
        child: const Icon(Icons.chat_bubble, color: Colors.white),
      ),
    );
  }
}

/// Opens the chat sheet (messages, recipients, text box).
Future<void> showChatSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.6,
          child: const ChatPanel(),
        ),
      ),
    );

/// Message list plus, on typing devices, the text box.
class ChatPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const ChatPanel({super.key});

  @override
  ConsumerState<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends ConsumerState<ChatPanel> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    final to = ref.read(voiceProvider).recipients;
    ref.read(gameProvider.notifier).send(ChatMsg(text, to: to));
    _text.clear();
  }

  @override
  Widget build(BuildContext context) {
    final canType = ref.watch(textChatProvider);
    final view = ref.watch(gameProvider);
    final to = ref.watch(voiceProvider.select((v) => v.recipients));
    final names = {
      for (final p in view.state?.players ?? <Player>[]) p.id: p.name
    };
    return Column(children: [
      const Expanded(child: ChatFeed()),
      if (canType)
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('chat-recipients'),
                  onPressed: () => showRecipientPicker(context, ref),
                  icon: Icon(to.isEmpty ? Icons.campaign : Icons.lock),
                  label: Text(to.isEmpty
                      ? 'To: everyone'
                      : 'To: ${to.map((id) => names[id] ?? '?').join(', ')}'),
                ),
              ),
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('chat-field'),
                    controller: _text,
                    maxLength: maxChatLength,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(),
                        counterText: ''),
                  ),
                ),
                IconButton(
                  key: const ValueKey('chat-send'),
                  tooltip: 'Send',
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ]),
            ]),
          ),
        ),
    ]);
  }
}

/// Chat messages (newest at the bottom); players I muted are hidden.
class ChatFeed extends ConsumerWidget {
  /// Creates the feed.
  const ChatFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(gameProvider);
    final muted =
        ref.watch(voiceProvider.select((v) => v.muteAll ? null : v.muted));
    final s = view.state;
    final msgs = view.chat
        .where((m) => muted != null && !muted.contains(m.from))
        .toList();
    if (msgs.isEmpty) {
      return const Center(child: Text('No messages yet'));
    }
    return ListView(
      key: const ValueKey('chat-feed'),
      reverse: true,
      padding: const EdgeInsets.all(8),
      children: [
        for (final m in msgs.reversed)
          Align(
            alignment: m.from == view.me
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: m.from == view.me
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s?.player(m.from)?.name ?? 'Someone'}${m.isPrivate ? ' · private' : ''}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: s == null ? null : playerColor(s, m.from)),
                    ),
                    Text(m.text),
                  ]),
            ),
          ),
      ],
    );
  }
}

/// Briefly shows the newest message from someone else at the top.
class ChatBanner extends ConsumerStatefulWidget {
  /// Creates the banner.
  const ChatBanner({super.key});

  @override
  ConsumerState<ChatBanner> createState() => _ChatBannerState();
}

class _ChatBannerState extends ConsumerState<ChatBanner> {
  String? _shownId;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(gameProvider);
    final voice = ref.watch(voiceProvider);
    final last = view.chat.isEmpty ? null : view.chat.last;
    if (last == null ||
        last.from == view.me ||
        voice.muteAll ||
        voice.muted.contains(last.from)) {
      return const SizedBox.shrink();
    }
    if (last.id != _shownId) {
      _shownId = last.id;
      _timer?.cancel();
      _timer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() {});
      });
    }
    if (!(_timer?.isActive ?? false)) return const SizedBox.shrink();
    final name = view.state?.player(last.from)?.name ?? 'Someone';
    return Material(
      key: const ValueKey('chat-banner'),
      color: Colors.black87,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showChatSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Text(
              '💬 $name${last.isPrivate ? ' (private)' : ''}: ${last.text}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}
