import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:vyapari_protocol/vyapari_protocol.dart';

import '../state/game_controller.dart';
import 'voice_platform.dart';

/// Longest clip.
const maxClip = Duration(seconds: 15);

/// Voice UI state.
class VoiceState {
  /// Creates a state.
  const VoiceState({
    this.recording = false,
    this.elapsedMs = 0,
    this.speaking,
    this.recipients = const [],
    this.muted = const {},
    this.muteAll = false,
    this.volume = 1,
    this.recent = const [],
    this.queued = 0,
    this.message,
  });

  /// Recording now.
  final bool recording;

  /// Recording time so far.
  final int elapsedMs;

  /// Clip playing now.
  final VoiceHeader? speaking;

  /// Chosen recipients; empty = broadcast.
  final List<String> recipients;

  /// Players I muted.
  final Set<String> muted;

  /// Mute everyone.
  final bool muteAll;

  /// Playback volume 0–1 (UI slider value; not money).
  final num volume;

  /// Last 5 received clips, newest last.
  final List<VoiceFrame> recent;

  /// Clips waiting to play.
  final int queued;

  /// Status text (e.g. microphone denied).
  final String? message;

  /// Copy with changes.
  VoiceState copyWith({
    bool? recording,
    int? elapsedMs,
    VoiceHeader? speaking,
    bool clearSpeaking = false,
    List<String>? recipients,
    Set<String>? muted,
    bool? muteAll,
    num? volume,
    List<VoiceFrame>? recent,
    int? queued,
    String? message,
  }) =>
      VoiceState(
        recording: recording ?? this.recording,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        speaking: clearSpeaking ? null : (speaking ?? this.speaking),
        recipients: recipients ?? this.recipients,
        muted: muted ?? this.muted,
        muteAll: muteAll ?? this.muteAll,
        volume: volume ?? this.volume,
        recent: recent ?? this.recent,
        queued: queued ?? this.queued,
        message: message,
      );
}

/// Abstraction over the recorder so tests can fake it.
abstract class ClipRecorder {
  /// Whether the mic may be used (asks the OS if needed).
  Future<bool> hasPermission();

  /// Starts recording.
  Future<void> start();

  /// Stops and returns the clip bytes (null if nothing).
  Future<Uint8List?> stop();
}

class _RealRecorder implements ClipRecorder {
  final _rec = AudioRecorder();

  @override
  Future<bool> hasPermission() => _rec.hasPermission();

  @override
  Future<void> start() async => _rec.start(
        RecordConfig(
            encoder: myEncoder,
            bitRate: 24000,
            sampleRate: 16000,
            numChannels: 1),
        path: await recordTarget(),
      );

  @override
  Future<Uint8List?> stop() async {
    final path = await _rec.stop();
    if (path == null) return null;
    return readRecording(path);
  }
}

/// Abstraction over playback so tests can fake it.
abstract class ClipPlayer {
  /// Plays [frame] to the end.
  Future<void> play(VoiceFrame frame, num volume);
}

class _RealPlayer implements ClipPlayer {
  final _player = AudioPlayer();

  @override
  Future<void> play(VoiceFrame frame, num volume) async {
    final (source, cleanup) = await sourceFor(frame.audio, frame.header.codec);
    try {
      await _player.setVolume(volume.toDouble());
      await _player.setAudioSource(source);
      await _player.play();
      await _player.processingStateStream
          .firstWhere((s) => s == ProcessingState.completed)
          .timeout(Duration(milliseconds: frame.header.durationMs + 3000));
      await _player.stop();
    } catch (_) {
      // Unplayable clip (e.g. codec unsupported here): skip it.
    } finally {
      await cleanup();
    }
  }
}

/// Recorder factory (overridable in tests).
final clipRecorderProvider = Provider<ClipRecorder>((ref) => _RealRecorder());

/// Player factory (overridable in tests).
final clipPlayerProvider = Provider<ClipPlayer>((ref) => _RealPlayer());

/// Push-to-talk voice: record, send, queue and play.
final voiceProvider =
    NotifierProvider<VoiceController, VoiceState>(VoiceController.new);

/// Controller for push-to-talk.
class VoiceController extends Notifier<VoiceState> {
  final List<VoiceFrame> _queue = [];
  bool _playing = false;
  Timer? _tick;
  DateTime? _startedAt;
  StreamSubscription<VoiceFrame>? _sub;

  @override
  VoiceState build() {
    _sub = ref.read(gameProvider.notifier).voiceFrames.stream.listen(receive);
    ref.onDispose(() {
      _sub?.cancel();
      _tick?.cancel();
    });
    return const VoiceState();
  }

  /// Picks recipients (empty = broadcast; at most 3).
  void setRecipients(List<String> ids) =>
      state = state.copyWith(recipients: ids.take(3).toList());

  /// Starts recording; auto-stops and sends at 15 s.
  Future<void> startTalking() async {
    if (state.recording) return;
    final rec = ref.read(clipRecorderProvider);
    if (!await rec.hasPermission()) {
      state = state.copyWith(
          message:
              'Allow the microphone to send voice clips (Settings → Vyapari).');
      return;
    }
    await rec.start();
    _startedAt = clock.now();
    state = state.copyWith(recording: true, elapsedMs: 0);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final ms = clock.now().difference(_startedAt!).inMilliseconds;
      state = state.copyWith(elapsedMs: min(ms, maxClip.inMilliseconds));
      if (ms >= maxClip.inMilliseconds) stopAndSend();
    });
  }

  /// Stops recording and sends the clip to the chosen recipients.
  Future<VoiceFrame?> stopAndSend() async {
    if (!state.recording) return null;
    _tick?.cancel();
    final ms = min(clock.now().difference(_startedAt!).inMilliseconds,
        maxClip.inMilliseconds);
    state = state.copyWith(recording: false, elapsedMs: 0);
    final bytes = await ref.read(clipRecorderProvider).stop();
    if (bytes == null || bytes.isEmpty || ms < 300) return null;
    if (bytes.length > VoiceFrame.maxAudioBytes) {
      state = state.copyWith(message: 'Clip too large — try a shorter one');
      return null;
    }
    final game = ref.read(gameProvider);
    final frame = VoiceFrame(
      VoiceHeader(
        clipId: '${game.me}-${clock.now().millisecondsSinceEpoch}',
        from: game.me ?? '',
        to: state.recipients,
        codec: myCodec,
        durationMs: ms,
      ),
      bytes,
    );
    ref.read(gameProvider.notifier).sendVoice(frame.encode());
    return frame;
  }

  /// Handles an incoming clip: keep for replay, queue for playback.
  void receive(VoiceFrame f) {
    if (state.muteAll || state.muted.contains(f.header.from)) return;
    final recent = [...state.recent, f];
    state = state.copyWith(
        recent: recent.length > 5 ? recent.sublist(recent.length - 5) : recent);
    _queue.add(f);
    state = state.copyWith(queued: _queue.length);
    _pump();
  }

  /// Replays a recent clip.
  void replay(VoiceFrame f) {
    _queue.add(f);
    _pump();
  }

  Future<void> _pump() async {
    if (_playing) return;
    _playing = true;
    final player = ref.read(clipPlayerProvider);
    while (_queue.isNotEmpty) {
      final f = _queue.removeAt(0);
      state = state.copyWith(speaking: f.header, queued: _queue.length);
      await player.play(f, state.volume);
    }
    state = state.copyWith(clearSpeaking: true, queued: 0);
    _playing = false;
  }

  /// Mutes or unmutes one player for me.
  void toggleMute(String id) {
    final m = {...state.muted};
    if (!m.remove(id)) m.add(id);
    state = state.copyWith(muted: m);
  }

  /// Mutes everyone.
  void setMuteAll(bool v) => state = state.copyWith(muteAll: v);

  /// Playback volume.
  void setVolume(num v) => state = state.copyWith(volume: v.clamp(0, 1));
}
