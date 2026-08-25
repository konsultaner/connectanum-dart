import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'voice_note_playback_source.dart';

VoiceNotePlaybackSourceFactory createVoiceNotePlaybackSourceFactory() =>
    Platform.isAndroid || Platform.isWindows
    ? _MemoryVoiceNotePlaybackSourceFactory()
    : SecureTemporaryVoiceNotePlaybackSourceFactory();

final class _MemoryVoiceNotePlaybackSourceFactory
    implements VoiceNotePlaybackSourceFactory {
  @override
  Future<VoiceNotePlaybackSource> create(Uint8List wavBytes) async =>
      MemoryVoiceNotePlaybackSource(wavBytes);
}

final class SecureTemporaryVoiceNotePlaybackSourceFactory
    implements VoiceNotePlaybackSourceFactory {
  SecureTemporaryVoiceNotePlaybackSourceFactory({
    Future<Directory> Function()? temporaryDirectory,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Future<Directory> Function() _temporaryDirectory;

  @override
  Future<VoiceNotePlaybackSource> create(Uint8List wavBytes) async {
    final directory = await _temporaryDirectory();
    final scratch = await directory.createTemp('.wampapp-voice-');
    final file = File(path.join(scratch.path, 'audio.wav'));
    try {
      final sink = await file.open(mode: FileMode.writeOnly);
      try {
        await sink.writeFrom(wavBytes);
        await sink.flush();
      } finally {
        await sink.close();
      }
      return _SecureTemporaryVoiceNotePlaybackSource(file, scratch);
    } catch (_) {
      try {
        await _secureDelete(file);
      } finally {
        await _deleteDirectory(scratch);
      }
      rethrow;
    }
  }
}

final class _SecureTemporaryVoiceNotePlaybackSource
    implements VoiceNotePlaybackSource {
  _SecureTemporaryVoiceNotePlaybackSource(this._file, this._scratch)
    : _source = DeviceFileSource(_file.path, mimeType: 'audio/wav');

  final File _file;
  final Directory _scratch;
  final DeviceFileSource _source;
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
    Object? failure;
    try {
      await _secureDelete(_file);
    } catch (error) {
      failure = error;
    }
    try {
      await _deleteDirectory(_scratch);
    } catch (error) {
      failure ??= error;
    }
    if (failure != null) throw failure;
  }
}

Future<void> _deleteDirectory(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}

Future<void> _secureDelete(File file) async {
  if (!await file.exists()) return;
  Object? overwriteFailure;
  try {
    final byteCount = await file.length();
    final handle = await file.open(mode: FileMode.writeOnly);
    try {
      final zeros = Uint8List(64 * 1024);
      var remaining = byteCount;
      while (remaining > 0) {
        final count = min(remaining, zeros.length);
        await handle.writeFrom(zeros, 0, count);
        remaining -= count;
      }
      await handle.flush();
    } catch (error) {
      overwriteFailure = error;
    } finally {
      await handle.close();
    }
  } catch (error) {
    overwriteFailure = error;
  }
  try {
    await file.delete();
  } catch (_) {
    if (overwriteFailure != null) rethrow;
    rethrow;
  }
  if (overwriteFailure != null) {
    throw FileSystemException(
      'Voice-note playback file could not be overwritten before deletion.',
      file.path,
    );
  }
}
