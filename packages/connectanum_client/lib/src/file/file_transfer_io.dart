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
      final chunk = Uint8List(chunkSize);
      var length = 0;
      while (length < chunk.length) {
        final read = await opened.readInto(chunk, length, chunk.length);
        if (read == 0) {
          break;
        }
        length += read;
      }
      if (length == 0) {
        break;
      }
      yield length == chunk.length
          ? chunk
          : Uint8List.sublistView(chunk, 0, length);
      if (length < chunk.length) {
        break;
      }
    }
  } finally {
    await opened.close();
  }
}
