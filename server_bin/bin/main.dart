// Vyapari online server.
//
// Environment:
//   VYAPARI_PORT    WebSocket/HTTP port (default 47800)
//   VYAPARI_BOARD   folder with board.json and cards.json
//                   (default assets/boards/india)
//   VYAPARI_DB      SQLite file for saves (default data/vyapari.db)
//   VYAPARI_LOCAL   set to 1 to run in local-host mode (4-digit code)
//   VYAPARI_WEB     folder of `flutter build web` output to serve (optional)
import 'dart:async';
import 'dart:io';

import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_server/vyapari_server.dart';

Future<void> main(List<String> args) async {
  // Flags (--port=, --board=, --db=, --web=, --local) override environment.
  final env = {
    ...Platform.environment,
    for (final a in args)
      if (a.startsWith('--'))
        'VYAPARI_${a.substring(2).split('=').first.toUpperCase()}':
            a.contains('=') ? a.substring(a.indexOf('=') + 1) : '1',
  };
  final port = int.tryParse(env['VYAPARI_PORT'] ?? '') ?? defaultPort;
  final boardDir = env['VYAPARI_BOARD'] ?? 'assets/boards/india';
  final dbPath = env['VYAPARI_DB'] ?? 'data/vyapari.db';
  final local = env['VYAPARI_LOCAL'] == '1';

  void log(String line) =>
      stdout.writeln('${DateTime.now().toUtc().toIso8601String()} $line');

  final BoardData board;
  try {
    board = BoardData.parse(
      File('$boardDir/board.json').readAsStringSync(),
      File('$boardDir/cards.json').readAsStringSync(),
    );
  } on Object catch (e) {
    stderr.writeln('Cannot load board from $boardDir: $e');
    exit(2);
  }

  final GameStore store;
  if (local) {
    store = JsonFileStore(Directory('data/saves'));
  } else {
    File(dbPath).parent.createSync(recursive: true);
    store = SqliteStore(dbPath);
  }

  final server = GameServer(
    board: board,
    config: ServerConfig(online: !local),
    store: store,
    log: log,
    webRoot: env['VYAPARI_WEB'],
  );
  final errors = <String>[];
  final restored = server.hub.restoreAll(errors: errors);
  for (final e in errors) {
    log('skipped save: $e');
  }
  log('restored $restored saved room(s)');
  if (local && server.hub.rooms.isEmpty) {
    final room = server.hub.createRoom();
    log('local room code ${room.code}');
  }
  await server.start(port: port);

  final stop = Completer<void>();
  for (final sig in [
    ProcessSignal.sigint,
    if (!Platform.isWindows) ProcessSignal.sigterm
  ]) {
    sig.watch().listen((_) {
      if (!stop.isCompleted) stop.complete();
    });
  }
  await stop.future;
  log('shutting down; saving rooms');
  for (final r in server.hub.rooms.values) {
    r.save();
  }
  await server.stop();
  exit(0);
}
