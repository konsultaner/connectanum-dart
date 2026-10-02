class AttachmentSaveProbe {
  static Future<AttachmentSaveProbe> create() =>
      throw UnsupportedError('Native file probe');
  String get path => throw UnsupportedError('Native file probe');
  Future<bool> exists() => throw UnsupportedError('Native file probe');
  Future<List<int>> read() => throw UnsupportedError('Native file probe');
  Future<void> get writeStarted => throw UnsupportedError('Native file probe');
  List<int>? get submittedBytes => throw UnsupportedError('Native file probe');
  void releaseWrite() => throw UnsupportedError('Native file probe');
  void rejectWrite() => throw UnsupportedError('Native file probe');
  Future<void> delayWrites(Future<void> Function() save) =>
      throw UnsupportedError('Native file probe');
  Future<void> dispose() async {}
}
