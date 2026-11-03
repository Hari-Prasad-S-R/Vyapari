import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import '../services/transport.dart';

/// Connection status.
enum ConnStatus { idle, connecting, connected, reconnecting, closed }

/// A short pop-up about money changing hands.
class Popup {
  /// Creates a pop-up.
  const Popup(this.text, this.at);

  /// Text.
  final String text;

  /// When it appeared (ms).
  final int at;
}

/// Everything the UI shows about the current game.
class GameView {
  /// Creates a view.
  const GameView({
    this.status = ConnStatus.idle,
    this.state,
    this.me,
    this.roomCode = '',
    this.sessionToken,
    this.error,
    this.errorCode,
    this.notice,
    this.paused = false,
    this.offline = false,
    this.hosting = false,
    this.hostAddress,
    this.dice = const [],
    this.emotes = const {},
    this.popups = const [],
    this.lastEvents = const [],
  });

  /// Connection status.
  final ConnStatus status;

  /// Mirrored server state.
  final GameState? state;

  /// My seat id.
  final String? me;

  /// Room code.
  final String roomCode;

  /// Session token for rejoining.
  final String? sessionToken;

  /// Last error shown to the user.
  final String? error;

  /// Last error code.
  final ErrorCode? errorCode;

  /// Last room notice.
  final String? notice;

  /// Whether the host paused the game.
  final bool paused;

  /// Playing offline against bots.
  final bool offline;

  /// This device hosts the server.
  final bool hosting;

  /// Host IP:port shown in the lobby when hosting.
  final String? hostAddress;

  /// Dice commits and reveals for the Verify view.
  final List<(DiceCommit?, DiceReveal)> dice;

  /// Active emotes per player: emote and time shown.
  final Map<String, (Emote, int)> emotes;

  /// Recent money pop-ups.
  final List<Popup> popups;

  /// Events from the latest patch (for animations).
  final List<GameEvent> lastEvents;

  /// My player.
  Player? get myPlayer => state?.player(me);

  /// Whether I am the host.
  bool get isHost => state != null && state!.hostId == me;

  /// Whether it is my turn.
  bool get myTurn => state != null && state!.currentPlayer == me;

  /// Copy with changes.
  GameView copyWith({
    ConnStatus? status,
    GameState? state,
    String? me,
    String? roomCode,
    String? sessionToken,
    String? error,
    bool clearError = false,
    ErrorCode? errorCode,
    String? notice,
    bool? paused,
    bool? offline,
    bool? hosting,
    String? hostAddress,
    List<(DiceCommit?, DiceReveal)>? dice,
    Map<String, (Emote, int)>? emotes,
    List<Popup>? popups,
    List<GameEvent>? lastEvents,
  }) =>
      GameView(
        status: status ?? this.status,
        state: state ?? this.state,
        me: me ?? this.me,
        roomCode: roomCode ?? this.roomCode,
        sessionToken: sessionToken ?? this.sessionToken,
        error: clearError ? null : (error ?? this.error),
        errorCode: clearError ? null : (errorCode ?? this.errorCode),
        notice: notice ?? this.notice,
        paused: paused ?? this.paused,
        offline: offline ?? this.offline,
        hosting: hosting ?? this.hosting,
        hostAddress: hostAddress ?? this.hostAddress,
        dice: dice ?? this.dice,
        emotes: emotes ?? this.emotes,
        popups: popups ?? this.popups,
        lastEvents: lastEvents ?? this.lastEvents,
      );
}

/// User-facing text for an error code.
String errorText(ErrorCode code, [String detail = '']) => switch (code) {
      ErrorCode.badCode => 'No game with that room code',
      ErrorCode.roomFull => 'Room is full',
      ErrorCode.versionMismatch => 'Please update the app',
      ErrorCode.badPassword => 'Wrong password',
      ErrorCode.rateLimited =>
        detail.isNotEmpty ? detail : 'Too many tries. Wait a moment.',
      ErrorCode.illegalPhase =>
        detail.isNotEmpty ? detail : 'Not allowed right now',
      ErrorCode.notYourTurn => 'Wait for your turn',
      ErrorCode.insufficientFunds => 'Not enough cash',
      ErrorCode.incompleteSet => 'You need the full colour set',
      ErrorCode.unevenBuild => 'Build evenly across the set',
      ErrorCode.noHousesLeft => 'The bank has no houses left',
      ErrorCode.noHotelsLeft => 'The bank has no hotels left',
      ErrorCode.mortgaged => 'Mortgaged',
      ErrorCode.hasBuildings => 'Sell the buildings first',
      ErrorCode.tradeInvalid => 'That trade is no longer valid',
      ErrorCode.hostOnly => 'Only the host can do that',
      ErrorCode.invalidAction =>
        "That move isn't possible any more (someone may have bid higher)",
      ErrorCode.notFound => 'That offer is no longer open',
      _ => detail.isNotEmpty ? detail : 'Something went wrong (${code.wire})',
    };

/// Function that opens a transport (overridable in tests).
typedef TransportFactory = Future<GameTransport> Function(Uri uri);

/// Opens real WebSocket transports.
final transportFactoryProvider =
    Provider<TransportFactory>((ref) => WsTransport.connect);

/// The game connection and mirrored state.
final gameProvider =
    NotifierProvider<GameController, GameView>(GameController.new);

/// Owns the connection to the authoritative server and mirrors its state.
class GameController extends Notifier<GameView> {
  GameTransport? _t;
  StreamSubscription<Incoming>? _sub;
  Timer? _ping;
  Uri? _uri;
  Hello? _hello;
  bool _leaving = false;
  int _retries = 0;
  final Map<int, DiceCommit> _commits = {};

  /// Voice frames for the audio service.
  final voiceFrames = StreamController<VoiceFrame>.broadcast();

  @override
  GameView build() {
    ref.onDispose(() {
      _ping?.cancel();
      _sub?.cancel();
      _t?.close();
    });
    return const GameView();
  }

  /// Joins (or creates) a room on the server at [uri].
  Future<bool> connect(
    Uri uri, {
    required String code,
    required String name,
    required Token token,
    bool create = false,
    String? password,
    bool hosting = false,
    String? hostAddress,
  }) async {
    await _close();
    _leaving = false;
    _uri = uri;
    _hello =
        Hello(name: name, token: token, create: create, password: password);
    state = GameView(
        status: ConnStatus.connecting,
        roomCode: code,
        hosting: hosting,
        hostAddress: hostAddress);
    try {
      final t = await ref.read(transportFactoryProvider)(uri);
      final ok = await _attach(t, code, _hello!);
      if (!ok) {
        // Refused (wrong code, full room…): drop the connection, keep the error.
        _leaving = true;
        await _close();
        state = state.copyWith(
            status: ConnStatus.closed, error: state.error ?? 'Could not join');
      }
      return ok;
    } catch (e) {
      state = state.copyWith(
          status: ConnStatus.closed, error: 'Could not reach the server');
      return false;
    }
  }

  /// Starts an offline game against bots on this device.
  Future<void> playOffline(GameTransport t,
      {required String name, required Token token}) async {
    await _close();
    _leaving = false;
    _uri = null;
    state = const GameView(
        status: ConnStatus.connecting, offline: true, roomCode: 'SOLO');
    _hello = Hello(name: name, token: token);
    await _attach(t, 'SOLO', _hello!);
  }

  Future<bool> _attach(GameTransport t, String code, Hello hello) async {
    _t = t;
    final welcomed = Completer<bool>();
    _sub = t.incoming.listen((e) {
      switch (e) {
        case IncomingMessage(:final message):
          if (message is Welcome && !welcomed.isCompleted) {
            welcomed.complete(true);
          }
          if (message is ErrorMsg &&
              !welcomed.isCompleted &&
              state.me == null) {
            welcomed.complete(false);
          }
          _onMessage(message);
        case IncomingVoice(:final frame):
          voiceFrames.add(frame);
        case IncomingClosed():
          _onClosed();
      }
    });
    t.send(hello, room: code);
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 10),
        (_) => _t?.send(const SimpleIntent('ping')));
    return welcomed.future
        .timeout(const Duration(seconds: 8), onTimeout: () => false);
  }

  void _onMessage(ServerMessage m) {
    switch (m) {
      case Welcome():
        _retries = 0;
        state = state.copyWith(
          status: ConnStatus.connected,
          me: m.playerId,
          sessionToken: m.sessionToken,
          state: m.state,
          clearError: true,
        );
      case StateMsg():
        state = state.copyWith(state: m.state);
      case PatchMsg():
        applyPatch(m);
      case DiceCommitMsg():
        _commits[m.commit.rollNumber] = m.commit;
      case DiceRevealMsg():
        state = state.copyWith(
            dice: [...state.dice, (_commits[m.reveal.rollNumber], m.reveal)]);
      case ErrorMsg():
        state = state.copyWith(
            error: errorText(m.code, m.message), errorCode: m.code);
      case EmoteBroadcast():
        state = state.copyWith(emotes: {
          ...state.emotes,
          m.from: (m.emote, DateTime.now().millisecondsSinceEpoch),
        });
      case NoticeMsg():
        switch (m.kind) {
          case 'paused':
            state = state.copyWith(paused: true, notice: m.text);
          case 'resumed':
            state = state.copyWith(paused: false, notice: m.text);
          case 'kicked':
            _leaving = true;
            state = state.copyWith(
                status: ConnStatus.closed, error: 'The host removed you');
          case 'pong':
            break;
          default:
            if (m.text.isNotEmpty) state = state.copyWith(notice: m.text);
        }
    }
  }

  /// Applies a patch; stale patches are ignored and gaps trigger a resync.
  void applyPatch(PatchMsg p) {
    final s = state.state;
    if (s == null) return;
    if (p.toVersion <= s.version) return; // stale
    final next = p.applyTo(s);
    if (next == null) {
      _t?.send(SyncMsg(s.version));
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final popups = [
      ...state.popups.where((x) => now - x.at < 4000),
      for (final e in p.events)
        if (const {
          'rent',
          'tax',
          'card',
          'bought',
          'auction_won',
          'pot',
          'salary',
          'bankrupt',
          'jailed'
        }.contains(e.type))
          Popup(e.text, now),
    ];
    state = state.copyWith(
        state: next,
        lastEvents: p.events,
        popups: popups.length > 4 ? popups.sublist(popups.length - 4) : popups);
  }

  void _onClosed() {
    if (_leaving || state.offline) return;
    // Try to win the seat back with the session token (FR-RECON-1).
    final token = state.sessionToken;
    final uri = _uri;
    final hello = _hello;
    if (token == null || uri == null || hello == null || _retries > 30) {
      state = state.copyWith(status: ConnStatus.closed, error: 'Disconnected');
      return;
    }
    state = state.copyWith(status: ConnStatus.reconnecting);
    final delay = Duration(seconds: _retries < 3 ? 1 : 5);
    _retries++;
    Timer(delay, () async {
      if (_leaving) return;
      try {
        final t = await ref.read(transportFactoryProvider)(uri);
        await _sub?.cancel();
        await _attach(
            t,
            state.roomCode,
            Hello(
                name: hello.name,
                token: hello.token,
                sessionToken: token,
                lastVersion: state.state?.version));
      } catch (_) {
        _onClosed();
      }
    });
  }

  /// Sends an intent to the server.
  void send(ClientMessage m) {
    state = state.copyWith(clearError: true);
    _t?.send(m);
  }

  /// Sends the intent for an engine action.
  void act(GameAction a) {
    final m = intentFor(a);
    if (m != null) send(m);
  }

  /// Sends a recorded clip.
  void sendVoice(Uint8List frame) => _t?.sendVoice(frame);

  /// Replaces the view (tests and previews only).
  @visibleForTesting
  void debugSetView(GameView v) => state = v;

  /// Clears the shown error.
  void clearError() => state = state.copyWith(clearError: true);

  /// Leaves the game and closes the connection.
  Future<void> leave() async {
    _leaving = true;
    _t?.send(const SimpleIntent('leave'));
    await _close();
    state = const GameView();
  }

  Future<void> _close() async {
    _ping?.cancel();
    await _sub?.cancel();
    _sub = null;
    final t = _t;
    _t = null;
    await t?.close();
  }
}
