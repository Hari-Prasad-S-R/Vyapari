import 'dart:convert';
import 'dart:typed_data';

import 'package:vyapari_core/vyapari_core.dart';

import 'messages.dart';

/// A decoded JSON frame: envelope fields plus the typed message.
class Envelope {
  /// Creates an envelope.
  const Envelope(this.message,
      {this.id = '', this.room = '', this.v = protocolVersion});

  /// Protocol version.
  final int v;

  /// Message id (client-chosen, echoed in errors as `refId`).
  final String id;

  /// Room code.
  final String room;

  /// Typed message.
  final Message message;

  /// Encodes to a JSON text frame.
  String encode() => jsonEncode({
        'v': v,
        'type': message.type,
        'id': id,
        'room': room,
        'data': message.toData(),
      });

  @override
  bool operator ==(Object other) =>
      other is Envelope &&
      other.v == v &&
      other.id == id &&
      other.room == room &&
      other.message == message;

  @override
  int get hashCode => Object.hash(v, id, room, message.type);
}

/// Typed decode failure. Decoding never throws.
class ProtocolError {
  /// Creates an error.
  const ProtocolError(this.code, this.detail, {this.id});

  /// Reason code (`malformed`, `unknown_message`, `version_mismatch`).
  final ErrorCode code;

  /// What went wrong.
  final String detail;

  /// Message id if it could be read.
  final String? id;

  @override
  String toString() => 'ProtocolError(${code.wire}: $detail)';
}

/// Result of decoding: exactly one of [envelope] or [error] is set.
class DecodeResult {
  const DecodeResult._(this.envelope, this.error);

  /// Success.
  const DecodeResult.ok(Envelope e) : this._(e, null);

  /// Failure.
  const DecodeResult.fail(ProtocolError e) : this._(null, e);

  /// Decoded envelope.
  final Envelope? envelope;

  /// Decode error.
  final ProtocolError? error;

  /// Whether decoding succeeded.
  bool get ok => envelope != null;
}

/// Decodes a JSON text frame into a typed message, or a typed error.
DecodeResult decodeFrame(String text) {
  Object? raw;
  try {
    raw = jsonDecode(text);
  } catch (_) {
    return const DecodeResult.fail(
        ProtocolError(ErrorCode.malformed, 'not valid JSON'));
  }
  if (raw is! Map) {
    return const DecodeResult.fail(
        ProtocolError(ErrorCode.malformed, 'frame is not an object'));
  }
  final id = raw['id'] is String ? raw['id'] as String : null;
  final v = raw['v'];
  final type = raw['type'];
  final room = raw['room'];
  final data = raw['data'] ?? const <String, Object?>{};
  if (v is! int) {
    return DecodeResult.fail(
        ProtocolError(ErrorCode.malformed, 'missing protocol version', id: id));
  }
  if (v != protocolVersion) {
    return DecodeResult.fail(ProtocolError(
        ErrorCode.versionMismatch, 'server speaks v$protocolVersion, got v$v',
        id: id));
  }
  if (type is! String || (room != null && room is! String) || data is! Map) {
    return DecodeResult.fail(
        ProtocolError(ErrorCode.malformed, 'bad envelope fields', id: id));
  }
  final decoder = decoders[type];
  if (decoder == null) {
    return DecodeResult.fail(ProtocolError(
        ErrorCode.unknownMessage, 'unknown type "$type"',
        id: id));
  }
  try {
    final message = decoder(data.cast<String, Object?>());
    return DecodeResult.ok(
        Envelope(message, id: id ?? '', room: room as String? ?? '', v: v));
  } catch (e) {
    return DecodeResult.fail(
        ProtocolError(ErrorCode.malformed, 'bad data for "$type": $e', id: id));
  }
}

/// Header of a binary voice frame.
class VoiceHeader {
  /// Creates a header.
  const VoiceHeader({
    required this.clipId,
    required this.from,
    this.to = const [],
    required this.codec,
    required this.durationMs,
  });

  /// Clip id.
  final String clipId;

  /// Sender id (the server overwrites this with the real sender).
  final String from;

  /// Recipient ids; empty means broadcast to everyone.
  final List<String> to;

  /// Codec: `opus` or `aac`.
  final String codec;

  /// Length in milliseconds.
  final int durationMs;

  /// Whether the clip is private (sent to specific players).
  bool get isPrivate => to.isNotEmpty;

  /// Copy with a different sender/recipients.
  VoiceHeader copyWith({String? from, List<String>? to}) => VoiceHeader(
      clipId: clipId,
      from: from ?? this.from,
      to: to ?? this.to,
      codec: codec,
      durationMs: durationMs);

  /// JSON form.
  Map<String, Object?> toJson() => {
        'clipId': clipId,
        'from': from,
        'to': to,
        'codec': codec,
        'durationMs': durationMs,
      };

  @override
  bool operator ==(Object other) =>
      other is VoiceHeader &&
      other.clipId == clipId &&
      other.from == from &&
      other.codec == codec &&
      other.durationMs == durationMs &&
      other.to.join(',') == to.join(',');

  @override
  int get hashCode => Object.hash(clipId, from, codec, durationMs);
}

/// A push-to-talk clip: `[4-byte header length][JSON header][audio bytes]`.
class VoiceFrame {
  /// Creates a frame.
  VoiceFrame(this.header, this.audio);

  /// Header.
  final VoiceHeader header;

  /// Compressed audio.
  final Uint8List audio;

  /// Max audio bytes per clip.
  static const maxAudioBytes = 60 * 1024;

  /// Max header bytes accepted.
  static const maxHeaderBytes = 4096;

  /// Max clip length.
  static const maxDurationMs = 15000;

  /// Encodes to binary.
  Uint8List encode() {
    final h = utf8.encode(jsonEncode(header.toJson()));
    final out = Uint8List(4 + h.length + audio.length);
    ByteData.sublistView(out).setUint32(0, h.length, Endian.big);
    out.setRange(4, 4 + h.length, h);
    out.setRange(4 + h.length, out.length, audio);
    return out;
  }

  /// Decodes binary; returns `null` (never throws) on malformed input.
  static VoiceFrame? decode(List<int> bytes) {
    try {
      if (bytes.length < 4) return null;
      final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      final len = ByteData.sublistView(data).getUint32(0, Endian.big);
      if (len == 0 || len > maxHeaderBytes || 4 + len > data.length) {
        return null;
      }
      final json = jsonDecode(utf8.decode(data.sublist(4, 4 + len)));
      if (json is! Map) return null;
      final to = json['to'];
      final header = VoiceHeader(
        clipId: json['clipId'] as String,
        from: json['from'] as String? ?? '',
        to: to == null ? const [] : (to as List).cast<String>(),
        codec: json['codec'] as String,
        durationMs: json['durationMs'] as int,
      );
      return VoiceFrame(header, Uint8List.sublistView(data, 4 + len));
    } catch (_) {
      return null;
    }
  }
}
