import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class AttachmentChunkStoreResult {
  const AttachmentChunkStoreResult({
    required this.receipt,
    required this.status,
  });

  final AttachmentChunkReceipt receipt;
  final AttachmentUploadStatus status;
}

final class AttachmentConflict implements Exception {
  const AttachmentConflict(this.attachmentId);

  final String attachmentId;
}

final class AttachmentNotFound implements Exception {
  const AttachmentNotFound(this.attachmentId);

  final String attachmentId;
}

final class AttachmentIncomplete implements Exception {
  const AttachmentIncomplete(this.attachmentId);

  final String attachmentId;
}

final class AttachmentUnavailable implements Exception {
  const AttachmentUnavailable(this.attachmentId);

  final String attachmentId;
}

final class AttachmentQuotaExceeded implements Exception {
  const AttachmentQuotaExceeded();
}

final class AttachmentPruneResult {
  const AttachmentPruneResult({
    required this.removedAttachments,
    required this.removedBytes,
  });

  final int removedAttachments;
  final int removedBytes;
}

/// Stores only opaque attachment ciphertext and routing-safe identifiers.
final class AttachmentStore {
  AttachmentStore(
    String path, {
    this.maxTotalBytes = 10 * 1024 * 1024 * 1024,
    this.maxBytesPerSender = 2 * 1024 * 1024 * 1024,
    this.stagingTtl = const Duration(hours: 24),
    DateTime Function()? clock,
  }) : directory = Directory(path),
       _clock = clock ?? DateTime.now {
    if (maxTotalBytes <= 0 ||
        maxBytesPerSender <= 0 ||
        maxBytesPerSender > maxTotalBytes ||
        stagingTtl <= Duration.zero) {
      throw ArgumentError('Attachment storage limits are invalid.');
    }
  }

  final Directory directory;
  final int maxTotalBytes;
  final int maxBytesPerSender;
  final Duration stagingTtl;
  final DateTime Function() _clock;
  final Map<String, Future<void>> _writeTails = {};
  final Map<String, _AttachmentRecord> _records = {};
  final Map<String, int> _senderBytes = {};
  final Random _random = Random.secure();
  var _totalBytes = 0;
  var _initialized = false;

  int get totalBytes => _totalBytes;

  int bytesForSender(String senderUsername) =>
      _senderBytes[AccountRegistration.normalizeUsername(senderUsername)] ?? 0;

  Future<void> initialize() => _serializeMutation(() async {
    _initialized = false;
    _records.clear();
    _senderBytes.clear();
    _totalBytes = 0;
    await directory.create(recursive: true);
    await _reconcileDirectoryTree();
    _initialized = true;
  });

  Future<void> _reconcileDirectoryTree() async {
    await for (final senderEntity in directory.list(followLinks: false)) {
      if (senderEntity is! Directory) {
        await _deleteEntity(senderEntity);
        continue;
      }
      await for (final messageEntity in senderEntity.list(followLinks: false)) {
        if (messageEntity is! Directory) {
          await _deleteEntity(messageEntity);
          continue;
        }
        await for (final attachmentEntity in messageEntity.list(
          followLinks: false,
        )) {
          if (attachmentEntity is! Directory) {
            await _deleteEntity(attachmentEntity);
            continue;
          }
          await _reconcileAttachmentDirectory(
            senderEntity,
            messageEntity,
            attachmentEntity,
          );
        }
        await _deleteIfEmpty(messageEntity);
      }
      await _deleteIfEmpty(senderEntity);
    }
  }

  Future<void> _reconcileAttachmentDirectory(
    Directory senderDirectory,
    Directory messageDirectory,
    Directory attachmentDirectory,
  ) async {
    final manifestFile = File(
      p.join(attachmentDirectory.path, 'manifest.json'),
    );
    final manifest = await _readManifest(manifestFile);
    if (manifest == null) {
      await attachmentDirectory.delete(recursive: true);
      return;
    }
    if (p.basename(senderDirectory.path) != _segment(manifest.senderUsername) ||
        p.basename(messageDirectory.path) != _segment(manifest.messageId) ||
        p.basename(attachmentDirectory.path) !=
            _segment(manifest.attachmentId)) {
      throw AttachmentUnavailable(manifest.attachmentId);
    }

    final expectedFiles = <String>{'manifest.json'};
    for (final entry in manifest.chunks.entries) {
      final chunkName = _chunkName(entry.key);
      expectedFiles.add(chunkName);
      final chunkFile = File(p.join(attachmentDirectory.path, chunkName));
      if (!await chunkFile.exists()) {
        throw AttachmentUnavailable(manifest.attachmentId);
      }
      final bytes = await chunkFile.readAsBytes();
      if (bytes.length != entry.value.bytes ||
          sha256.convert(bytes).toString() != entry.value.sha256Digest) {
        throw AttachmentUnavailable(manifest.attachmentId);
      }
    }
    await for (final entity in attachmentDirectory.list(followLinks: false)) {
      if (!expectedFiles.contains(p.basename(entity.path))) {
        await _deleteEntity(entity);
      }
    }
    if (manifest.needsRewrite) {
      await _writeJsonAtomically(manifestFile, manifest.toJson());
    }
    final key = _storageKey(
      manifest.senderUsername,
      manifest.messageId,
      manifest.attachmentId,
    );
    if (_records.containsKey(key)) {
      throw AttachmentUnavailable(manifest.attachmentId);
    }
    final record = _AttachmentRecord(
      directory: attachmentDirectory,
      manifest: manifest,
    );
    _records[key] = record;
    _addUsage(manifest.senderUsername, manifest.storedBytes);
  }

  Future<AttachmentChunkStoreResult> put(EncryptedAttachmentChunk chunk) {
    chunk.validate();
    _ensureInitialized();
    final key = _storageKey(
      chunk.senderUsername,
      chunk.messageId,
      chunk.attachmentId,
    );
    return _serializeMutation(
      () => _serialize(key, () async {
        final bytes = chunk.encryptedBytes;
        final actualDigest = sha256.convert(bytes).toString();
        if (actualDigest != chunk.ciphertextSha256.toLowerCase()) {
          throw const FormatException(
            'Attachment ciphertext checksum does not match its bytes.',
          );
        }
        final attachmentDirectory = _attachmentDirectory(
          chunk.senderUsername,
          chunk.messageId,
          chunk.attachmentId,
        );
        final manifestFile = File(
          p.join(attachmentDirectory.path, 'manifest.json'),
        );
        final timestamp = _now();
        final manifest =
            await _readManifest(manifestFile) ??
            _AttachmentManifest(
              senderUsername: chunk.senderUsername,
              messageId: chunk.messageId,
              attachmentId: chunk.attachmentId,
              chunkCount: chunk.chunkCount,
              chunks: const {},
              createdAt: timestamp,
              updatedAt: timestamp,
            );
        if (!manifest.matchesChunk(chunk)) {
          throw AttachmentConflict(chunk.attachmentId);
        }

        final existing = manifest.chunks[chunk.chunkIndex];
        final chunkFile = File(
          p.join(attachmentDirectory.path, _chunkName(chunk.chunkIndex)),
        );
        var duplicate = false;
        var wroteChunk = false;
        if (existing != null) {
          if (existing.sha256Digest != actualDigest ||
              existing.bytes != bytes.length ||
              !await chunkFile.exists() ||
              !_sameBytes(await chunkFile.readAsBytes(), bytes)) {
            throw AttachmentConflict(chunk.attachmentId);
          }
          duplicate = true;
        } else if (await chunkFile.exists()) {
          final stored = await chunkFile.readAsBytes();
          if (!_sameBytes(stored, bytes)) {
            throw AttachmentConflict(chunk.attachmentId);
          }
        } else {
          _ensureQuota(chunk.senderUsername, bytes.length);
          await attachmentDirectory.create(recursive: true);
          await _writeBytesAtomically(chunkFile, bytes);
          wroteChunk = true;
        }

        final nextManifest = existing == null
            ? manifest.withChunk(
                chunk.chunkIndex,
                _StoredChunk(bytes: bytes.length, sha256Digest: actualDigest),
                updatedAt: timestamp,
              )
            : manifest;
        if (existing == null) {
          if (!wroteChunk) {
            _ensureQuota(chunk.senderUsername, bytes.length);
          }
          try {
            await attachmentDirectory.create(recursive: true);
            await _writeJsonAtomically(manifestFile, nextManifest.toJson());
          } catch (_) {
            if (wroteChunk && await chunkFile.exists()) {
              await chunkFile.delete();
            }
            rethrow;
          }
          _addUsage(chunk.senderUsername, bytes.length);
        }
        _records[key] = _AttachmentRecord(
          directory: attachmentDirectory,
          manifest: nextManifest,
        );
        final status = await _statusForManifest(
          attachmentDirectory,
          nextManifest,
        );
        return AttachmentChunkStoreResult(
          receipt: AttachmentChunkReceipt(
            messageId: chunk.messageId,
            attachmentId: chunk.attachmentId,
            chunkIndex: chunk.chunkIndex,
            ciphertextSha256: actualDigest,
            duplicate: duplicate,
            complete: status.complete,
          ),
          status: status,
        );
      }),
    );
  }

  Future<AttachmentUploadStatus> status({
    required String senderUsername,
    required String messageId,
    required String attachmentId,
    required int chunkCount,
  }) {
    _ensureInitialized();
    final normalizedSender = AccountRegistration.normalizeUsername(
      senderUsername,
    );
    _validateLookup(normalizedSender, messageId, attachmentId, chunkCount);
    final key = _storageKey(normalizedSender, messageId, attachmentId);
    return _serialize(key, () async {
      final attachmentDirectory = _attachmentDirectory(
        normalizedSender,
        messageId,
        attachmentId,
      );
      final manifest = await _readManifest(
        File(p.join(attachmentDirectory.path, 'manifest.json')),
      );
      if (manifest == null) {
        return AttachmentUploadStatus(
          messageId: messageId,
          attachmentId: attachmentId,
          chunkCount: chunkCount,
          receivedChunks: const [],
        );
      }
      if (!manifest.matches(
        senderUsername: normalizedSender,
        messageId: messageId,
        attachmentId: attachmentId,
        chunkCount: chunkCount,
      )) {
        throw AttachmentConflict(attachmentId);
      }
      return _statusForManifest(attachmentDirectory, manifest);
    });
  }

  Future<void> requireComplete(EncryptedChatMessage message) async {
    _ensureInitialized();
    await _serializeMutation(() => _requireCompleteLocked(message));
  }

  Future<T> commitMessage<T>(
    EncryptedChatMessage message,
    Future<T> Function() commit,
  ) {
    _ensureInitialized();
    return _serializeMutation(() async {
      await _requireCompleteLocked(message);
      return commit();
    });
  }

  Future<void> _requireCompleteLocked(EncryptedChatMessage message) async {
    for (final attachmentId in message.attachmentIds) {
      final key = _storageKey(
        message.senderUsername,
        message.messageId,
        attachmentId,
      );
      await _serialize(key, () async {
        final attachmentDirectory = _attachmentDirectory(
          message.senderUsername,
          message.messageId,
          attachmentId,
        );
        final manifest = await _readManifest(
          File(p.join(attachmentDirectory.path, 'manifest.json')),
        );
        if (manifest == null ||
            !manifest.matchesIdentity(
              senderUsername: message.senderUsername,
              messageId: message.messageId,
              attachmentId: attachmentId,
            )) {
          throw AttachmentIncomplete(attachmentId);
        }
        final status = await _statusForManifest(attachmentDirectory, manifest);
        if (!status.complete) throw AttachmentIncomplete(attachmentId);
        await _verifyManifestContents(attachmentDirectory, manifest);
      });
    }
  }

  Future<AttachmentPruneResult> prune({
    required Future<Iterable<EncryptedChatMessage>> Function()
    loadActiveMessages,
    DateTime? now,
  }) {
    _ensureInitialized();
    return _serializeMutation(() async {
      final timestamp = (now ?? _clock()).toUtc();
      final activeKeys = <String>{};
      for (final message in await loadActiveMessages()) {
        if (message.isExpiredAt(timestamp)) continue;
        for (final attachmentId in message.attachmentIds) {
          activeKeys.add(
            _storageKey(
              message.senderUsername,
              message.messageId,
              attachmentId,
            ),
          );
        }
      }
      final cutoff = timestamp.subtract(stagingTtl);
      var removedAttachments = 0;
      var removedBytes = 0;
      for (final entry in List<MapEntry<String, _AttachmentRecord>>.of(
        _records.entries,
      )) {
        if (activeKeys.contains(entry.key) ||
            entry.value.manifest.updatedAt.isAfter(cutoff)) {
          continue;
        }
        await _serialize(entry.key, () async {
          final record = _records[entry.key];
          if (record == null || activeKeys.contains(entry.key)) return;
          final manifestFile = File(
            p.join(record.directory.path, 'manifest.json'),
          );
          final manifest = await _readManifest(manifestFile);
          if (manifest != null && manifest.updatedAt.isAfter(cutoff)) return;
          if (await record.directory.exists()) {
            await record.directory.delete(recursive: true);
          }
          _records.remove(entry.key);
          final bytes = manifest?.storedBytes ?? record.manifest.storedBytes;
          _removeUsage(record.manifest.senderUsername, bytes);
          removedAttachments += 1;
          removedBytes += bytes;
          await _deleteEmptyParents(record.directory);
        });
      }
      return AttachmentPruneResult(
        removedAttachments: removedAttachments,
        removedBytes: removedBytes,
      );
    });
  }

  Future<EncryptedAttachmentChunk> readChunk({
    required String senderUsername,
    required String messageId,
    required String attachmentId,
    required int chunkIndex,
  }) {
    _ensureInitialized();
    final normalizedSender = AccountRegistration.normalizeUsername(
      senderUsername,
    );
    _validateLookup(normalizedSender, messageId, attachmentId, 1);
    if (chunkIndex < 0 || chunkIndex >= WampAppAttachmentLimits.maxChunkCount) {
      throw const FormatException('Attachment chunk index is invalid.');
    }
    final key = _storageKey(normalizedSender, messageId, attachmentId);
    return _serialize(key, () async {
      final attachmentDirectory = _attachmentDirectory(
        normalizedSender,
        messageId,
        attachmentId,
      );
      final manifest = await _readManifest(
        File(p.join(attachmentDirectory.path, 'manifest.json')),
      );
      if (manifest == null ||
          !manifest.matchesIdentity(
            senderUsername: normalizedSender,
            messageId: messageId,
            attachmentId: attachmentId,
          ) ||
          chunkIndex >= manifest.chunkCount) {
        throw AttachmentNotFound(attachmentId);
      }
      final stored = manifest.chunks[chunkIndex];
      final chunkFile = File(
        p.join(attachmentDirectory.path, _chunkName(chunkIndex)),
      );
      if (stored == null || !await chunkFile.exists()) {
        throw AttachmentNotFound(attachmentId);
      }
      final bytes = await chunkFile.readAsBytes();
      if (bytes.length != stored.bytes ||
          sha256.convert(bytes).toString() != stored.sha256Digest) {
        throw AttachmentUnavailable(attachmentId);
      }
      return EncryptedAttachmentChunk(
        senderUsername: normalizedSender,
        messageId: messageId,
        attachmentId: attachmentId,
        chunkIndex: chunkIndex,
        chunkCount: manifest.chunkCount,
        ciphertextSha256: stored.sha256Digest,
        encryptedBytes: bytes,
      );
    });
  }

  Future<AttachmentUploadStatus> _statusForManifest(
    Directory attachmentDirectory,
    _AttachmentManifest manifest,
  ) async {
    final received = <int>[];
    for (final entry in manifest.chunks.entries) {
      final file = File(
        p.join(attachmentDirectory.path, _chunkName(entry.key)),
      );
      if (!await file.exists() || await file.length() != entry.value.bytes) {
        throw AttachmentUnavailable(manifest.attachmentId);
      }
      received.add(entry.key);
    }
    received.sort();
    return AttachmentUploadStatus(
      messageId: manifest.messageId,
      attachmentId: manifest.attachmentId,
      chunkCount: manifest.chunkCount,
      receivedChunks: received,
    );
  }

  Future<void> _verifyManifestContents(
    Directory attachmentDirectory,
    _AttachmentManifest manifest,
  ) async {
    for (final entry in manifest.chunks.entries) {
      final file = File(
        p.join(attachmentDirectory.path, _chunkName(entry.key)),
      );
      if (!await file.exists()) {
        throw AttachmentUnavailable(manifest.attachmentId);
      }
      final bytes = await file.readAsBytes();
      if (bytes.length != entry.value.bytes ||
          sha256.convert(bytes).toString() != entry.value.sha256Digest) {
        throw AttachmentUnavailable(manifest.attachmentId);
      }
    }
  }

  Future<_AttachmentManifest?> _readManifest(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException();
      return _AttachmentManifest.fromJson(
        Map<String, dynamic>.from(decoded),
        legacyTimestamp: (await file.lastModified()).toUtc(),
      );
    } on FormatException {
      throw AttachmentUnavailable(p.basename(file.parent.path));
    }
  }

  Directory _attachmentDirectory(
    String senderUsername,
    String messageId,
    String attachmentId,
  ) => Directory(
    p.join(
      directory.path,
      _segment(senderUsername),
      _segment(messageId),
      _segment(attachmentId),
    ),
  );

  String _storageKey(
    String senderUsername,
    String messageId,
    String attachmentId,
  ) => '$senderUsername\n$messageId\n$attachmentId';

  String _segment(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  String _chunkName(int index) =>
      'chunk-${index.toString().padLeft(3, '0')}.bin';

  DateTime _now() => _clock().toUtc();

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('AttachmentStore.initialize must complete first.');
    }
  }

  void _ensureQuota(String senderUsername, int additionalBytes) {
    if (_totalBytes + additionalBytes > maxTotalBytes ||
        (_senderBytes[senderUsername] ?? 0) + additionalBytes >
            maxBytesPerSender) {
      throw const AttachmentQuotaExceeded();
    }
  }

  void _addUsage(String senderUsername, int bytes) {
    _totalBytes += bytes;
    _senderBytes[senderUsername] = (_senderBytes[senderUsername] ?? 0) + bytes;
  }

  void _removeUsage(String senderUsername, int bytes) {
    _totalBytes -= bytes;
    final remaining = (_senderBytes[senderUsername] ?? bytes) - bytes;
    if (remaining <= 0) {
      _senderBytes.remove(senderUsername);
    } else {
      _senderBytes[senderUsername] = remaining;
    }
  }

  Future<void> _deleteEmptyParents(Directory attachmentDirectory) async {
    var parent = attachmentDirectory.parent;
    final root = p.normalize(directory.absolute.path);
    while (p.normalize(parent.absolute.path) != root) {
      if (!await parent.exists() || !await parent.list().isEmpty) return;
      final next = parent.parent;
      await parent.delete();
      parent = next;
    }
  }

  Future<void> _deleteIfEmpty(Directory value) async {
    if (await value.exists() && await value.list().isEmpty) {
      await value.delete();
    }
  }

  Future<void> _deleteEntity(FileSystemEntity entity) =>
      entity.delete(recursive: entity is Directory);

  Future<void> _writeBytesAtomically(File file, Uint8List bytes) async {
    final temporary = File('${file.path}.tmp-${_random.nextInt(1 << 32)}');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _writeJsonAtomically(
    File file,
    Map<String, dynamic> value,
  ) async {
    final temporary = File('${file.path}.tmp-${_random.nextInt(1 << 32)}');
    try {
      await temporary.writeAsString(jsonEncode(value), flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<T> _serialize<T>(String key, Future<T> Function() action) {
    final previous = _writeTails[key] ?? Future<void>.value();
    final completer = Completer<T>();
    late final Future<void> tail;
    tail = previous
        .catchError((_) {})
        .then<void>((_) async {
          try {
            completer.complete(await action());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        })
        .whenComplete(() {
          if (identical(_writeTails[key], tail)) _writeTails.remove(key);
        });
    _writeTails[key] = tail;
    return completer.future;
  }

  Future<T> _serializeMutation<T>(Future<T> Function() action) =>
      _serialize('\u0000attachment-store-mutation', action);
}

final class _AttachmentRecord {
  const _AttachmentRecord({required this.directory, required this.manifest});

  final Directory directory;
  final _AttachmentManifest manifest;
}

final class _AttachmentManifest {
  static const version = 2;

  const _AttachmentManifest({
    required this.senderUsername,
    required this.messageId,
    required this.attachmentId,
    required this.chunkCount,
    required this.chunks,
    required this.createdAt,
    required this.updatedAt,
    this.sourceVersion = version,
  });

  final String senderUsername;
  final String messageId;
  final String attachmentId;
  final int chunkCount;
  final Map<int, _StoredChunk> chunks;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int sourceVersion;

  bool get needsRewrite => sourceVersion != version;

  int get storedBytes =>
      chunks.values.fold(0, (sum, chunk) => sum + chunk.bytes);

  bool matchesChunk(EncryptedAttachmentChunk chunk) => matches(
    senderUsername: chunk.senderUsername,
    messageId: chunk.messageId,
    attachmentId: chunk.attachmentId,
    chunkCount: chunk.chunkCount,
  );

  bool matches({
    required String senderUsername,
    required String messageId,
    required String attachmentId,
    required int chunkCount,
  }) =>
      matchesIdentity(
        senderUsername: senderUsername,
        messageId: messageId,
        attachmentId: attachmentId,
      ) &&
      this.chunkCount == chunkCount;

  bool matchesIdentity({
    required String senderUsername,
    required String messageId,
    required String attachmentId,
  }) =>
      this.senderUsername == senderUsername &&
      this.messageId == messageId &&
      this.attachmentId == attachmentId;

  _AttachmentManifest withChunk(
    int index,
    _StoredChunk chunk, {
    required DateTime updatedAt,
  }) => _AttachmentManifest(
    senderUsername: senderUsername,
    messageId: messageId,
    attachmentId: attachmentId,
    chunkCount: chunkCount,
    chunks: Map<int, _StoredChunk>.unmodifiable({...chunks, index: chunk}),
    createdAt: createdAt,
    updatedAt: updatedAt.toUtc(),
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    'sender_username': senderUsername,
    'message_id': messageId,
    'attachment_id': attachmentId,
    'chunk_count': chunkCount,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'chunks': {
      for (final entry in chunks.entries) '${entry.key}': entry.value.toJson(),
    },
  };

  factory _AttachmentManifest.fromJson(
    Map<String, dynamic> value, {
    required DateTime legacyTimestamp,
  }) {
    final sourceVersion = value['version'];
    if ((sourceVersion != 1 && sourceVersion != version) ||
        value['chunks'] is! Map) {
      throw const FormatException('Attachment manifest is invalid.');
    }
    final senderUsername = value['sender_username'];
    final messageId = value['message_id'];
    final attachmentId = value['attachment_id'];
    final chunkCount = value['chunk_count'];
    if (senderUsername is! String ||
        messageId is! String ||
        attachmentId is! String ||
        chunkCount is! int) {
      throw const FormatException('Attachment manifest fields are invalid.');
    }
    _validateLookup(senderUsername, messageId, attachmentId, chunkCount);
    final createdAt = sourceVersion == 1
        ? legacyTimestamp.toUtc()
        : _manifestTimestamp(value['created_at']);
    final updatedAt = sourceVersion == 1
        ? legacyTimestamp.toUtc()
        : _manifestTimestamp(value['updated_at']);
    if (updatedAt.isBefore(createdAt)) {
      throw const FormatException(
        'Attachment manifest timestamps are invalid.',
      );
    }
    final chunks = <int, _StoredChunk>{};
    for (final entry in (value['chunks'] as Map).entries) {
      final index = int.tryParse('${entry.key}');
      if (index == null ||
          index < 0 ||
          index >= chunkCount ||
          entry.value is! Map ||
          chunks.containsKey(index)) {
        throw const FormatException('Attachment manifest chunks are invalid.');
      }
      chunks[index] = _StoredChunk.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
    return _AttachmentManifest(
      senderUsername: senderUsername,
      messageId: messageId,
      attachmentId: attachmentId,
      chunkCount: chunkCount,
      chunks: Map<int, _StoredChunk>.unmodifiable(chunks),
      createdAt: createdAt,
      updatedAt: updatedAt,
      sourceVersion: sourceVersion as int,
    );
  }
}

DateTime _manifestTimestamp(Object? value) {
  if (value is! String) {
    throw const FormatException('Attachment manifest timestamp is invalid.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('Attachment manifest timestamp is invalid.');
  }
  return parsed.toUtc();
}

final class _StoredChunk {
  const _StoredChunk({required this.bytes, required this.sha256Digest});

  final int bytes;
  final String sha256Digest;

  Map<String, dynamic> toJson() => {'bytes': bytes, 'sha256': sha256Digest};

  factory _StoredChunk.fromJson(Map<String, dynamic> value) {
    final bytes = value['bytes'];
    final digest = value['sha256'];
    if (bytes is! int ||
        bytes < WampAppAttachmentLimits.secretBoxOverheadBytes ||
        bytes > WampAppAttachmentLimits.maxEncryptedChunkBytes ||
        digest is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException('Stored attachment chunk is invalid.');
    }
    return _StoredChunk(bytes: bytes, sha256Digest: digest);
  }
}

void _validateLookup(
  String senderUsername,
  String messageId,
  String attachmentId,
  int chunkCount,
) {
  if (!RegExp(r'^[a-z0-9][a-z0-9_.-]{2,63}$').hasMatch(senderUsername) ||
      !RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(messageId) ||
      !RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(attachmentId) ||
      chunkCount <= 0 ||
      chunkCount > WampAppAttachmentLimits.maxChunkCount) {
    throw const FormatException('Attachment lookup is invalid.');
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
