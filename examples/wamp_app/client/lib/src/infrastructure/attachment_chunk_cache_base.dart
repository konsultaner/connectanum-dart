import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class AttachmentCacheConflict implements Exception {
  const AttachmentCacheConflict();

  @override
  String toString() => 'Encrypted attachment cache data conflicts.';
}

final class AttachmentCacheMiss implements Exception {
  const AttachmentCacheMiss();

  @override
  String toString() => 'Encrypted attachment cache data is unavailable.';
}

abstract interface class AttachmentChunkCache {
  Future<void> put({
    required String scope,
    required EncryptedAttachmentChunk chunk,
  });

  Future<EncryptedAttachmentChunk?> get({
    required String scope,
    required String senderUsername,
    required String messageId,
    required String attachmentId,
    required int chunkIndex,
    required int chunkCount,
  });

  Future<void> removeMessage({
    required String scope,
    required String messageId,
  });

  Future<void> dispose();
}

String attachmentCacheScope(ServerEndpoint endpoint, String username) => sha256
    .convert(utf8.encode('${endpoint.websocketUri}\n${username.toLowerCase()}'))
    .toString();

String attachmentCacheDigest(Uint8List bytes) =>
    sha256.convert(bytes).toString();

bool attachmentCacheBytesEqual(Uint8List left, Uint8List right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

final class MemoryAttachmentChunkCache implements AttachmentChunkCache {
  final Map<String, EncryptedAttachmentChunk> _chunks = {};
  bool _disposed = false;

  @override
  Future<void> put({
    required String scope,
    required EncryptedAttachmentChunk chunk,
  }) async {
    _ensureActive();
    chunk.validate();
    final key = _key(
      scope,
      chunk.messageId,
      chunk.attachmentId,
      chunk.chunkIndex,
    );
    final existing = _chunks[key];
    if (existing != null &&
        !attachmentCacheBytesEqual(
          existing.encryptedBytes,
          chunk.encryptedBytes,
        )) {
      throw const AttachmentCacheConflict();
    }
    _chunks[key] = EncryptedAttachmentChunk.fromWampKeywords(
      chunk.toWampKeywords(),
    );
  }

  @override
  Future<EncryptedAttachmentChunk?> get({
    required String scope,
    required String senderUsername,
    required String messageId,
    required String attachmentId,
    required int chunkIndex,
    required int chunkCount,
  }) async {
    _ensureActive();
    final value = _chunks[_key(scope, messageId, attachmentId, chunkIndex)];
    if (value == null) return null;
    if (value.senderUsername != senderUsername.toLowerCase() ||
        value.chunkCount != chunkCount) {
      throw const AttachmentCacheConflict();
    }
    return EncryptedAttachmentChunk.fromWampKeywords(value.toWampKeywords());
  }

  @override
  Future<void> removeMessage({
    required String scope,
    required String messageId,
  }) async {
    _ensureActive();
    final prefix = '$scope\n$messageId\n';
    _chunks.removeWhere((key, _) => key.startsWith(prefix));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _chunks.clear();
  }

  String _key(
    String scope,
    String messageId,
    String attachmentId,
    int chunkIndex,
  ) => '$scope\n$messageId\n$attachmentId\n$chunkIndex';

  void _ensureActive() {
    if (_disposed) throw StateError('Attachment cache is disposed.');
  }
}
