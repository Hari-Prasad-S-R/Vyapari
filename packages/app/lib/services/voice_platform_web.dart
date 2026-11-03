import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

/// Browsers record Opus in WebM.
String get myCodec => 'opus-webm';

/// Encoder for [myCodec].
AudioEncoder get myEncoder => AudioEncoder.opus;

/// The web recorder ignores the path and returns a blob URL on stop.
Future<String> recordTarget() async => '';

/// Fetches the recorded blob into memory.
Future<Uint8List> readRecording(String blobUrl) async =>
    (await http.get(Uri.parse(blobUrl))).bodyBytes;

/// Plays a clip from a data URI (nothing touches storage).
Future<(AudioSource, Future<void> Function())> sourceFor(
    Uint8List bytes, String codec) async {
  final mime = switch (codec) {
    'aac' => 'audio/mp4',
    'opus-ogg' => 'audio/ogg',
    _ => 'audio/webm',
  };
  return (
    AudioSource.uri(Uri.dataFromBytes(bytes, mimeType: mime)),
    () async {}
  );
}
