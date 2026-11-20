import 'dart:io';
import 'dart:typed_data';

import 'file_transfer.dart';

/// Creates a re-openable WAMP file source from a local path.
Future<WampFileSource> wampFileSourceFromPath(
  String path, {
  String? name,
  String? contentType,
  String? sha256Digest,
  Map<String, dynamic>? custom,
}) async {
  final file = File(path);
  final length = await file.length();
  final nativePath = file.absolute.path;
  return WampFileSource(
    name: name ?? file.uri.pathSegments.last,
    length: length,
    openRead: () => file.openRead().map(
      (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
    ),
    openReadChunks: (chunkSize) => _openFileChunks(file, chunkSize),
    contentType: contentType,
    sha256Digest: sha256Digest,
    nativePath: nativePath,
    custom: custom,
  );
}

Stream<Uint8List> _openFileChunks(File file, int chunkSize) async* {
  final opened = await file.open();
  try {
    while (true) {
      // Async readInto first receives an owned IO buffer, then copies it into
      // the destination. Keep that owned buffer for complete reads instead.
      var chunk = await opened.read(chunkSize);
      if (chunk.isEmpty) {
        break;
      }
      if (chunk.length < chunkSize) {
        final partial = BytesBuilder(copy: false)..add(chunk);
        var length = chunk.length;
        while (length < chunkSize) {
          final next = await opened.read(chunkSize - length);
          if (next.isEmpty) break;
          partial.add(next);
          length += next.length;
        }
        chunk = partial.takeBytes();
      }
      yield chunk;
      if (chunk.length < chunkSize) {
        break;
      }
    }
  } finally {
    await opened.close();
  }
}
