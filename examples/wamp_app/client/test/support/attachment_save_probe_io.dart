import 'dart:async';
import 'dart:io';

class AttachmentSaveProbe {
  AttachmentSaveProbe._(this._directory);
  final Directory _directory;
  final _writeStarted = Completer<void>();
  final _releaseWrite = Completer<void>();
  List<int>? submittedBytes;

  static Future<AttachmentSaveProbe> create() async => AttachmentSaveProbe._(
    await Directory.systemTemp.createTemp('attachment-preview-regression-'),
  );

  String get path => '${_directory.path}/saved.txt';
  Future<bool> exists() => File(path).exists();
  Future<List<int>> read() => File(path).readAsBytes();
  Future<void> get writeStarted => _writeStarted.future;
  void releaseWrite() {
    if (!_releaseWrite.isCompleted) _releaseWrite.complete();
  }

  void rejectWrite() {
    _releaseWrite.completeError(StateError('controlled write failure'));
  }

  Future<void> delayWrites(Future<void> Function() save) {
    final parentZone = Zone.current;
    final destination = File(path);
    return IOOverrides.runZoned(
      save,
      createFile: (name) {
        if (name != path) return parentZone.run(() => File(name));
        return _DelayedFile(destination, (bytes) async {
          submittedBytes = bytes;
          _writeStarted.complete();
          await _releaseWrite.future;
        });
      },
    );
  }

  Future<void> dispose() async {
    releaseWrite();
    await _directory.delete(recursive: true);
  }
}

class _DelayedFile implements File {
  _DelayedFile(this.destination, this.beforeWrite);
  final File destination;
  final Future<void> Function(List<int>) beforeWrite;

  @override
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    await beforeWrite(bytes);
    return destination.writeAsBytes(bytes, mode: mode, flush: flush);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
