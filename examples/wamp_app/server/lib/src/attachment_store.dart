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

/// Stores only opaque attachment ciphertext and routing-safe identifiers.
final class AttachmentStore {
  AttachmentStore(String path) : directory = Directory(path);

  final Directory directory;
  final Map<String, Future<void>> _writeTails = {};
  final Random _random = Random.secure();

  Future<void> initialize() async {
    await directory.create(recursive: true);
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File && p.basename(entity.path).contains('.tmp-')) {
        try {
          await entity.delete();
        } on FileSystemException {
          // A concurrent process may already have removed a stale temp file.
        }
      }
    }
  }

  Future<AttachmentChunkStoreResult> put(EncryptedAttachmentChunk chunk) {
    chunk.validate();
    final key = _storageKey(
      chunk.senderUsername,
      chunk.messageId,
      chunk.attachmentId,
    );
    return _serialize(key, () async {
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
      await attachmentDirectory.create(recursive: true);
      final manifestFile = File(
        p.join(attachmentDirectory.path, 'manifest.json'),
      );
      final manifest =
          await _readManifest(manifestFile) ??
          _AttachmentManifest(
            senderUsername: chunk.senderUsername,
            messageId: chunk.messageId,
            attachmentId: chunk.attachmentId,
            chunkCount: chunk.chunkCount,
            chunks: const {},
          );
      if (!manifest.matchesChunk(chunk)) {
        throw AttachmentConflict(chunk.attachmentId);
      }

      final existing = manifest.chunks[chunk.chunkIndex];
      final chunkFile = File(
        p.join(attachmentDirectory.path, _chunkName(chunk.chunkIndex)),
      );
      var duplicate = false;
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
        await _writeBytesAtomically(chunkFile, bytes);
      }

      final nextManifest = existing == null
          ? manifest.withChunk(
              chunk.chunkIndex,
              _StoredChunk(bytes: bytes.length, sha256Digest: actualDigest),
            )
          : manifest;
      if (existing == null) {
        await _writeJsonAtomically(manifestFile, nextManifest.toJson());
      }
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
    });
  }

  Future<AttachmentUploadStatus> status({
    required String senderUsername,
    required String messageId,
    required String attachmentId,
    required int chunkCount,
  }) {
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
      });
    }
  }

  Future<EncryptedAttachmentChunk> readChunk({
    required String senderUsername,
    required String messageId,
    required String attachmentId,
    required int chunkIndex,
  }) {
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

  Future<_AttachmentManifest?> _readManifest(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException();
      return _AttachmentManifest.fromJson(Map<String, dynamic>.from(decoded));
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
}

final class _AttachmentManifest {
  const _AttachmentManifest({
    required this.senderUsername,
    required this.messageId,
    required this.attachmentId,
    required this.chunkCount,
    required this.chunks,
  });

  static const version = 1;

  final String senderUsername;
  final String messageId;
  final String attachmentId;
  final int chunkCount;
  final Map<int, _StoredChunk> chunks;

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

  _AttachmentManifest withChunk(int index, _StoredChunk chunk) =>
      _AttachmentManifest(
        senderUsername: senderUsername,
        messageId: messageId,
        attachmentId: attachmentId,
        chunkCount: chunkCount,
        chunks: Map<int, _StoredChunk>.unmodifiable({...chunks, index: chunk}),
      );

  Map<String, dynamic> toJson() => {
    'version': version,
    'sender_username': senderUsername,
    'message_id': messageId,
    'attachment_id': attachmentId,
    'chunk_count': chunkCount,
    'chunks': {
      for (final entry in chunks.entries) '${entry.key}': entry.value.toJson(),
    },
  };

  factory _AttachmentManifest.fromJson(Map<String, dynamic> value) {
    if (value['version'] != version || value['chunks'] is! Map) {
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
    );
  }
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
