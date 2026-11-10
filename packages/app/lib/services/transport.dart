import 'dart:async';
import 'dart:typed_data';

import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';
import 'package:vyapari_server/room_core.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Something arriving from the server: a text message or a voice frame.
sealed class Incoming {
  const Incoming();
}

/// A decoded server message.
class IncomingMessage extends Incoming {
  /// Creates the event.
  const IncomingMessage(this.message);

  /// Message.
  final ServerMessage message;
}

/// A voice clip.
class IncomingVoice extends Incoming {
  /// Creates the event.
  const IncomingVoice(this.frame);

  /// Clip.
  final VoiceFrame frame;
}

/// The connection closed.
class IncomingClosed extends Incoming {
  /// Creates the event.
  const IncomingClosed();
}

/// One connection to an authoritative server.
abstract class GameTransport {
  /// Server events.
  Stream<Incoming> get incoming;

  /// Sends an intent.
  void send(ClientMessage m, {String room = ''});

  /// Sends a voice frame.
  void sendVoice(Uint8List bytes);

  /// Closes the connection.
  Future<void> close();
}

int _seq = 0;

/// WebSocket transport (`ws://` locally, `wss://` online).
class WsTransport implements GameTransport {
  WsTransport._(this._ch) {
    _ch.stream.listen(
      (data) {
        if (data is String) {
          final r = decodeFrame(data);
          final m = r.envelope?.message;
          if (m is ServerMessage) _out.add(IncomingMessage(m));
        } else if (data is List<int>) {
          final f = VoiceFrame.decode(data);
          if (f != null) _out.add(IncomingVoice(f));
        }
      },
      onDone: () {
        if (!_out.isClosed) {
          _out.add(const IncomingClosed());
          _out.close();
        }
      },
      onError: (Object _) {},
    );
  }

  /// Connects to [uri].
  static Future<WsTransport> connect(Uri uri) async {
    final ch = WebSocketChannel.connect(uri);
    await ch.ready.timeout(const Duration(seconds: 5));
    return WsTransport._(ch);
  }

  final WebSocketChannel _ch;
  final _out = StreamController<Incoming>.broadcast();

  @override
  Stream<Incoming> get incoming => _out.stream;

  @override
  void send(ClientMessage m, {String room = ''}) =>
      _ch.sink.add(Envelope(m, id: 'c-${_seq++}', room: room).encode());

  @override
  void sendVoice(Uint8List bytes) => _ch.sink.add(bytes);

  @override
  Future<void> close() => _ch.sink.close();
}

class _MemoryPeer implements Peer {
  _MemoryPeer(this.out);
  final StreamController<Incoming> out;

  @override
  String get remote => 'this-device';

  @override
  void sendText(String text) {
    final m = decodeFrame(text).envelope?.message;
    if (m is ServerMessage && !out.isClosed) {
      // Deliver asynchronously, like a socket.
      scheduleMicrotask(() {
        if (!out.isClosed) out.add(IncomingMessage(m));
      });
    }
  }

  @override
  void sendBinary(Uint8List bytes) {}

  @override
  void close() {}
}

/// Offline game against bots: the same [Room] engine the server runs, in
/// memory on this device (works on web too).
class OfflineTransport implements GameTransport {
  /// Creates an offline room for [board].
  OfflineTransport(BoardData board,
      {Duration botDelay = const Duration(milliseconds: 650), bool pace = true})
      : room = Room(
          code: 'SOLO',
          board: board,
          config: ServerConfig(
              botDelay: botDelay, enableTurnTimer: false, paceAnimations: pace),
          rng: SecureRandomSource(),
          isLocal: false,
        ) {
    _peer = _MemoryPeer(_out);
  }

  /// The in-memory room.
  final Room room;
  final _out = StreamController<Incoming>.broadcast();
  late final _MemoryPeer _peer;
  String? _me;

  @override
  Stream<Incoming> get incoming => _out.stream;

  @override
  void send(ClientMessage m, {String room = ''}) {
    scheduleMicrotask(() {
      if (m is Hello) {
        final r = this.room.join(_peer, m);
        _me = r.playerId;
        return;
      }
      final me = _me;
      if (me != null) this.room.onMessage(me, Envelope(m));
    });
  }

  @override
  void sendVoice(Uint8List bytes) {}

  @override
  Future<void> close() async {
    room.dispose();
    await _out.close();
  }
}
