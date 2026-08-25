import 'voice_note_playback_source.dart';

VoiceNotePlaybackSourceFactory createVoiceNotePlaybackSourceFactory() =>
    _WebVoiceNotePlaybackSourceFactory();

final class _WebVoiceNotePlaybackSourceFactory
    implements VoiceNotePlaybackSourceFactory {
  @override
  Future<VoiceNotePlaybackSource> create(wavBytes) async =>
      MemoryVoiceNotePlaybackSource(wavBytes);
}
