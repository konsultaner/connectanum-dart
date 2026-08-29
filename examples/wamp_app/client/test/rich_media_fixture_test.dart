import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/voice_note_playback.dart';

import '../integration_test/support/rich_media_fixtures.dart';

void main() {
  test('native GIF fixture decodes as two animated frames', () async {
    final bytes = nativeAnimatedGifBytes();
    expect(ascii.decode(bytes.sublist(0, 6)), 'GIF89a');

    final codec = await ui.instantiateImageCodec(bytes);
    addTearDown(codec.dispose);
    expect(codec.frameCount, 2);
    for (var index = 0; index < codec.frameCount; index += 1) {
      final frame = await codec.getNextFrame();
      expect(frame.duration, const Duration(milliseconds: 100));
      expect(frame.image.width, 1);
      expect(frame.image.height, 1);
      frame.image.dispose();
    }
  });

  test('native voice-note fixture is a non-silent two-second PCM WAV', () {
    final bytes = nativeVoiceNoteBytes();
    final data = ByteData.sublistView(bytes);
    final playback = VoiceNotePlaybackController(
      bytes,
      expectedDuration: const Duration(
        milliseconds: nativeVoiceNoteDurationMilliseconds,
      ),
      backend: const _NoopVoiceNoteBackend(),
    );
    addTearDown(playback.dispose);

    expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
    expect(data.getUint32(4, Endian.little) + 8, bytes.length);
    expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
    expect(ascii.decode(bytes.sublist(12, 16)), 'fmt ');
    expect(data.getUint16(20, Endian.little), 1);
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 16000);
    expect(data.getUint32(28, Endian.little), 32000);
    expect(data.getUint16(34, Endian.little), 16);
    expect(ascii.decode(bytes.sublist(36, 40)), 'data');
    expect(data.getUint32(40, Endian.little), bytes.length - 44);
    expect(bytes.skip(44), contains(isNot(0)));
    expect(
      (bytes.length - 44) ~/ 2 * 1000 ~/ 16000,
      nativeVoiceNoteDurationMilliseconds,
    );
  });
}

final class _NoopVoiceNoteBackend implements VoiceNotePlayerBackend {
  const _NoopVoiceNoteBackend();

  @override
  Stream<void> get completions => const Stream.empty();

  @override
  Stream<Duration> get durationChanges => const Stream.empty();

  @override
  Stream<Duration> get positionChanges => const Stream.empty();

  @override
  Stream<PlayerState> get stateChanges => const Stream.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play(Source source) async {}

  @override
  Future<void> release() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> seek(Duration position) async {}
}
