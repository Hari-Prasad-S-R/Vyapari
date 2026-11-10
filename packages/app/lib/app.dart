import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
/// Home → Lobby → Game → Results. Also keeps the screen awake while in a
/// room (a sleeping phone drops Wi-Fi) and checks the connection the moment
/// the app comes back to the foreground.
class AppShell extends ConsumerStatefulWidget {
  /// Creates the shell.
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  bool _awake = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _keepAwake(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(gameProvider.notifier).onResumed();
    }
  }

  void _keepAwake(bool on) {
    if (on == _awake) return;
    _awake = on;
    WakelockPlus.toggle(enable: on).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(gameProvider);
    final s = view.state;
    _keepAwake(s != null && view.me != null && s.phase != GamePhase.gameOver);
    if (s == null || view.me == null) return const HomeScreen();
    return switch (s.phase) {
      GamePhase.lobby => const LobbyScreen(),
      GamePhase.gameOver => const ResultsScreen(),
      _ => const GameScreen(),
    };
  }
}
