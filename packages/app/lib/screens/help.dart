import 'package:flutter/material.dart';

/// How to play and how to host (VY-36).
class HelpScreen extends StatelessWidget {
  /// Creates the screen.
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('How to play')),
        body: ListView(padding: const EdgeInsets.all(16), children: const [
          _H('Goal'),
          _P('Buy cities, build houses and hotels, collect rent and trade. '
              'The last player who is not bankrupt wins — or the richest when time runs out.'),
          _H('Your turn'),
          _P('Roll the dice and move. Doubles roll again, but three doubles in a row '
              'sends you to Jail. Passing Start pays ₹2,00,000.'),
          _P('Land on an unowned city to buy it, or let it go to auction. '
              'Landing on someone else\'s city charges rent automatically.'),
          _H('Building'),
          _P('Own every city in a colour group to build. Build evenly: '
              'one house on each city before a second on any. Four houses become a hotel.'),
          _H('Vaaippu and Undiyal'),
          _P('Card tiles bring Diwali bonuses, traffic challans, wedding gifts and more.'),
          _H('Jail'),
          _P('Pay ₹50,000, use a get-out card, or try for doubles up to three times.'),
          _H('Talking'),
          _P('Hold the mic button to talk (up to 15 seconds) and release to send. '
              'Tap it to choose everyone, one player or a small group. There is no typed chat.'),
          _H('How to host (no internet)'),
          _P('1. Turn on your phone\'s hotspot (mobile data can stay off).'),
          _P('2. Tap Host a game. Share the room code or let friends scan the QR code.'),
          _P('3. Friends join your hotspot Wi-Fi and tap Join nearby.'),
          _P('Android keeps the game running with the screen off. On iPhone keep Vyapari open while hosting.'),
          _H('Playing online'),
          _P('Tap Join online, enter the server address and a room code, or create a new room.'),
        ]),
      );
}

class _H extends StatelessWidget {
  const _H(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _P extends StatelessWidget {
  const _P(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text));
}
