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
        overrides: [
          chatOnlyProvider.overrideWithValue(true),
          transportFactoryProvider.overrideWithValue((_) async => fake),
        ]);
    await tester.runAsync(() => c.read(gameProvider.notifier).connect(
        Uri.parse('ws://test/ws'),
        code: '4821',
        name: 'A',
        token: Token.kite));
    await tester.pump();
    expect(find.byKey(const ValueKey('talk-button')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chat-button')));
    await settleSheet(tester); // dice keep pulsing, so step frames
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

  testWidgets('Android: chat and talk buttons; incoming chat shows up',
      (tester) async {
    final s = started();
    final c = await pumpWith(tester, const GameScreen(),
        view: GameView(state: s, me: 'p1'), size: const Size(1440, 900));
    expect(find.byKey(const ValueKey('talk-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-button')), findsOneWidget);
    c
        .read(gameProvider.notifier)
        .debugSetView(GameView(state: s, me: 'p1', chat: const [
          ChatBroadcast(id: 'm1', from: 'p0', text: 'Semma move!'),
        ]));
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-banner')), findsOneWidget);
    expect(find.textContaining('Semma move!'), findsWidgets);
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

  testWidgets('Android players can type and send too', (tester) async {
    final s = started(n: 3);
    final fake = FakeTransport(
        reply: (m) => m is Hello
            ? [Welcome(playerId: 'p1', sessionToken: 't', state: s)]
            : []);
    final c = await pumpWith(tester, const GameScreen(),
        view: GameView(state: s, me: 'p1'),
        size: const Size(800, 1000),
        overrides: [
          transportFactoryProvider.overrideWithValue((_) async => fake)
        ]);
    await tester.runAsync(() => c.read(gameProvider.notifier).connect(
        Uri.parse('ws://test/ws'),
        code: '4821',
        name: 'B',
        token: Token.kite));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-button')));
    await settleSheet(tester);
    await tester.enterText(
        find.byKey(const ValueKey('chat-field')).last, 'Ok, deal!');
    await tester.tap(find.byKey(const ValueKey('chat-send')).last);
    await tester.pump();
    final sent = fake.sent.whereType<ChatMsg>().single;
    expect(sent.text, 'Ok, deal!');
    expect(sent.to, isEmpty, reason: 'broadcast by default');
  });
}
