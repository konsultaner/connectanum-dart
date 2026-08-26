import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'voice_note_playback_source.dart';
import 'voice_note_playback_source_factory.dart';

enum VoiceNotePlaybackState { stopped, playing, paused }

abstract interface class VoiceNotePlayerBackend {
  Stream<PlayerState> get stateChanges;

  Stream<Duration> get positionChanges;

  Stream<Duration> get durationChanges;

  Stream<void> get completions;

  Future<void> play(Source source);

  Future<void> pause();

  Future<void> resume();

  Future<void> seek(Duration position);

  Future<void> release();

  Future<void> dispose();
}

final class AudioPlayersVoiceNoteBackend implements VoiceNotePlayerBackend {
  AudioPlayersVoiceNoteBackend({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  var _configured = false;

  @override
  Stream<PlayerState> get stateChanges => _player.onPlayerStateChanged;

  @override
  Stream<Duration> get positionChanges => _player.onPositionChanged;

  @override
  Stream<Duration> get durationChanges => _player.onDurationChanged;

  @override
  Stream<void> get completions => _player.onPlayerComplete;

  @override
  Future<void> play(Source source) async {
    if (!_configured) {
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      await _player.setReleaseMode(ReleaseMode.stop);
      _configured = true;
    }
    await _player.play(source);
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> release() => _player.release();

  @override
  Future<void> dispose() => _player.dispose();
}

final class VoiceNotePlaybackController extends ChangeNotifier {
  VoiceNotePlaybackController(
    Uint8List wavBytes, {
    required Duration expectedDuration,
    VoiceNotePlayerBackend? backend,
    VoiceNotePlaybackSourceFactory? sourceFactory,
  }) : _wavBytes = _validateVoiceNoteWav(wavBytes, expectedDuration),
       _duration = expectedDuration,
       _backend = backend ?? AudioPlayersVoiceNoteBackend(),
       _sourceFactory =
           sourceFactory ?? createVoiceNotePlaybackSourceFactory() {
    _subscriptions.addAll([
      _backend.stateChanges.listen(_handleState),
      _backend.positionChanges.listen(_handlePosition),
      _backend.durationChanges.listen(_handleDuration),
      _backend.completions.listen((_) => _handleCompletion()),
    ]);
  }

  final Uint8List _wavBytes;
  final VoiceNotePlayerBackend _backend;
  final VoiceNotePlaybackSourceFactory _sourceFactory;
  final List<StreamSubscription<void>> _subscriptions = [];

  VoiceNotePlaybackSource? _source;
  Future<void>? _operation;
  VoiceNotePlaybackState _state = VoiceNotePlaybackState.stopped;
  Duration _position = Duration.zero;
  Duration _duration;
  String? _error;
  var _disposed = false;
  var _notifierDisposed = false;
  Future<void>? _disposeFuture;

  VoiceNotePlaybackState get state => _state;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get error => _error;
  bool get busy => _operation != null;

  Future<void> toggle() => switch (_state) {
    VoiceNotePlaybackState.playing => pause(),
    VoiceNotePlaybackState.paused => resume(),
    VoiceNotePlaybackState.stopped => play(),
  };

  Future<void> play() => _run(() async {
    final source = _source ??= await _sourceFactory.create(_wavBytes);
    _error = null;
    await _backend.play(source.audioSource);
    _state = VoiceNotePlaybackState.playing;
  });

  Future<void> pause() => _run(() async {
    await _backend.pause();
    _state = VoiceNotePlaybackState.paused;
  });

  Future<void> resume() => _run(() async {
    await _backend.resume();
    _state = VoiceNotePlaybackState.playing;
  });

  Future<void> seek(Duration position) => _run(() async {
    final bounded = position < Duration.zero
        ? Duration.zero
        : position > _duration
        ? _duration
        : position;
    await _backend.seek(bounded);
    _position = bounded;
  });

  Future<void> _run(Future<void> Function() operation) {
    _throwIfDisposed();
    final pending = _operation;
    if (pending != null) return pending;
    final future = () async {
      try {
        await operation();
      } catch (_) {
        _error = 'Voice-note playback failed.';
        _state = VoiceNotePlaybackState.stopped;
      } finally {
        _operation = null;
        if (!_disposed) notifyListeners();
      }
    }();
    _operation = future;
    notifyListeners();
    return future;
  }

  void _handleState(PlayerState state) {
    if (_disposed) return;
    _state = switch (state) {
      PlayerState.playing => VoiceNotePlaybackState.playing,
      PlayerState.paused => VoiceNotePlaybackState.paused,
      PlayerState.stopped ||
      PlayerState.completed ||
      PlayerState.disposed => VoiceNotePlaybackState.stopped,
    };
    notifyListeners();
  }

  void _handlePosition(Duration value) {
    if (_disposed) return;
    _position = value > _duration ? _duration : value;
    notifyListeners();
  }

  void _handleDuration(Duration value) {
    if (_disposed || value <= Duration.zero) return;
    _duration = value;
    notifyListeners();
  }

  void _handleCompletion() {
    if (_disposed) return;
    _position = _duration;
    _state = VoiceNotePlaybackState.stopped;
    notifyListeners();
  }

  @override
  void dispose() {
    final future = _startDisposal();
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
    future.ignore();
  }

  Future<void> disposeAsync() async {
    final future = _startDisposal();
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
    await future;
  }

  Future<void> _startDisposal() => _disposeFuture ??= _disposeResources();

  Future<void> _disposeResources() async {
    _disposed = true;
    final pending = _operation;
    if (pending != null) await pending;
    Object? failure;
    for (final subscription in _subscriptions) {
      try {
        await subscription.cancel();
      } catch (error) {
        failure ??= error;
      }
    }
    try {
      await _backend.release();
    } catch (error) {
      failure = error;
    }
    try {
      await _backend.dispose();
    } catch (error) {
      failure ??= error;
    }
    try {
      await _source?.dispose();
    } catch (error) {
      failure ??= error;
    }
    _wavBytes.fillRange(0, _wavBytes.length, 0);
    if (failure != null) throw failure;
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError('The voice-note player has been disposed.');
    }
  }
}

Uint8List _validateVoiceNoteWav(Uint8List bytes, Duration expectedDuration) {
  if (bytes.length < WampAppAttachmentLimits.voiceNoteWavHeaderBytes ||
      bytes.length > WampAppAttachmentLimits.maxVoiceNoteWavBytes) {
    throw const FormatException('Voice-note WAV size is invalid.');
  }
  final ownedBytes = Uint8List.fromList(bytes);
  final data = ByteData.sublistView(ownedBytes);
  bool hasAscii(int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      if (ownedBytes[offset + index] != value.codeUnitAt(index)) return false;
    }
    return true;
  }

  final pcmBytes =
      ownedBytes.length - WampAppAttachmentLimits.voiceNoteWavHeaderBytes;
  final durationMilliseconds = pcmBytes <= 0
      ? 0
      : (pcmBytes * 1000 +
                WampAppAttachmentLimits.voiceNotePcmBytesPerSecond -
                1) ~/
            WampAppAttachmentLimits.voiceNotePcmBytesPerSecond;
  if (!hasAscii(0, 'RIFF') ||
      data.getUint32(4, Endian.little) != ownedBytes.length - 8 ||
      !hasAscii(8, 'WAVE') ||
      !hasAscii(12, 'fmt ') ||
      data.getUint32(16, Endian.little) != 16 ||
      data.getUint16(20, Endian.little) != 1 ||
      data.getUint16(22, Endian.little) != 1 ||
      data.getUint32(24, Endian.little) != 16000 ||
      data.getUint32(28, Endian.little) !=
          WampAppAttachmentLimits.voiceNotePcmBytesPerSecond ||
      data.getUint16(32, Endian.little) != 2 ||
      data.getUint16(34, Endian.little) != 16 ||
      !hasAscii(36, 'data') ||
      data.getUint32(40, Endian.little) != pcmBytes ||
      pcmBytes <= 0 ||
      pcmBytes.isOdd ||
      expectedDuration.inMilliseconds != durationMilliseconds) {
    throw const FormatException('Voice-note WAV payload is invalid.');
  }
  return ownedBytes;
}
