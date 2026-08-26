import 'voice_note_playback_source.dart';

VoiceNotePlaybackSourceFactory createVoiceNotePlaybackSourceFactory() =>
    _MemoryVoiceNotePlaybackSourceFactory();

final class _MemoryVoiceNotePlaybackSourceFactory
    implements VoiceNotePlaybackSourceFactory {
  @override
  Future<VoiceNotePlaybackSource> create(wavBytes) async =>
      MemoryVoiceNotePlaybackSource(wavBytes);
}
