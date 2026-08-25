import 'voice_note_playback_source.dart';
import 'voice_note_playback_source_factory_stub.dart'
    if (dart.library.io) 'voice_note_playback_source_factory_io.dart'
    if (dart.library.js_interop) 'voice_note_playback_source_factory_web.dart'
    as platform;

VoiceNotePlaybackSourceFactory createVoiceNotePlaybackSourceFactory() =>
    platform.createVoiceNotePlaybackSourceFactory();
