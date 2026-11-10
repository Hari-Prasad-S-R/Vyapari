import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    this.chat = const [],
    this.feed = const [],
  });

  /// Every game event received, in order, each with a rising sequence
  /// number (last 200). The board replays these one by one so moves,
  /// cards and payments are shown exactly as they happened.
  final List<(int, GameEvent)> feed;

  /// Recent chat messages, oldest first (memory only, last 50).
  final List<ChatBroadcast> chat;

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
    List<ChatBroadcast>? chat,
    List<(int, GameEvent)>? feed,
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
        chat: chat ?? this.chat,
        feed: feed ?? this.feed,
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
  int _feedSeq = 0;
  DateTime? _reconnectSince;
  DateTime _lastHeard = DateTime.now();
  Timer? _watchdog;
  final Map<int, DiceCommit> _commits = {};

  /// How long to keep trying to win the seat back (the server holds it 3 min).
  static const rejoinWindow = Duration(minutes: 3);

  /// A connection silent this long is treated as dead and reopened.
  static const silenceLimit = Duration(seconds: 20);

  /// Voice frames for the audio service.
  final voiceFrames = StreamController<VoiceFrame>.broadcast();

  @override
  GameView build() {
    ref.onDispose(() {
      _ping?.cancel();
      _watchdog?.cancel();
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
    String? sessionToken,
  }) async {
    await _close();
    _leaving = false;
    _uri = uri;
    _retries = 0;
    _reconnectSince = null;
    _hello = Hello(
        name: name,
        token: token,
        create: create,
        password: password,
        sessionToken: sessionToken);
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
      if (!identical(_t, t)) return; // a replaced connection
      _lastHeard = DateTime.now();
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
    _lastHeard = DateTime.now();
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 5),
        (_) => _t?.send(const SimpleIntent('ping')));
    _watchdog?.cancel();
    if (!state.offline) {
      _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
        // Half-open sockets (Wi-Fi blips, phone sleep) never report closing;
        // if the server has gone quiet, reopen the connection ourselves.
        if (identical(_t, t) &&
            state.status == ConnStatus.connected &&
            DateTime.now().difference(_lastHeard) > silenceLimit) {
          forceReconnect();
        }
      });
    }
    return welcomed.future
        .timeout(const Duration(seconds: 8), onTimeout: () => false);
  }

  void _onMessage(ServerMessage m) {
    switch (m) {
      case Welcome():
        _retries = 0;
        _reconnectSince = null;
        state = state.copyWith(
          status: ConnStatus.connected,
          me: m.playerId,
          sessionToken: m.sessionToken,
          state: m.state,
          // A created room gets its code from the server.
          roomCode: m.state.roomId,
          clearError: true,
        );
        _rememberSession();
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
      case ChatBroadcast():
        final chat = [...state.chat, m];
        state = state.copyWith(
            chat: chat.length > 50 ? chat.sublist(chat.length - 50) : chat);
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
    final feed = [
      ...state.feed,
      for (final e in p.events) (++_feedSeq, e),
    ];
    state = state.copyWith(
        state: next,
        lastEvents: p.events,
        feed: feed.length > 200 ? feed.sublist(feed.length - 200) : feed);
    if (next.phase == GamePhase.gameOver) forgetSession();
  }

  void _onClosed() {
    if (_leaving || state.offline) return;
    // Try to win the seat back with the session token (FR-RECON-1).
    final token = state.sessionToken;
    final uri = _uri;
    final hello = _hello;
    final since = _reconnectSince ??= DateTime.now();
    if (token == null ||
        uri == null ||
        hello == null ||
        DateTime.now().difference(since) > rejoinWindow) {
      state = state.copyWith(
          status: ConnStatus.closed,
          error: 'Lost the connection. Tap Rejoin on the home screen.');
      return;
    }
    state = state.copyWith(status: ConnStatus.reconnecting);
    // 0.5 s, 1 s, 2 s, then every 3 s.
    final delay = Duration(milliseconds: min(3000, 500 << min(_retries, 3)));
    _retries++;
    Timer(delay, () async {
      if (_leaving || state.status == ConnStatus.connected) return;
      try {
        final t = await ref.read(transportFactoryProvider)(uri);
        await _sub?.cancel();
        final old = _t;
        _t = null;
        unawaited(old?.close());
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

  /// Drops the current socket and reconnects with the session token
  /// (watchdog, app resumed, or the player tapped Reconnect).
  void forceReconnect() {
    if (_leaving || state.offline || state.sessionToken == null) return;
    final old = _t;
    _t = null;
    _sub?.cancel();
    unawaited(old?.close());
    _onClosed();
  }

  /// Called when the app returns to the foreground: check the line at once.
  void onResumed() {
    if (state.offline || state.me == null) return;
    if (state.status == ConnStatus.connected &&
        DateTime.now().difference(_lastHeard) < const Duration(seconds: 6)) {
      _t?.send(SyncMsg(state.state?.version ?? 0));
    } else {
      _retries = 0;
      forceReconnect();
    }
  }

  /// Rejoins a saved game (app restarted, phone rebooted, …).
  Future<bool> rejoin(LastSession s) => connect(
        Uri.parse(s.url),
        code: s.code,
        name: s.name,
        token: s.token,
        sessionToken: s.sessionToken,
        hosting: s.hosting,
      );

  Future<void> _rememberSession() async {
    final uri = _uri;
    final hello = _hello;
    final token = state.sessionToken;
    if (uri == null || hello == null || token == null || state.offline) return;
    await saveLastSession(LastSession(
      url: uri.toString(),
      code: state.roomCode,
      name: hello.name,
      token: hello.token,
      sessionToken: token,
      hosting: state.hosting,
    ));
  }

  /// Forgets the saved game (left on purpose or finished).
  Future<void> forgetSession() => saveLastSession(null);

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
    unawaited(forgetSession());
    _t?.send(const SimpleIntent('leave'));
    await _close();
    state = const GameView();
  }

  Future<void> _close() async {
    _ping?.cancel();
    _watchdog?.cancel();
    await _sub?.cancel();
    _sub = null;
    final t = _t;
    _t = null;
    await t?.close();
  }
}

/// A game this device can rejoin with its session token.
class LastSession {
  /// Creates a record.
  const LastSession({
    required this.url,
    required this.code,
    required this.name,
    required this.token,
    required this.sessionToken,
    this.hosting = false,
  });

  /// Server WebSocket URL.
  final String url;

  /// Room code.
  final String code;

  /// Nickname.
  final String name;

  /// Token.
  final Token token;

  /// Seat token.
  final String sessionToken;

  /// Whether this device hosted (the host must start its server again).
  final bool hosting;

  /// JSON form.
  Map<String, Object?> toJson() => {
        'url': url,
        'code': code,
        'name': name,
        'token': token.name,
        'sessionToken': sessionToken,
        'hosting': hosting,
      };

  /// Decodes a record.
  static LastSession? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      return LastSession(
        url: raw['url'] as String,
        code: raw['code'] as String,
        name: raw['name'] as String,
        token: Token.values.byName(raw['token'] as String),
        sessionToken: raw['sessionToken'] as String,
        hosting: raw['hosting'] as bool? ?? false,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Loads the saved game, if any.
Future<LastSession?> loadLastSession() async {
  try {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('last_session');
    return raw == null ? null : LastSession.fromJson(jsonDecode(raw));
  } catch (_) {
    return null;
  }
}

/// Saves (or with `null` clears) the game to rejoin.
Future<void> saveLastSession(LastSession? s) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (s == null) {
      await p.remove('last_session');
    } else {
      await p.setString('last_session', jsonEncode(s.toJson()));
    }
  } catch (_) {}
}
