import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/voice_note_recorder.dart';

void main() {
  test('builds an exact bounded PCM16 WAV and auto-stops', () async {
    final backend = _FakeVoiceRecorderBackend();
    final recorder = VoiceNoteRecorder(
      backend: backend,
      maximumDuration: const Duration(milliseconds: 100),
    );
    final session = await recorder.start();

    backend.add(Uint8List.fromList(List<int>.filled(4000, 0x5a)));
    final recording = await session.completed;
    final wav = recording.takeBytes();

    expect(recording.durationMilliseconds, 100);
    expect(wav.length, 44 + 3200);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    final header = ByteData.sublistView(wav);
    expect(header.getUint32(4, Endian.little), 36 + 3200);
    expect(header.getUint16(20, Endian.little), 1);
    expect(header.getUint16(22, Endian.little), 1);
    expect(header.getUint32(24, Endian.little), 16000);
    expect(header.getUint32(28, Endian.little), 32000);
    expect(header.getUint16(34, Endian.little), 16);
    expect(header.getUint32(40, Endian.little), 3200);
    expect(wav.sublist(44), everyElement(0x5a));
    expect(backend.stopCalls, 1);

    wav.fillRange(0, wav.length, 0);
    await recorder.dispose();
  });

  test('permission and encoder failures never start capture', () async {
    final denied = _FakeVoiceRecorderBackend(permission: false);
    final deniedRecorder = VoiceNoteRecorder(backend: denied);
    await expectLater(
      deniedRecorder.start(),
      throwsA(isA<VoiceNoteRecordingException>()),
    );
    expect(denied.startCalls, 0);
    await deniedRecorder.dispose();

    final unsupported = _FakeVoiceRecorderBackend(pcm16Supported: false);
    final unsupportedRecorder = VoiceNoteRecorder(backend: unsupported);
    await expectLater(
      unsupportedRecorder.start(),
      throwsA(isA<VoiceNoteRecordingException>()),
    );
    expect(unsupported.startCalls, 0);
    await unsupportedRecorder.dispose();
  });

  test('incompatible adjusted config fails closed before capture', () async {
    final backend = _FakeVoiceRecorderBackend(incompatibleOnStart: true);
    final recorder = VoiceNoteRecorder(backend: backend);

    await expectLater(
      recorder.start(),
      throwsA(isA<VoiceNoteRecordingException>()),
    );
    expect(backend.cancelCalls, 1);
    expect(recorder.isRecording, isFalse);
    await recorder.dispose();
  });

  test('cancellation fences late bytes and allows a fresh attempt', () async {
    final backend = _FakeVoiceRecorderBackend();
    final recorder = VoiceNoteRecorder(backend: backend);
    final first = await recorder.start();
    backend.add(Uint8List.fromList([1, 2, 3, 4]));
    final cancelled = expectLater(
      first.completed,
      throwsA(isA<VoiceNoteRecordingCancelled>()),
    );

    await first.cancel();
    await cancelled;
    expect(backend.cancelCalls, 1);
    expect(recorder.isRecording, isFalse);

    final second = await recorder.start();
    backend.add(Uint8List.fromList([9, 10, 11, 12]));
    final recording = await second.stop();
    final wav = recording.takeBytes();
    expect(wav.sublist(44), [9, 10, 11, 12]);
    wav.fillRange(0, wav.length, 0);
    await recorder.dispose();
  });

  test('concurrent start and use after disposal are rejected', () async {
    final backend = _FakeVoiceRecorderBackend();
    final recorder = VoiceNoteRecorder(backend: backend);
    final session = await recorder.start();

    expect(recorder.start, throwsStateError);
    final cancelled = expectLater(
      session.completed,
      throwsA(isA<VoiceNoteRecordingCancelled>()),
    );
    await recorder.dispose();
    await cancelled;
    expect(backend.disposeCalls, 1);
    expect(recorder.start, throwsStateError);
  });

  test(
    'stop timeout cancels and fails without returning partial audio',
    () async {
      final backend = _FakeVoiceRecorderBackend(hangOnStop: true);
      final recorder = VoiceNoteRecorder(
        backend: backend,
        shutdownTimeout: const Duration(milliseconds: 5),
      );
      final session = await recorder.start();
      backend.add(Uint8List.fromList([1, 2]));

      await expectLater(
        session.stop(),
        throwsA(isA<VoiceNoteRecordingException>()),
      );
      await expectLater(
        session.completed,
        throwsA(isA<VoiceNoteRecordingException>()),
      );
      expect(backend.cancelCalls, 1);
      expect(recorder.isRecording, isFalse);
      await recorder.dispose();
    },
  );
}

final class _FakeVoiceRecorderBackend implements VoiceRecorderBackend {
  _FakeVoiceRecorderBackend({
    this.permission = true,
    this.pcm16Supported = true,
    this.incompatibleOnStart = false,
    this.hangOnStop = false,
  });

  final bool permission;
  final bool pcm16Supported;
  final bool incompatibleOnStart;
  final bool hangOnStop;

  StreamController<Uint8List>? _controller;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;

  void add(Uint8List bytes) => _controller!.add(bytes);

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> supportsPcm16() async => pcm16Supported;

  @override
  Future<Stream<Uint8List>> startPcm16({
    required void Function() onIncompatibleConfig,
  }) async {
    startCalls += 1;
    _controller = StreamController<Uint8List>();
    if (incompatibleOnStart) onIncompatibleConfig();
    return _controller!.stream;
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    if (hangOnStop) return Completer<void>().future;
    await _closeController();
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    await _closeController();
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _closeController();
  }

  Future<void> _closeController() async {
    final controller = _controller;
    _controller = null;
    if (controller == null || controller.isClosed) return;
    final closing = controller.close();
    if (controller.hasListener) await closing;
  }
}
