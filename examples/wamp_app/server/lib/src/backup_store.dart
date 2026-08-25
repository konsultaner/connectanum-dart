import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class BackupConflict implements Exception {
  const BackupConflict(this.currentRevision);

  final int currentRevision;
}

final class BackupNotFound implements Exception {
  const BackupNotFound();
}

final class BackupUploadNotFound implements Exception {
  const BackupUploadNotFound();
}

final class BackupIncomplete implements Exception {
  const BackupIncomplete();
}

final class BackupQuotaExceeded implements Exception {
  const BackupQuotaExceeded();
}

final class BackupUnavailable implements Exception {
  const BackupUnavailable();
}

/// Stores one revisioned opaque encrypted archive for each authenticated user.
final class BackupStore {
  static const defaultMaximumTotalBytes = 10 * 1024 * 1024 * 1024;

  BackupStore(
    String path, {
    this.maximumConcurrentUploads = 64,
    this.maximumTotalBytes = defaultMaximumTotalBytes,
    this.uploadTtl = const Duration(minutes: 15),
    DateTime Function()? clock,
  }) : directory = Directory(path),
       _clock = clock ?? DateTime.now {
    if (maximumConcurrentUploads <= 0 ||
        maximumTotalBytes <= 0 ||
        uploadTtl <= Duration.zero) {
      throw ArgumentError('Backup upload limits are invalid.');
    }
  }

  final Directory directory;
  final int maximumConcurrentUploads;
  final int maximumTotalBytes;
  final Duration uploadTtl;
  final DateTime Function() _clock;
  final Random _random = Random.secure();
  final Map<String, _BackupUploadState> _uploads = {};
  Future<void> _writeTail = Future<void>.value();
  var _committedBytes = 0;
  var _initialized = false;

  Future<void> initialize() => _serialize(() async {
    _initialized = false;
    _uploads.clear();
    _committedBytes = 0;
    await directory.create(recursive: true);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! Directory) {
        await entity.delete(recursive: true);
        continue;
      }
      _committedBytes += await _reconcileAccountDirectory(entity);
      if (_committedBytes > maximumTotalBytes) {
        throw const BackupQuotaExceeded();
      }
    }
    _initialized = true;
  });

  Future<BackupUploadSession> begin(
    String username,
    BackupUploadRequest request,
  ) {
    request.validate();
    _ensureInitialized();
    final normalized = AccountRegistration.normalizeUsername(username);
    return _serialize(() async {
      await _expireUploads();
      final current = await _readManifest(normalized);
      final currentRevision = current?.metadata.revision ?? 0;
      if (request.expectedRevision != currentRevision) {
        throw BackupConflict(currentRevision);
      }
      final existing = _uploads.values
          .where((upload) => upload.username == normalized)
          .firstOrNull;
      if (existing != null) await _discardUpload(existing);
      if (_uploads.length >= maximumConcurrentUploads) {
        throw const BackupQuotaExceeded();
      }
      final stagedBytes = _uploads.values.fold<int>(
        0,
        (total, upload) => total + upload.request.byteCount,
      );
      if (_committedBytes + stagedBytes + request.byteCount >
          maximumTotalBytes) {
        throw const BackupQuotaExceeded();
      }
      final accountDirectory = _accountDirectory(normalized);
      await accountDirectory.create(recursive: true);
      final uploadId = _randomToken();
      final temporary = File(p.join(accountDirectory.path, '.$uploadId.part'));
      await temporary.writeAsBytes(const [], flush: true);
      await _restrictPermissions(temporary);
      _uploads[uploadId] = _BackupUploadState(
        uploadId: uploadId,
        username: normalized,
        request: request,
        temporary: temporary,
        createdAt: _now(),
      );
      return BackupUploadSession(
        uploadId: uploadId,
        expectedRevision: request.expectedRevision,
      );
    });
  }

  Future<void> putChunk(String username, EncryptedBackupChunk chunk) {
    _ensureInitialized();
    final normalized = AccountRegistration.normalizeUsername(username);
    return _serialize(() async {
      await _expireUploads();
      final upload = _uploads[chunk.uploadId];
      if (upload == null || upload.username != normalized) {
        throw const BackupUploadNotFound();
      }
      if (chunk.chunkIndex != upload.nextChunkIndex) {
        throw const FormatException('Backup chunks must be uploaded in order.');
      }
      final bytes = chunk.bytes;
      try {
        final remaining = upload.request.byteCount - upload.receivedBytes;
        final expectedBytes = min(
          WampAppBackupTransferLimits.chunkBytes,
          remaining,
        );
        if (bytes.length != expectedBytes) {
          throw const FormatException('Backup chunk size is invalid.');
        }
        final sink = upload.temporary.openWrite(mode: FileMode.append);
        try {
          sink.add(bytes);
          await sink.flush();
        } finally {
          await sink.close();
        }
        upload
          ..nextChunkIndex += 1
          ..receivedBytes += bytes.length;
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    });
  }

  Future<BackupMetadata> commit(String username, String uploadId) {
    _validateUploadId(uploadId);
    _ensureInitialized();
    final normalized = AccountRegistration.normalizeUsername(username);
    return _serialize(() async {
      await _expireUploads();
      final upload = _uploads[uploadId];
      if (upload == null || upload.username != normalized) {
        throw const BackupUploadNotFound();
      }
      try {
        if (upload.nextChunkIndex != upload.request.chunkCount ||
            upload.receivedBytes != upload.request.byteCount ||
            await upload.temporary.length() != upload.request.byteCount) {
          throw const BackupIncomplete();
        }
        final digest = await sha256.bind(upload.temporary.openRead()).first;
        if (digest.toString() != upload.request.sha256) {
          throw const FormatException('Backup checksum does not match.');
        }
        final current = await _readManifest(normalized);
        final currentRevision = current?.metadata.revision ?? 0;
        if (currentRevision != upload.request.expectedRevision) {
          throw BackupConflict(currentRevision);
        }
        final revision = currentRevision + 1;
        final archive = _archiveFile(normalized, revision);
        if (await archive.exists()) await archive.delete();
        await upload.temporary.rename(archive.path);
        await _restrictPermissions(archive);
        final metadata = BackupMetadata(
          revision: revision,
          byteCount: upload.request.byteCount,
          chunkCount: upload.request.chunkCount,
          sha256: upload.request.sha256,
          updatedAt: _now(),
        );
        final manifest = _BackupManifest(
          username: normalized,
          archiveName: p.basename(archive.path),
          metadata: metadata,
        );
        await _writeManifest(normalized, manifest);
        _committedBytes +=
            metadata.byteCount - (current?.metadata.byteCount ?? 0);
        if (current != null && current.archiveName != manifest.archiveName) {
          final oldArchive = File(
            p.join(_accountDirectory(normalized).path, current.archiveName),
          );
          if (await oldArchive.exists()) await oldArchive.delete();
        }
        await _deleteOrphans(normalized, keep: manifest.archiveName);
        return metadata;
      } finally {
        _uploads.remove(uploadId);
        if (await upload.temporary.exists()) await upload.temporary.delete();
      }
    });
  }

  Future<BackupMetadata> metadata(String username) {
    _ensureInitialized();
    final normalized = AccountRegistration.normalizeUsername(username);
    return _serialize(() async {
      final manifest = await _readManifest(normalized);
      if (manifest == null) throw const BackupNotFound();
      await _validateArchive(normalized, manifest, hashContents: false);
      return manifest.metadata;
    });
  }

  Future<EncryptedBackupDownloadChunk> readChunk({
    required String username,
    required int revision,
    required int chunkIndex,
  }) {
    _ensureInitialized();
    final normalized = AccountRegistration.normalizeUsername(username);
    return _serialize(() async {
      final manifest = await _readManifest(normalized);
      if (manifest == null) throw const BackupNotFound();
      if (manifest.metadata.revision != revision) {
        throw BackupConflict(manifest.metadata.revision);
      }
      if (chunkIndex < 0 || chunkIndex >= manifest.metadata.chunkCount) {
        throw const FormatException('Backup chunk index is invalid.');
      }
      final archive = await _validateArchive(
        normalized,
        manifest,
        hashContents: false,
      );
      final offset = chunkIndex * WampAppBackupTransferLimits.chunkBytes;
      final expected = min(
        WampAppBackupTransferLimits.chunkBytes,
        manifest.metadata.byteCount - offset,
      );
      final handle = await archive.open();
      try {
        await handle.setPosition(offset);
        final bytes = await handle.read(expected);
        if (bytes.length != expected) throw const BackupUnavailable();
        return EncryptedBackupDownloadChunk(
          revision: revision,
          chunkIndex: chunkIndex,
          bytes: Uint8List.fromList(bytes),
        );
      } finally {
        await handle.close();
      }
    });
  }

  Future<bool> delete(String username, int expectedRevision) {
    if (expectedRevision < 0) {
      throw const FormatException('Backup revision is invalid.');
    }
    _ensureInitialized();
    final normalized = AccountRegistration.normalizeUsername(username);
    return _serialize(() async {
      final manifest = await _readManifest(normalized);
      final currentRevision = manifest?.metadata.revision ?? 0;
      if (expectedRevision != currentRevision) {
        throw BackupConflict(currentRevision);
      }
      if (manifest == null) return false;
      final active = _uploads.values
          .where((upload) => upload.username == normalized)
          .firstOrNull;
      if (active != null) await _discardUpload(active);
      final manifestFile = _manifestFile(normalized);
      if (await manifestFile.exists()) await manifestFile.delete();
      _committedBytes -= manifest.metadata.byteCount;
      final archive = File(
        p.join(_accountDirectory(normalized).path, manifest.archiveName),
      );
      if (await archive.exists()) await archive.delete();
      await _deleteOrphans(normalized);
      final accountDirectory = _accountDirectory(normalized);
      if (await accountDirectory.exists() &&
          await accountDirectory.list().isEmpty) {
        await accountDirectory.delete();
      }
      return true;
    });
  }

  Future<int> _reconcileAccountDirectory(Directory accountDirectory) async {
    await for (final entity in accountDirectory.list(followLinks: false)) {
      if (p.basename(entity.path).startsWith('.') || entity is Directory) {
        await entity.delete(recursive: true);
      }
    }
    final manifestFile = File(p.join(accountDirectory.path, 'manifest.json'));
    if (!await manifestFile.exists()) {
      await accountDirectory.delete(recursive: true);
      return 0;
    }
    final decoded = await _decodeManifest(manifestFile);
    if (p.basename(accountDirectory.path) != _segment(decoded.username)) {
      throw const BackupUnavailable();
    }
    await _validateArchive(decoded.username, decoded, hashContents: true);
    await _deleteOrphans(decoded.username, keep: decoded.archiveName);
    return decoded.metadata.byteCount;
  }

  Future<_BackupManifest?> _readManifest(String username) async {
    final file = _manifestFile(username);
    if (!await file.exists()) return null;
    final manifest = await _decodeManifest(file);
    if (manifest.username != username) throw const BackupUnavailable();
    return manifest;
  }

  Future<_BackupManifest> _decodeManifest(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) throw const FormatException();
      return _BackupManifest.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      throw const BackupUnavailable();
    }
  }

  Future<File> _validateArchive(
    String username,
    _BackupManifest manifest, {
    required bool hashContents,
  }) async {
    final archive = File(
      p.join(_accountDirectory(username).path, manifest.archiveName),
    );
    if (!await archive.exists() ||
        await archive.length() != manifest.metadata.byteCount) {
      throw const BackupUnavailable();
    }
    if (hashContents &&
        (await sha256.bind(archive.openRead()).first).toString() !=
            manifest.metadata.sha256) {
      throw const BackupUnavailable();
    }
    return archive;
  }

  Future<void> _writeManifest(String username, _BackupManifest manifest) async {
    final file = _manifestFile(username);
    final temporary = File('${file.path}.tmp-${_random.nextInt(1 << 32)}');
    try {
      await temporary.writeAsString(jsonEncode(manifest.toJson()), flush: true);
      await _restrictPermissions(temporary);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _deleteOrphans(String username, {String? keep}) async {
    final accountDirectory = _accountDirectory(username);
    if (!await accountDirectory.exists()) return;
    final allowed = {'manifest.json', ?keep};
    await for (final entity in accountDirectory.list(followLinks: false)) {
      if (!allowed.contains(p.basename(entity.path))) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<void> _expireUploads() async {
    final cutoff = _now().subtract(uploadTtl);
    for (final upload in List<_BackupUploadState>.of(_uploads.values)) {
      if (upload.createdAt.isBefore(cutoff)) await _discardUpload(upload);
    }
  }

  Future<void> _discardUpload(_BackupUploadState upload) async {
    _uploads.remove(upload.uploadId);
    if (await upload.temporary.exists()) await upload.temporary.delete();
  }

  Directory _accountDirectory(String username) =>
      Directory(p.join(directory.path, _segment(username)));

  File _manifestFile(String username) =>
      File(p.join(_accountDirectory(username).path, 'manifest.json'));

  File _archiveFile(String username, int revision) =>
      File(p.join(_accountDirectory(username).path, 'backup-$revision.bin'));

  String _segment(String username) =>
      sha256.convert(utf8.encode(username)).toString();

  String _randomToken() => base64Url
      .encode(List<int>.generate(24, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  DateTime _now() => _clock().toUtc();

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('BackupStore.initialize must complete first.');
    }
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeTail = _writeTail.catchError((_) {}).then<void>((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

final class _BackupUploadState {
  _BackupUploadState({
    required this.uploadId,
    required this.username,
    required this.request,
    required this.temporary,
    required this.createdAt,
  });

  final String uploadId;
  final String username;
  final BackupUploadRequest request;
  final File temporary;
  final DateTime createdAt;
  int nextChunkIndex = 0;
  int receivedBytes = 0;
}

final class _BackupManifest {
  const _BackupManifest({
    required this.username,
    required this.archiveName,
    required this.metadata,
  });

  final String username;
  final String archiveName;
  final BackupMetadata metadata;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'username': username,
    'archive_name': archiveName,
    ...metadata.toWampKeywords(),
  };

  factory _BackupManifest.fromJson(Map<String, dynamic> value) {
    if (value['version'] != 1) throw const FormatException();
    final username = value['username'];
    final archiveName = value['archive_name'];
    if (username is! String || archiveName is! String) {
      throw const FormatException();
    }
    final metadata = BackupMetadata.fromWampKeywords(value);
    if (archiveName != 'backup-${metadata.revision}.bin') {
      throw const FormatException();
    }
    return _BackupManifest(
      username: AccountRegistration.normalizeUsername(username),
      archiveName: archiveName,
      metadata: metadata,
    );
  }
}

void _validateUploadId(String uploadId) {
  if (!RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(uploadId)) {
    throw const FormatException('Backup upload identifier is invalid.');
  }
}

Future<void> _restrictPermissions(File target) async {
  if (Platform.isWindows) return;
  final result = await Process.run('chmod', ['600', target.path]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'Could not restrict backup store permissions',
      target.path,
    );
  }
}
