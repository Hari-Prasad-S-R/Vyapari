import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyapari_app/screens/game.dart';
import 'package:vyapari_app/services/voice.dart';
import 'package:vyapari_app/state/game_controller.dart';
import 'package:vyapari_app/widgets/chat.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import 'helpers.dart';

void main() {
  testWidgets(
      'iPhone: chat button replaces talk; typed message is sent to the picked players',
      (tester) async {
    final s = started(n: 4);
    final fake = FakeTransport(
        reply: (m) => m is Hello
            ? [Welcome(playerId: 'p0', sessionToken: 't', state: s)]
            : []);
    final c = await pumpWith(tester, const GameScreen(),
        view: GameView(state: s, me: 'p0'),
        size: const Size(800, 1000),
        overrides: [textChatProvider.overrideWithValue(true)]);
    await tester.runAsync(() => c
        .read(gameProvider.notifier)
        .playOffline(fake, name: 'A', token: Token.kite));
    await tester.pump();
    expect(find.byKey(const ValueKey('talk-button')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chat-button')));
    await tester.pumpAndSettle();
    c.read(voiceProvider.notifier).setRecipients(['p2']);
    await tester.pump();
    expect(find.text('To: Player 2'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('chat-field')).last, 'Deal on Chennai?');
    await tester.tap(find.byKey(const ValueKey('chat-send')).last);
    await tester.pump();
    final sent = fake.sent.whereType<ChatMsg>().single;
    expect(sent.text, 'Deal on Chennai?');
    expect(sent.to, ['p2']);
  });

  testWidgets('Android: no text box, but chat from iPhone players shows up',
      (tester) async {
    final s = started();
    final c = await pumpWith(tester, const GameScreen(),
        view: GameView(state: s, me: 'p1'), size: const Size(1440, 900));
    expect(find.byKey(const ValueKey('talk-button')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    c
        .read(gameProvider.notifier)
        .debugSetView(GameView(state: s, me: 'p1', chat: const [
          ChatBroadcast(id: 'm1', from: 'p0', text: 'Semma move!'),
        ]));
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-banner')), findsOneWidget);
    expect(find.textContaining('Semma move!'), findsWidgets);
    expect(find.byType(TextField), findsNothing, reason: 'reading only');
    await tester.pump(const Duration(seconds: 6));
    expect(find.byKey(const ValueKey('chat-banner')), findsNothing);
  });

  testWidgets('messages from players I muted are hidden', (tester) async {
    final s = started();
    final c = await pumpWith(tester, const Scaffold(body: ChatFeed()),
        view: GameView(state: s, me: 'p1', chat: const [
          ChatBroadcast(id: 'm1', from: 'p0', text: 'hello'),
          ChatBroadcast(id: 'm2', from: 'p2', text: 'spam'),
        ]));
    c.read(voiceProvider.notifier).toggleMute('p2');
    await tester.pump();
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('spam'), findsNothing);
  });
}
