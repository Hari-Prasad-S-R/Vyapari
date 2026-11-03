import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vyapari_core/vyapari_core.dart';

import 'screens/game.dart';
import 'screens/home.dart';
import 'screens/lobby.dart';
import 'screens/results.dart';
import 'state/game_controller.dart';
import 'ui.dart';

/// Loads the India board from bundled JSON (`assets/boards/india`).
final boardProvider = FutureProvider<BoardData>((ref) async {
  final board = await rootBundle.loadString('assets/boards/india/board.json');
  final cards = await rootBundle.loadString('assets/boards/india/cards.json');
  return BoardData.parse(board, cards);
});

/// Root widget.
class VyapariApp extends StatelessWidget {
  /// Creates the app.
  const VyapariApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Vyapari',
        debugShowCheckedModeBanner: false,
        theme: vyapariTheme(Brightness.light),
        darkTheme: vyapariTheme(Brightness.dark),
        home: const AppShell(),
      );
}

/// Picks the screen from the connection and game phase:
/// Home → Lobby → Game → Results.
class AppShell extends ConsumerWidget {
  /// Creates the shell.
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(gameProvider);
    final s = view.state;
    if (s == null || view.me == null) return const HomeScreen();
    return switch (s.phase) {
      GamePhase.lobby => const LobbyScreen(),
      GamePhase.gameOver => const ResultsScreen(),
      _ => const GameScreen(),
    };
  }
}
