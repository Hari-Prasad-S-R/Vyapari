import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Codec label sent in the voice header: AAC on iOS, Opus elsewhere.
String get myCodec => Platform.isIOS ? 'aac' : 'opus-ogg';

/// Encoder for [myCodec].
AudioEncoder get myEncoder =>
    Platform.isIOS ? AudioEncoder.aacLc : AudioEncoder.opus;

int _n = 0;

Future<String> _tempPath(String ext) async {
  final dir = await getTemporaryDirectory();
  return '${dir.path}/vyapari_${DateTime.now().microsecondsSinceEpoch}_${_n++}.$ext';
}

/// Where the recorder writes the clip.
Future<String> recordTarget() => _tempPath(Platform.isIOS ? 'm4a' : 'ogg');

/// Reads the finished recording and deletes the temporary file.
Future<Uint8List> readRecording(String path) async {
  final f = File(path);
  final bytes = await f.readAsBytes();
  try {
    await f.delete();
  } catch (_) {}
  return bytes;
}

/// Audio source for a received clip; [cleanup] removes the temporary file.
Future<(AudioSource, Future<void> Function())> sourceFor(
    Uint8List bytes, String codec) async {
  final ext = switch (codec) {
    'aac' => 'm4a',
    'opus-webm' => 'webm',
    _ => 'ogg',
  };
  final path = await _tempPath(ext);
  final f = File(path);
  await f.writeAsBytes(bytes, flush: true);
  return (
    AudioSource.file(path),
    () async {
      try {
        await f.delete();
      } catch (_) {}
    }
  );
}
