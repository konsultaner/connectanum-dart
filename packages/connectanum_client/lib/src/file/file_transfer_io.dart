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
    contentType: contentType,
    sha256Digest: sha256Digest,
    nativePath: nativePath,
    custom: custom,
  );
}
