import 'dart:io';
import 'dart:math';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'attachment_chunk_cache_base.dart';

AttachmentChunkCache createPlatformAttachmentChunkCache() =>
    NativeAttachmentChunkCache();

final class NativeAttachmentChunkCache implements AttachmentChunkCache {
  NativeAttachmentChunkCache({Future<Directory> Function()? rootDirectory})
    : _rootDirectory = rootDirectory ?? _defaultRoot;

  final Future<Directory> Function() _rootDirectory;
  final Random _random = Random.secure();
  Future<Directory>? _root;
  bool _disposed = false;

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(path.join(support.path, 'wamp_app', 'attachments'));
  }

  @override
  Future<void> put({
    required String scope,
    required EncryptedAttachmentChunk chunk,
  }) async {
    _ensureActive();
    chunk.validate();
    final target = await _chunkFile(
      scope: scope,
      messageId: chunk.messageId,
      attachmentId: chunk.attachmentId,
      chunkIndex: chunk.chunkIndex,
    );
    await target.parent.create(recursive: true);
    final bytes = chunk.encryptedBytes;
    if (await target.exists()) {
      final existing = await target.readAsBytes();
      if (!attachmentCacheBytesEqual(existing, bytes)) {
        throw const AttachmentCacheConflict();
      }
      return;
    }
    final temporary = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-'
      '${_random.nextInt(1 << 32)}',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        if (!await target.exists()) rethrow;
        final existing = await target.readAsBytes();
        if (!attachmentCacheBytesEqual(existing, bytes)) {
          throw const AttachmentCacheConflict();
        }
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
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
    final file = await _chunkFile(
      scope: scope,
      messageId: messageId,
      attachmentId: attachmentId,
      chunkIndex: chunkIndex,
    );
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return EncryptedAttachmentChunk(
      senderUsername: senderUsername,
      messageId: messageId,
      attachmentId: attachmentId,
      chunkIndex: chunkIndex,
      chunkCount: chunkCount,
      ciphertextSha256: attachmentCacheDigest(bytes),
      encryptedBytes: bytes,
    );
  }

  @override
  Future<void> removeMessage({
    required String scope,
    required String messageId,
  }) async {
    _ensureActive();
    final root = await _openRoot();
    final directory = Directory(
      path.join(root.path, _hash(scope), _hash(messageId)),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }

  Future<File> _chunkFile({
    required String scope,
    required String messageId,
    required String attachmentId,
    required int chunkIndex,
  }) async {
    final root = await _openRoot();
    return File(
      path.join(
        root.path,
        _hash(scope),
        _hash(messageId),
        _hash(attachmentId),
        '$chunkIndex.chunk',
      ),
    );
  }

  Future<Directory> _openRoot() async {
    _ensureActive();
    final root = await (_root ??= _rootDirectory());
    await root.create(recursive: true);
    return root;
  }

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

  void _ensureActive() {
    if (_disposed) throw StateError('Attachment cache is disposed.');
  }
}
