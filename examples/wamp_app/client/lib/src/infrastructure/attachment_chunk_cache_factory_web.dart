import 'dart:typed_data';

import 'package:idb_shim/idb_browser.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'attachment_chunk_cache_base.dart';

AttachmentChunkCache createPlatformAttachmentChunkCache() =>
    WebAttachmentChunkCache();

final class WebAttachmentChunkCache implements AttachmentChunkCache {
  static const _databaseName = 'wamp_app_attachments';
  static const _storeName = 'chunks';

  Future<Database>? _database;
  bool _disposed = false;

  @override
  Future<void> put({
    required String scope,
    required EncryptedAttachmentChunk chunk,
  }) async {
    _ensureActive();
    chunk.validate();
    final database = await _open();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    final key = _key(
      scope,
      chunk.messageId,
      chunk.attachmentId,
      chunk.chunkIndex,
    );
    final existing = await store.getObject(key);
    if (existing != null) {
      final cached = _decode(existing);
      if (!attachmentCacheBytesEqual(
        cached.encryptedBytes,
        chunk.encryptedBytes,
      )) {
        transaction.abort();
        throw const AttachmentCacheConflict();
      }
    } else {
      await store.put(chunk.toWampKeywords(), key);
    }
    await transaction.completed;
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
    final database = await _open();
    final transaction = database.transaction(_storeName, idbModeReadOnly);
    final value = await transaction
        .objectStore(_storeName)
        .getObject(_key(scope, messageId, attachmentId, chunkIndex));
    await transaction.completed;
    if (value == null) return null;
    final chunk = _decode(value);
    if (chunk.senderUsername != senderUsername.toLowerCase() ||
        chunk.messageId != messageId ||
        chunk.attachmentId != attachmentId ||
        chunk.chunkIndex != chunkIndex ||
        chunk.chunkCount != chunkCount) {
      throw const AttachmentCacheConflict();
    }
    return chunk;
  }

  @override
  Future<void> removeMessage({
    required String scope,
    required String messageId,
  }) async {
    _ensureActive();
    final database = await _open();
    final transaction = database.transaction(_storeName, idbModeReadWrite);
    final store = transaction.objectStore(_storeName);
    final prefix = '$scope\n$messageId\n';
    final keys = await store.getAllKeys();
    for (final key in keys.whereType<String>().where(
      (candidate) => candidate.startsWith(prefix),
    )) {
      await store.delete(key);
    }
    await transaction.completed;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final database = _database;
    _database = null;
    if (database != null) (await database).close();
  }

  Future<Database> _open() {
    _ensureActive();
    return _database ??= idbFactoryWeb.open(
      _databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        if (!event.database.objectStoreNames.contains(_storeName)) {
          event.database.createObjectStore(_storeName);
        }
      },
    );
  }

  EncryptedAttachmentChunk _decode(Object value) {
    if (value is! Map) throw const AttachmentCacheConflict();
    final mapped = Map<String, dynamic>.from(value);
    final bytes = mapped['encrypted_bytes'];
    if (bytes is List<int> && bytes is! Uint8List) {
      mapped['encrypted_bytes'] = Uint8List.fromList(bytes);
    }
    try {
      return EncryptedAttachmentChunk.fromWampKeywords(mapped);
    } on FormatException {
      throw const AttachmentCacheConflict();
    }
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
