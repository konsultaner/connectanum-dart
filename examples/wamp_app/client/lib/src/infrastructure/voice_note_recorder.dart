import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

const _voiceSampleRate = 16000;
const _voiceChannels = 1;
const _voiceBitsPerSample = 16;
const _voiceBytesPerSample = _voiceBitsPerSample ~/ 8;
const _voiceBytesPerSecond =
    _voiceSampleRate * _voiceChannels * _voiceBytesPerSample;

final class VoiceNoteRecordingException implements Exception {
  const VoiceNoteRecordingException(this.message);

  final String message;

  @override
  String toString() => 'VoiceNoteRecordingException: $message';
}

final class VoiceNoteRecordingCancelled extends VoiceNoteRecordingException {
  const VoiceNoteRecordingCancelled()
    : super('The voice-note recording was cancelled.');
}

abstract interface class VoiceRecorderBackend {
  Future<bool> hasPermission();

  Future<bool> supportsPcm16();

  Future<Stream<Uint8List>> startPcm16({
    required void Function() onIncompatibleConfig,
  });

  Future<void> stop();

  Future<void> cancel();

  Future<void> dispose();
}

abstract interface class VoiceNoteCapture {
  Future<VoiceNoteCaptureSession> start();

  Future<void> dispose();
}

abstract interface class VoiceNoteCaptureSession {
  Future<VoiceNoteRecording> get completed;

  Future<VoiceNoteRecording> stop();

  Future<void> cancel();
}

abstract interface class VoiceNoteRecording {
  int get byteCount;

  int get durationMilliseconds;

  Uint8List takeBytes();

  void dispose();
}

final class RecordVoiceRecorderBackend implements VoiceRecorderBackend {
  RecordVoiceRecorderBackend({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<bool> supportsPcm16() =>
      _recorder.isEncoderSupported(AudioEncoder.pcm16bits);

  @override
  Future<Stream<Uint8List>> startPcm16({
    required void Function() onIncompatibleConfig,
  }) async {
    await _recorder.setOnConfigChanged((config) {
      if (config.encoder != AudioEncoder.pcm16bits ||
          config.sampleRate != _voiceSampleRate ||
          config.numChannels != _voiceChannels) {
        onIncompatibleConfig();
      }
    });
    return _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _voiceSampleRate,
        numChannels: _voiceChannels,
        echoCancel: true,
        noiseSuppress: true,
        streamBufferSize: 3200,
      ),
    );
  }

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}

final class RecordedVoiceNote implements VoiceNoteRecording {
  RecordedVoiceNote._(this._wavBytes, this.durationMilliseconds);

  Uint8List? _wavBytes;
  @override
  final int durationMilliseconds;

  @override
  int get byteCount => _wavBytes?.length ?? 0;

  @override
  Uint8List takeBytes() {
    final bytes = _wavBytes;
    if (bytes == null) {
      throw StateError('The recorded voice note is no longer available.');
    }
    _wavBytes = null;
    return bytes;
  }

  @override
  void dispose() {
    final bytes = _wavBytes;
    _wavBytes = null;
    bytes?.fillRange(0, bytes.length, 0);
  }
}

final class VoiceNoteRecordingSession implements VoiceNoteCaptureSession {
  VoiceNoteRecordingSession._(this._owner, this._attemptId, this.completed);

  final VoiceNoteRecorder _owner;
  final int _attemptId;
  @override
  final Future<RecordedVoiceNote> completed;

  @override
  Future<RecordedVoiceNote> stop() => _owner._stop(_attemptId);

  @override
  Future<void> cancel() => _owner._cancel(_attemptId);
}

final class VoiceNoteRecorder implements VoiceNoteCapture {
  VoiceNoteRecorder({
    VoiceRecorderBackend? backend,
    this.maximumDuration = const Duration(
      milliseconds: WampAppAttachmentLimits.maxVoiceNoteDurationMilliseconds,
    ),
    this.shutdownTimeout = const Duration(seconds: 5),
  }) : _backend = backend ?? RecordVoiceRecorderBackend() {
    if (maximumDuration.inMilliseconds <= 0 ||
        maximumDuration.inMilliseconds >
            WampAppAttachmentLimits.maxVoiceNoteDurationMilliseconds) {
      throw ArgumentError.value(
        maximumDuration,
        'maximumDuration',
        'must be positive and no longer than five minutes',
      );
    }
    if (shutdownTimeout <= Duration.zero) {
      throw ArgumentError.value(
        shutdownTimeout,
        'shutdownTimeout',
        'must be positive',
      );
    }
  }

  final VoiceRecorderBackend _backend;
  final Duration maximumDuration;
  final Duration shutdownTimeout;

  _VoiceRecordingAttempt? _active;
  Future<VoiceNoteRecordingSession>? _starting;
  var _nextAttemptId = 0;
  var _disposed = false;

  bool get isRecording => _active != null;

  @override
  Future<VoiceNoteRecordingSession> start() {
    _throwIfDisposed();
    if (_starting != null || _active != null) {
      throw StateError('A voice-note recording is already active.');
    }
    final future = _start();
    _starting = future;
    return future.whenComplete(() {
      if (identical(_starting, future)) _starting = null;
    });
  }

  Future<VoiceNoteRecordingSession> _start() async {
    if (!await _backend.hasPermission()) {
      throw const VoiceNoteRecordingException(
        'Microphone permission is required to record a voice note.',
      );
    }
    _throwIfDisposed();
    if (!await _backend.supportsPcm16()) {
      throw const VoiceNoteRecordingException(
        'This device does not support PCM voice-note recording.',
      );
    }
    _throwIfDisposed();

    final attemptId = ++_nextAttemptId;
    var incompatibleConfig = false;
    late final Stream<Uint8List> stream;
    try {
      stream = await _backend.startPcm16(
        onIncompatibleConfig: () {
          incompatibleConfig = true;
          unawaited(_failIncompatibleConfig(attemptId));
        },
      );
    } catch (_) {
      throw const VoiceNoteRecordingException(
        'The microphone could not start recording.',
      );
    }
    if (_disposed || incompatibleConfig) {
      await _cancelBackend();
      _throwIfDisposed();
      throw const VoiceNoteRecordingException(
        'The microphone changed to an incompatible audio format.',
      );
    }

    final attempt = _VoiceRecordingAttempt(attemptId);
    _active = attempt;
    attempt.subscription = stream.listen(
      (bytes) => _capture(attemptId, bytes),
      onError: (Object _, StackTrace _) {
        unawaited(
          _fail(
            attemptId,
            const VoiceNoteRecordingException(
              'The microphone stopped unexpectedly.',
            ),
          ),
        );
      },
      onDone: () {
        if (!attempt.streamClosed.isCompleted) {
          attempt.streamClosed.complete();
        }
        if (!attempt.closing) {
          unawaited(
            _fail(
              attemptId,
              const VoiceNoteRecordingException(
                'The microphone stopped unexpectedly.',
              ),
            ),
          );
        }
      },
      cancelOnError: false,
    );
    attempt.maximumTimer = Timer(maximumDuration, () {
      _stop(attemptId).ignore();
    });
    return VoiceNoteRecordingSession._(
      this,
      attemptId,
      attempt.completion.future,
    );
  }

  void _capture(int attemptId, Uint8List bytes) {
    final attempt = _active;
    if (attempt == null ||
        attempt.id != attemptId ||
        !attempt.acceptBytes ||
        bytes.isEmpty) {
      return;
    }
    final maximumPcmBytes =
        _voiceBytesPerSecond * maximumDuration.inMilliseconds ~/ 1000;
    final remaining = maximumPcmBytes - attempt.byteCount;
    if (remaining <= 0) {
      _stop(attemptId).ignore();
      return;
    }
    final take = min(remaining, bytes.length);
    final chunk = Uint8List(take)..setRange(0, take, bytes);
    attempt.chunks.add(chunk);
    attempt.byteCount += take;
    if (take < bytes.length || attempt.byteCount >= maximumPcmBytes) {
      _stop(attemptId).ignore();
    }
  }

  Future<RecordedVoiceNote> _stop(int attemptId) {
    final attempt = _requireAttempt(attemptId);
    final existing = attempt.finishFuture;
    if (existing != null) return existing;
    attempt.closing = true;
    attempt.maximumTimer?.cancel();
    final future = _finishStop(attempt);
    attempt.finishFuture = future;
    return future;
  }

  Future<RecordedVoiceNote> _finishStop(_VoiceRecordingAttempt attempt) async {
    try {
      await _backend.stop().timeout(shutdownTimeout);
      await attempt.streamClosed.future.timeout(shutdownTimeout);
      attempt.acceptBytes = false;
      await _cancelSubscription(attempt, failOnTimeout: true);
      if (attempt.byteCount == 0 ||
          attempt.byteCount.isOdd ||
          attempt.incompatibleConfig ||
          attempt.byteCount >
              _voiceBytesPerSecond * maximumDuration.inMilliseconds ~/ 1000) {
        throw const VoiceNoteRecordingException(
          'The microphone did not return a valid voice recording.',
        );
      }
      final durationMilliseconds = max(
        1,
        (attempt.byteCount * 1000 + _voiceBytesPerSecond - 1) ~/
            _voiceBytesPerSecond,
      );
      final wav = _buildPcm16Wav(attempt.chunks, attempt.byteCount);
      final result = RecordedVoiceNote._(wav, durationMilliseconds);
      _completeAttempt(attempt, result: result);
      return result;
    } on VoiceNoteRecordingException catch (error, stackTrace) {
      attempt.acceptBytes = false;
      await _cancelBackend();
      _completeAttempt(attempt, error: error, stackTrace: stackTrace);
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      attempt.acceptBytes = false;
      await _cancelBackend();
      const failure = VoiceNoteRecordingException(
        'The microphone did not stop safely in time.',
      );
      _completeAttempt(attempt, error: failure, stackTrace: stackTrace);
      Error.throwWithStackTrace(failure, stackTrace);
    } catch (_, stackTrace) {
      attempt.acceptBytes = false;
      await _cancelBackend();
      const failure = VoiceNoteRecordingException(
        'The voice-note recording could not be finalized.',
      );
      _completeAttempt(attempt, error: failure, stackTrace: stackTrace);
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  Future<void> _cancel(int attemptId) async {
    final attempt = _requireAttempt(attemptId);
    if (attempt.finishFuture != null) {
      try {
        await attempt.finishFuture;
      } catch (_) {
        // The in-flight terminal operation already owns cleanup.
      }
      return;
    }
    attempt.closing = true;
    attempt.acceptBytes = false;
    attempt.maximumTimer?.cancel();
    await _cancelBackend();
    await _cancelSubscription(attempt);
    const failure = VoiceNoteRecordingCancelled();
    _completeAttempt(attempt, error: failure, stackTrace: StackTrace.current);
  }

  Future<void> _failIncompatibleConfig(int attemptId) async {
    final attempt = _active;
    if (attempt == null || attempt.id != attemptId) return;
    attempt.incompatibleConfig = true;
    if (attempt.closing) return;
    await _fail(
      attemptId,
      const VoiceNoteRecordingException(
        'The microphone changed to an incompatible audio format.',
      ),
    );
  }

  Future<void> _fail(int attemptId, VoiceNoteRecordingException failure) async {
    final attempt = _active;
    if (attempt == null || attempt.id != attemptId || attempt.closing) return;
    attempt.closing = true;
    attempt.acceptBytes = false;
    attempt.maximumTimer?.cancel();
    await _cancelBackend();
    await _cancelSubscription(attempt);
    _completeAttempt(attempt, error: failure, stackTrace: StackTrace.current);
  }

  void _completeAttempt(
    _VoiceRecordingAttempt attempt, {
    RecordedVoiceNote? result,
    Object? error,
    StackTrace? stackTrace,
  }) {
    for (final chunk in attempt.chunks) {
      chunk.fillRange(0, chunk.length, 0);
    }
    attempt.chunks.clear();
    attempt.byteCount = 0;
    attempt.acceptBytes = false;
    if (identical(_active, attempt)) _active = null;
    if (attempt.completion.isCompleted) return;
    if (result != null) {
      attempt.completion.complete(result);
    } else {
      attempt.completion.completeError(
        error ?? const VoiceNoteRecordingException('Recording failed.'),
        stackTrace,
      );
    }
  }

  _VoiceRecordingAttempt _requireAttempt(int attemptId) {
    final attempt = _active;
    if (attempt == null || attempt.id != attemptId) {
      throw StateError('The voice-note recording is no longer active.');
    }
    return attempt;
  }

  Future<void> _cancelBackend() async {
    try {
      await _backend.cancel().timeout(shutdownTimeout);
    } catch (_) {
      // Cleanup remains best effort after a terminal recorder failure.
    }
  }

  Future<void> _cancelSubscription(
    _VoiceRecordingAttempt attempt, {
    bool failOnTimeout = false,
  }) async {
    final subscription = attempt.subscription;
    attempt.subscription = null;
    if (subscription == null) return;
    try {
      await subscription.cancel().timeout(shutdownTimeout);
    } catch (_) {
      if (failOnTimeout) rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final starting = _starting;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {
        // Startup observes disposal and fails closed.
      }
    }
    final attempt = _active;
    if (attempt != null) await _cancel(attempt.id);
    await _backend.dispose().timeout(shutdownTimeout);
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError('The voice-note recorder has been disposed.');
    }
  }
}

final class _VoiceRecordingAttempt {
  _VoiceRecordingAttempt(this.id) {
    completion.future.ignore();
  }

  final int id;
  final chunks = <Uint8List>[];
  final completion = Completer<RecordedVoiceNote>();
  final streamClosed = Completer<void>();
  StreamSubscription<Uint8List>? subscription;
  Timer? maximumTimer;
  Future<RecordedVoiceNote>? finishFuture;
  var byteCount = 0;
  var closing = false;
  var acceptBytes = true;
  var incompatibleConfig = false;
}

Uint8List _buildPcm16Wav(List<Uint8List> chunks, int pcmByteCount) {
  const headerBytes = 44;
  final wav = Uint8List(headerBytes + pcmByteCount);
  final data = ByteData.sublistView(wav);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      wav[offset + index] = value.codeUnitAt(index);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + pcmByteCount, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, _voiceChannels, Endian.little);
  data.setUint32(24, _voiceSampleRate, Endian.little);
  data.setUint32(28, _voiceBytesPerSecond, Endian.little);
  data.setUint16(32, _voiceChannels * _voiceBytesPerSample, Endian.little);
  data.setUint16(34, _voiceBitsPerSample, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, pcmByteCount, Endian.little);
  var offset = headerBytes;
  for (final chunk in chunks) {
    wav.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return wav;
}
