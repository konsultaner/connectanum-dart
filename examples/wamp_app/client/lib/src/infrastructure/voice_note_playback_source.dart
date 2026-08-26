import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

abstract interface class VoiceNotePlaybackSource {
  Source get audioSource;

  Future<void> dispose();
}

abstract interface class VoiceNotePlaybackSourceFactory {
  Future<VoiceNotePlaybackSource> create(Uint8List wavBytes);
}

final class MemoryVoiceNotePlaybackSource implements VoiceNotePlaybackSource {
  MemoryVoiceNotePlaybackSource(Uint8List wavBytes)
    : _source = BytesSource(
        Uint8List.fromList(wavBytes),
        mimeType: 'audio/wav',
      );

  final BytesSource _source;
  var _disposed = false;

  @override
  Source get audioSource {
    if (_disposed) throw StateError('The playback source was disposed.');
    return _source;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _source.bytes.fillRange(0, _source.bytes.length, 0);
  }
}
