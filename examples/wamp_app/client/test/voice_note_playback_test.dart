import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/voice_note_playback.dart';
import 'package:wamp_app/src/infrastructure/voice_note_playback_source.dart';
import 'package:wamp_app/src/infrastructure/voice_note_playback_source_factory_io.dart';

void main() {
  test('memory playback source owns and wipes its byte copy', () async {
    final original = Uint8List.fromList([1, 2, 3, 4]);
    final source = MemoryVoiceNotePlaybackSource(original);
    final playerBytes = (source.audioSource as BytesSource).bytes;

    original.fillRange(0, original.length, 9);
    expect(playerBytes, [1, 2, 3, 4]);
    await source.dispose();
    expect(playerBytes, everyElement(0));
    expect(() => source.audioSource, throwsStateError);
  });

  test('managed playback file is random, private, and deleted', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wampapp-voice-source-',
    );
    final factory = SecureTemporaryVoiceNotePlaybackSourceFactory(
      temporaryDirectory: () async => directory,
    );
    final bytes = Uint8List.fromList([82, 73, 70, 70, 1, 2, 3, 4]);

    final source = await factory.create(bytes);
    final path = (source.audioSource as DeviceFileSource).path;
    final file = File(path);
    expect(path, startsWith(directory.path));
    expect(path, isNot(contains('voice.wav')));
    expect(await file.readAsBytes(), bytes);

    await source.dispose();
    expect(await file.exists(), isFalse);
    await directory.delete(recursive: true);
  });

  test('controller serializes playback and ignores late events', () async {
    final events = <String>[];
    final backend = _FakeVoiceNotePlayerBackend(events: events);
    final factory = _FakePlaybackSourceFactory(events);
    final callerBytes = _voiceWav(64000);
    final controller = VoiceNotePlaybackController(
      callerBytes,
      expectedDuration: const Duration(seconds: 2),
      backend: backend,
      sourceFactory: factory,
    );
    callerBytes.fillRange(0, callerBytes.length, 0);

    await controller.play();
    expect(factory.createCalls, 1);
    expect(factory.createdBytes!.sublist(0, 4), [82, 73, 70, 70]);
    expect(backend.playCalls, 1);
    backend.states.add(PlayerState.playing);
    backend.positions.add(const Duration(milliseconds: 500));
    backend.durations.add(const Duration(milliseconds: 1900));
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, VoiceNotePlaybackState.playing);
    expect(controller.position, const Duration(milliseconds: 500));
    expect(controller.duration, const Duration(milliseconds: 1900));

    await controller.pause();
    await controller.resume();
    await controller.seek(const Duration(seconds: 10));
    expect(backend.pauseCalls, 1);
    expect(backend.resumeCalls, 1);
    expect(backend.lastSeek, const Duration(milliseconds: 1900));

    backend.completes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, VoiceNotePlaybackState.stopped);
    expect(controller.position, controller.duration);

    await controller.disposeAsync();
    expect(factory.createdBytes, everyElement(0));
    expect(
      events,
      containsAllInOrder(['release', 'backend-dispose', 'source-dispose']),
    );
    backend.states.add(PlayerState.playing);
    backend.positions.add(const Duration(seconds: 1));
    backend.completes.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(controller.play, throwsStateError);
    await backend.close();
  });

  test('controller rejects malformed or duration-mismatched WAVs', () {
    expect(
      () => VoiceNotePlaybackController(
        Uint8List(44),
        expectedDuration: const Duration(seconds: 1),
      ),
      throwsFormatException,
    );
    expect(
      () => VoiceNotePlaybackController(
        _voiceWav(32000),
        expectedDuration: const Duration(seconds: 2),
      ),
      throwsFormatException,
    );
  });

  test('source cleanup still runs when player disposal fails', () async {
    final events = <String>[];
    final backend = _FakeVoiceNotePlayerBackend(
      events: events,
      failDispose: true,
    );
    final factory = _FakePlaybackSourceFactory(events);
    final controller = VoiceNotePlaybackController(
      _voiceWav(32000),
      expectedDuration: const Duration(seconds: 1),
      backend: backend,
      sourceFactory: factory,
    );
    await controller.play();

    await expectLater(controller.disposeAsync(), throwsStateError);
    expect(factory.source!.disposed, isTrue);
    expect(events.last, 'source-dispose');
    await backend.close();
  });
}

Uint8List _voiceWav(int pcmBytes) {
  final bytes = Uint8List(44 + pcmBytes);
  final data = ByteData.sublistView(bytes);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      bytes[offset + index] = value.codeUnitAt(index);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + pcmBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, pcmBytes, Endian.little);
  return bytes;
}

final class _FakePlaybackSourceFactory
    implements VoiceNotePlaybackSourceFactory {
  _FakePlaybackSourceFactory(this.events);

  final List<String> events;
  int createCalls = 0;
  Uint8List? createdBytes;
  _FakePlaybackSource? source;

  @override
  Future<VoiceNotePlaybackSource> create(Uint8List wavBytes) async {
    createCalls += 1;
    createdBytes = wavBytes;
    return source = _FakePlaybackSource(events);
  }
}

final class _FakePlaybackSource implements VoiceNotePlaybackSource {
  _FakePlaybackSource(this.events);

  final List<String> events;
  final Source _source = BytesSource(Uint8List.fromList([1, 2]));
  bool disposed = false;

  @override
  Source get audioSource => _source;

  @override
  Future<void> dispose() async {
    disposed = true;
    events.add('source-dispose');
  }
}

final class _FakeVoiceNotePlayerBackend implements VoiceNotePlayerBackend {
  _FakeVoiceNotePlayerBackend({required this.events, this.failDispose = false});

  final List<String> events;
  final bool failDispose;
  final states = StreamController<PlayerState>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration>.broadcast();
  final completes = StreamController<void>.broadcast();

  int playCalls = 0;
  int pauseCalls = 0;
  int resumeCalls = 0;
  Duration? lastSeek;

  @override
  Stream<PlayerState> get stateChanges => states.stream;

  @override
  Stream<Duration> get positionChanges => positions.stream;

  @override
  Stream<Duration> get durationChanges => durations.stream;

  @override
  Stream<void> get completions => completes.stream;

  @override
  Future<void> play(Source source) async {
    playCalls += 1;
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
  }

  @override
  Future<void> resume() async {
    resumeCalls += 1;
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
  }

  @override
  Future<void> release() async {
    events.add('release');
  }

  @override
  Future<void> dispose() async {
    events.add('backend-dispose');
    if (failDispose) throw StateError('player disposal failed');
  }

  Future<void> close() async {
    await states.close();
    await positions.close();
    await durations.close();
    await completes.close();
  }
}
