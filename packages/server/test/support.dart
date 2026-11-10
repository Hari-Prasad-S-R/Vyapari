import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';
import 'package:vyapari_server/vyapari_server.dart';
import 'package:web_socket_channel/io.dart';

/// The India board.
BoardData india() {
  var dir = Directory.current;
  while (!Directory('${dir.path}/assets/boards/india').existsSync()) {
    dir = dir.parent;
  }
  return BoardData.parse(
    File('${dir.path}/assets/boards/india/board.json').readAsStringSync(),
    File('${dir.path}/assets/boards/india/cards.json').readAsStringSync(),
  );
}

/// Fast settings for tests.
const testConfig = ServerConfig(
  paceAnimations: false,
  botDelay: Duration.zero,
  auctionTime: Duration(milliseconds: 150),
  tradeReviewDelay: Duration.zero,
  rejoinWindow: Duration(seconds: 2),
  heartbeatSweep: Duration(milliseconds: 200),
  heartbeatTimeout: Duration(seconds: 20),
);

/// A headless player over a real WebSocket. Mirrors server state from
/// `welcome`/`state`/`patch` and can drive itself with a core bot.
class TestClient {
  TestClient._(this._ws, this.name);

  /// Connects to [port] on localhost.
  static Future<TestClient> connect(int port, String name) async {
    final ws = IOWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$port/ws'));
    await ws.ready;
    final c = TestClient._(ws, name);
    c._sub = ws.stream.listen(c._onData, onDone: () {
      c.closed = true;
      c._changes.add(null);
    });
    return c;
  }

  final IOWebSocketChannel _ws;
  late final StreamSubscription<dynamic> _sub;

  /// Nickname.
  final String name;

  /// Mirrored state.
  GameState? state;

  /// Seat id.
  String? playerId;

  /// Session token.
  String? sessionToken;

  /// All server messages received.
  final List<ServerMessage> received = [];

  /// Binary voice frames received.
  final List<VoiceFrame> voice = [];

  /// Errors received.
  List<ErrorMsg> get errors => received.whereType<ErrorMsg>().toList();

  /// Whether the socket closed.
  bool closed = false;

  /// Arrival time of each patch toVersion (ms).
  final Map<int, int> patchArrivals = {};

  /// Log events in arrival order.
  final List<GameEvent> events = [];

  final _changes = StreamController<void>.broadcast();
  Bot? brain;
  int _actedOn = -1;
  int _seq = 0;

  void _onData(dynamic data) {
    if (data is List<int>) {
      final f = VoiceFrame.decode(data);
      if (f != null) voice.add(f);
      _changes.add(null);
      return;
    }
    final r = decodeFrame(data as String);
    if (!r.ok) return;
    final m = r.envelope!.message as ServerMessage;
    received.add(m);
    switch (m) {
      case Welcome():
        playerId = m.playerId;
        sessionToken = m.sessionToken;
        state = m.state;
      case StateMsg():
        state = m.state;
      case ErrorMsg():
        // A rejected (stale) intent: think again on the current state.
        _actedOn = -1;
      case PatchMsg():
        patchArrivals[m.toVersion] = DateTime.now().millisecondsSinceEpoch;
        events.addAll(m.events);
        final s = state;
        final next = s == null ? null : m.applyTo(s);
        if (next != null) {
          state = next;
        } else if (s != null && m.toVersion > s.version) {
          send(SyncMsg(s.version));
        }
      default:
        break;
    }
    _changes.add(null);
    _think();
  }

  /// Sends [m].
  void send(ClientMessage m, {String room = ''}) =>
      _ws.sink.add(Envelope(m, id: '$name-${_seq++}', room: room).encode());

  /// Sends raw text.
  void sendRaw(String text) => _ws.sink.add(text);

  /// Sends raw bytes.
  void sendBytes(Uint8List bytes) => _ws.sink.add(bytes);

  /// Says hello to room [code].
  Future<void> hello(String code,
      {Token token = Token.kite,
      bool create = false,
      String? password,
      String? session}) async {
    send(
        Hello(
            name: name,
            token: token,
            create: create,
            password: password,
            sessionToken: session),
        room: code);
    await waitFor(() => playerId != null || errors.isNotEmpty);
  }

  /// Waits until [cond] holds.
  Future<void> waitFor(bool Function() cond,
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (cond()) return;
    final done = Completer<void>();
    final sub = _changes.stream.listen((_) {
      if (!done.isCompleted && cond()) done.complete();
    });
    try {
      await done.future.timeout(timeout);
    } finally {
      await sub.cancel();
    }
  }

  /// Lets a core bot play this seat through protocol intents.
  void autoplay(Bot bot) {
    brain = bot;
    _think();
  }

  void _think() {
    final bot = brain;
    final s = state;
    final me = playerId;
    if (bot == null || s == null || me == null || closed) return;
    if (s.version == _actedOn) return;
    for (final a in bot.candidates(s, me)) {
      final probe = a is Roll && !a.hasDice ? Roll(me, 1, 2) : a;
      if (!apply(probe, s).ok) continue;
      final msg = intentFor(a);
      if (msg == null) continue;
      _actedOn = s.version;
      send(msg);
      return;
    }
  }

  /// Closes the socket.
  Future<void> close() async {
    brain = null;
    await _ws.sink.close();
    await _sub.cancel();
    closed = true;
  }
}

/// In-process peer for fast unit tests.
class FakePeer implements Peer {
  /// Creates a peer.
  FakePeer([this.remote = '10.0.0.1']);

  @override
  final String remote;

  /// Text frames sent to this peer.
  final List<String> texts = [];

  /// Binary frames sent to this peer.
  final List<Uint8List> binaries = [];

  /// Whether closed.
  bool closed = false;

  @override
  void sendText(String text) => texts.add(text);

  @override
  void sendBinary(Uint8List bytes) => binaries.add(bytes);

  @override
  void close() => closed = true;

  /// Decoded server messages.
  List<ServerMessage> get messages => [
        for (final t in texts)
          if (decodeFrame(t).ok)
            decodeFrame(t).envelope!.message as ServerMessage,
      ];

  /// Errors received.
  List<ErrorMsg> get errors => messages.whereType<ErrorMsg>().toList();
}

/// Sends a message through a [Connection].
void say(Connection c, ClientMessage m, {String room = ''}) =>
    c.onText(Envelope(m, room: room).encode());
