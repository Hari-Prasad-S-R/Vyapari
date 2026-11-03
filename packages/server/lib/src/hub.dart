import 'dart:async';
import 'dart:typed_data';

import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import 'room.dart';
import 'store.dart';
import 'support.dart';

/// Owns all rooms on a server and routes connections to them.
class RoomHub {
  /// Creates a hub.
  RoomHub({
    required this.board,
    this.config = const ServerConfig(),
    GameStore? store,
    RandomSource? rng,
    this.clock = systemClock,
  })  : store = store ?? MemoryStore(),
        rng = rng ?? SecureRandomSource() {
    blocker = AttemptBlocker(
        maxAttempts: config.maxFailedJoins,
        blockTime: config.joinBlockTime,
        clock: clock);
    _sweep = Timer.periodic(config.heartbeatSweep, (_) {
      for (final r in rooms.values.toList()) {
        r.sweepHeartbeats();
      }
    });
  }

  /// Board every room plays on.
  final BoardData board;

  /// Tunables.
  final ServerConfig config;

  /// Save store.
  final GameStore store;

  /// Secure randomness.
  final RandomSource rng;

  /// Clock.
  final Clock clock;

  /// Wrong code/password limiter.
  late final AttemptBlocker blocker;

  /// Rooms by code.
  final Map<String, Room> rooms = {};
  late final Timer _sweep;

  /// Creates a room with a fresh code (or [code]).
  Room createRoom({String? password, String? code}) {
    var c = code ?? newRoomCode(rng, online: config.online);
    while (code == null && rooms.containsKey(c)) {
      c = newRoomCode(rng, online: config.online);
    }
    final room = Room(
      code: c,
      board: board,
      config: config,
      rng: rng,
      password: (password == null || password.isEmpty) ? null : password,
      isLocal: !config.online,
      clock: clock,
      onSave: _save,
      onEmpty: _empty,
    );
    rooms[c] = room;
    return room;
  }

  void _save(Room room) {
    try {
      store.save(room.code, room.snapshot(), clock());
    } catch (_) {
      // Saving must never break play.
    }
  }

  void _empty(Room room) {
    if (!config.online) return; // the local host's room stays open
    if (room.state.players.any((p) => !p.isBot)) return;
    room.dispose();
    rooms.remove(room.code);
    store.delete(room.code);
  }

  /// Loads a saved room (local resume). Returns `null` if missing.
  Room? resume(String code) {
    final saved = store.load(code);
    if (saved == null) return null;
    final room = Room.restore(saved.json,
        board: board,
        config: config,
        rng: rng,
        clock: clock,
        onSave: _save,
        onEmpty: _empty);
    rooms[room.code]?.dispose();
    rooms[room.code] = room;
    return room;
  }

  /// Restores every saved room that has not finished (online restart).
  /// Corrupt saves are reported in [errors] and skipped.
  int restoreAll({List<String>? errors}) {
    var n = 0;
    for (final saved in store.list(errors: errors)) {
      try {
        final phase = (saved.json['state'] as Map)['phase'];
        if (phase == GamePhase.gameOver.name) continue;
        resume(saved.code);
        n++;
      } catch (e) {
        errors?.add('room ${saved.code}: $e');
      }
    }
    return n;
  }

  /// Rooms open to join from a public lobby list.
  List<Map<String, Object?>> publicRooms() => [
        for (final r in rooms.values)
          if (r.state.phase == GamePhase.lobby && r.password == null)
            {
              'code': r.code,
              'players': r.state.players.length,
              'maxPlayers': r.state.config.maxPlayers,
              'host': r.state.player(r.state.hostId)?.name,
            },
      ];

  /// Starts handling a new connection.
  Connection connect(Peer peer) => Connection._(this, peer);

  /// Stops all rooms.
  void dispose() {
    _sweep.cancel();
    for (final r in rooms.values) {
      r.dispose();
    }
    rooms.clear();
  }
}

/// State of one client connection.
class Connection {
  Connection._(this.hub, this.peer);

  /// Hub.
  final RoomHub hub;

  /// Transport.
  final Peer peer;

  /// Joined room.
  Room? room;

  /// Seat id once joined.
  String? playerId;

  void _reply(ServerMessage m) => peer.sendText(Envelope(m).encode());

  void _refuse(ErrorCode code,
      {String? refId, String message = '', bool close = false}) {
    _reply(ErrorMsg(code, refId: refId, message: message));
    if (close) peer.close();
  }

  /// Handles a text frame.
  void onText(String text) {
    final decoded = decodeFrame(text);
    if (!decoded.ok) {
      final e = decoded.error!;
      _refuse(e.code,
          refId: e.id,
          message: e.code == ErrorCode.versionMismatch
              ? 'Please update the app'
              : e.detail,
          close: e.code == ErrorCode.versionMismatch && room == null);
      return;
    }
    final env = decoded.envelope!;
    final r = room;
    if (r != null) {
      r.onMessage(playerId!, env);
      return;
    }
    final m = env.message;
    if (m is! Hello) {
      _refuse(ErrorCode.unknownMessage,
          refId: env.id, message: 'Send hello first');
      return;
    }
    _hello(env, m);
  }

  void _hello(Envelope env, Hello h) {
    final key = peer.remote;
    if (hub.blocker.isBlocked(key)) {
      _refuse(ErrorCode.rateLimited,
          refId: env.id, message: 'Too many wrong attempts. Wait a minute.');
      return;
    }
    Room? target;
    if (h.create) {
      if (!hub.config.online) {
        target = hub.rooms.values.isEmpty
            ? hub.createRoom()
            : hub.rooms.values.first;
      } else {
        if (hub.rooms.length >= hub.config.maxRooms) {
          _refuse(ErrorCode.roomFull, refId: env.id, message: 'Server is full');
          return;
        }
        target = hub.createRoom(password: h.password);
      }
    } else {
      target = hub.rooms[env.room.toUpperCase()];
      if (target == null &&
          env.room.isEmpty &&
          !hub.config.online &&
          hub.rooms.length == 1) {
        target = hub.rooms.values.first;
      }
    }
    if (target == null) {
      hub.blocker.fail(key);
      _refuse(ErrorCode.badCode,
          refId: env.id, message: 'No room with that code');
      return;
    }
    final rejoining =
        h.sessionToken != null && target.sessions.containsKey(h.sessionToken);
    if (!h.create &&
        !rejoining &&
        target.password != null &&
        target.password != h.password) {
      hub.blocker.fail(key);
      _refuse(ErrorCode.badPassword, refId: env.id, message: 'Wrong password');
      return;
    }
    final out = target.join(peer, h);
    if (out.error != null) {
      _refuse(out.error!,
          refId: env.id,
          message: switch (out.error!) {
            ErrorCode.roomFull => 'Room is full',
            ErrorCode.illegalPhase => 'The game has already started',
            _ => '',
          });
      return;
    }
    hub.blocker.succeed(key);
    room = target;
    playerId = out.playerId;
  }

  /// Handles a binary (voice) frame.
  void onBinary(Uint8List bytes) {
    final r = room;
    if (r == null) {
      _refuse(ErrorCode.unknownMessage, message: 'Send hello first');
      return;
    }
    r.onVoice(playerId!, bytes);
  }

  /// The socket closed.
  void onDone() => room?.onClosed(playerId!, peer);
}
