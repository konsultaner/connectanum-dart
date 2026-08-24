import 'dart:typed_data';

import 'file_transfer_digest.dart';

FileTransferDigest createFileTransferDigest({
  required Object? anchor,
  required bool allowNative,
}) => DartFileTransferDigest();

Uint8List? nativeFileChunkBytes(Object? anchor) => null;

bool releaseNativeFileChunkBytes(Uint8List bytes) => false;

bool releaseNativeFileChunkMessage(Object? anchor) => false;
