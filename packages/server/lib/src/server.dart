import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:vyapari_core/vyapari_core.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'hub.dart';
import 'store.dart';
import 'support.dart';

/// Default WebSocket port.
const defaultPort = 47800;

class _SocketPeer implements Peer {
  _SocketPeer(this.channel, this.remote);
  final WebSocketChannel channel;
  bool _closed = false;

  @override
  final String remote;

  @override
  void sendText(String text) {
    if (!_closed) channel.sink.add(text);
  }

  @override
  void sendBinary(Uint8List bytes) {
    if (!_closed) channel.sink.add(bytes);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(channel.sink.close());
  }
}

/// HTTP + WebSocket front end: `/ws` for players, `/health`, `/rooms`.
class GameServer {
  /// Creates a server.
  GameServer({
    required BoardData board,
    ServerConfig config = const ServerConfig(),
    GameStore? store,
    RandomSource? rng,
    void Function(String line)? log,
    String? webRoot,
  })  : hub = RoomHub(board: board, config: config, store: store, rng: rng),
        _log = log ?? ((_) {}),
        _static = webRoot == null
            ? null
            : createStaticHandler(webRoot, defaultDocument: 'index.html');

  /// Room hub.
  final RoomHub hub;
  final void Function(String) _log;
  final Handler? _static;
  HttpServer? _http;

  /// Bound port (after [start]).
  int get port => _http?.port ?? 0;

  /// Request handler (exposed for tests).
  Handler get handler => (Request request) {
        final path = request.url.path;
        if (path == 'health') {
          return Response.ok(
              jsonEncode({
                'status': 'ok',
                'protocol': protocolVersion,
                'rooms': hub.rooms.length,
              }),
              headers: {'content-type': 'application/json'});
        }
        if (path == 'local') {
          final info = hub.localInfo();
          if (info == null) return Response.notFound('Not a local host');
          return Response.ok(jsonEncode({...info, 'v': protocolVersion}),
              headers: {'content-type': 'application/json'});
        }
        if (path == 'rooms') {
          return Response.ok(jsonEncode(hub.publicRooms()),
              headers: {'content-type': 'application/json'});
        }
        final isUpgrade =
            request.headers['upgrade']?.toLowerCase() == 'websocket';
        if (_static != null && !isUpgrade && path != 'ws') {
          return _static(request);
        }
        if (path == 'ws' || path.isEmpty) {
          final info = request.context['shelf.io.connection_info'];
          final remote =
              info is HttpConnectionInfo ? info.remoteAddress.address : 'local';
          return webSocketHandler((WebSocketChannel ch, String? _) {
            _onSocket(ch, remote);
          }, pingInterval: const Duration(seconds: 10))(request);
        }
        return Response.notFound('Not found');
      };

  void _onSocket(WebSocketChannel ch, String remote) {
    final peer = _SocketPeer(ch, remote);
    final conn = hub.connect(peer);
    _log('connect $remote');
    ch.stream.listen(
      (data) {
        try {
          if (data is String) {
            conn.onText(data);
          } else if (data is List<int>) {
            conn.onBinary(data is Uint8List ? data : Uint8List.fromList(data));
          }
        } catch (e, st) {
          // Never let one bad frame take the server down.
          _log('error handling frame from $remote: $e\n$st');
        }
      },
      onDone: () {
        peer._closed = true;
        conn.onDone();
        _log('disconnect $remote');
      },
      onError: (Object e) => _log('socket error $remote: $e'),
      cancelOnError: false,
    );
  }

  /// Binds to [address]:[port] (0 picks a free port).
  Future<int> start({Object? address, int port = defaultPort}) async {
    final pipeline =
        const Pipeline().addMiddleware(_errors()).addHandler(handler);
    _http = await shelf_io.serve(
        pipeline, address ?? InternetAddress.anyIPv4, port,
        shared: false);
    _log(
        'Vyapari server listening on ${_http!.address.address}:${_http!.port}');
    return _http!.port;
  }

  Middleware _errors() => (inner) => (request) async {
        try {
          return await inner(request);
        } on HijackException {
          rethrow;
        } catch (e) {
          _log('request error: $e');
          return Response.internalServerError();
        }
      };

  /// Stops listening and closes all rooms.
  Future<void> stop() async {
    hub.dispose();
    await _http?.close(force: true);
    _http = null;
  }
}
