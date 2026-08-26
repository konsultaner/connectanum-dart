import 'dart:typed_data';

abstract final class WampAppBackupTransferLimits {
  static const maximumArchiveBytes = 12 * 1024 * 1024;
  static const chunkBytes = 128 * 1024;
  static const maximumChunkCount = maximumArchiveBytes ~/ chunkBytes;
}

final class BackupUploadRequest {
  BackupUploadRequest({
    required this.expectedRevision,
    required this.byteCount,
    required this.chunkCount,
    required String sha256,
  }) : sha256 = sha256.toLowerCase() {
    validate();
  }

  final int expectedRevision;
  final int byteCount;
  final int chunkCount;
  final String sha256;

  void validate() {
    if (expectedRevision < 0) {
      throw const FormatException('Backup revision is invalid.');
    }
    if (byteCount <= 0 ||
        byteCount > WampAppBackupTransferLimits.maximumArchiveBytes) {
      throw const FormatException('Backup size is invalid.');
    }
    final expectedChunks =
        (byteCount + WampAppBackupTransferLimits.chunkBytes - 1) ~/
        WampAppBackupTransferLimits.chunkBytes;
    if (chunkCount != expectedChunks ||
        chunkCount > WampAppBackupTransferLimits.maximumChunkCount) {
      throw const FormatException('Backup chunk count is invalid.');
    }
    _validateSha256(sha256);
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'expected_revision': expectedRevision,
      'byte_count': byteCount,
      'chunk_count': chunkCount,
      'sha256': sha256,
    };
  }

  factory BackupUploadRequest.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Backup upload details are required.');
    }
    return BackupUploadRequest(
      expectedRevision: _readInt(
        value['expected_revision'],
        'expected_revision',
      ),
      byteCount: _readInt(value['byte_count'], 'byte_count'),
      chunkCount: _readInt(value['chunk_count'], 'chunk_count'),
      sha256: _readString(value['sha256'], 'sha256'),
    );
  }
}

final class BackupUploadSession {
  BackupUploadSession({
    required this.uploadId,
    required this.expectedRevision,
  }) {
    _validateOpaqueId(uploadId, 'upload_id');
    if (expectedRevision < 0) {
      throw const FormatException('Backup revision is invalid.');
    }
  }

  final String uploadId;
  final int expectedRevision;

  Map<String, dynamic> toWampKeywords() => {
    'upload_id': uploadId,
    'expected_revision': expectedRevision,
    'chunk_bytes': WampAppBackupTransferLimits.chunkBytes,
  };

  factory BackupUploadSession.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null ||
        _readInt(value['chunk_bytes'], 'chunk_bytes') !=
            WampAppBackupTransferLimits.chunkBytes) {
      throw const FormatException('Backup upload session is invalid.');
    }
    return BackupUploadSession(
      uploadId: _readString(value['upload_id'], 'upload_id'),
      expectedRevision: _readInt(
        value['expected_revision'],
        'expected_revision',
      ),
    );
  }
}

final class EncryptedBackupChunk {
  EncryptedBackupChunk({
    required this.uploadId,
    required this.chunkIndex,
    required Uint8List bytes,
  }) : _bytes = Uint8List.fromList(bytes) {
    _validateOpaqueId(uploadId, 'upload_id');
    if (chunkIndex < 0 ||
        chunkIndex >= WampAppBackupTransferLimits.maximumChunkCount) {
      throw const FormatException('Backup chunk index is invalid.');
    }
    if (_bytes.isEmpty ||
        _bytes.length > WampAppBackupTransferLimits.chunkBytes) {
      throw const FormatException('Backup chunk size is invalid.');
    }
  }

  final String uploadId;
  final int chunkIndex;
  final Uint8List _bytes;

  Uint8List get bytes => Uint8List.fromList(_bytes);

  Map<String, dynamic> toWampKeywords() => {
    'upload_id': uploadId,
    'chunk_index': chunkIndex,
    'bytes': bytes,
  };

  factory EncryptedBackupChunk.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Backup chunk is required.');
    }
    return EncryptedBackupChunk(
      uploadId: _readString(value['upload_id'], 'upload_id'),
      chunkIndex: _readInt(value['chunk_index'], 'chunk_index'),
      bytes: _readBinary(value['bytes'], 'bytes'),
    );
  }
}

final class BackupMetadata {
  BackupMetadata({
    required this.revision,
    required this.byteCount,
    required this.chunkCount,
    required String sha256,
    required DateTime updatedAt,
  }) : sha256 = sha256.toLowerCase(),
       updatedAt = updatedAt.toUtc() {
    BackupUploadRequest(
      expectedRevision: revision - 1,
      byteCount: byteCount,
      chunkCount: chunkCount,
      sha256: this.sha256,
    );
    if (revision <= 0) {
      throw const FormatException('Backup revision is invalid.');
    }
  }

  final int revision;
  final int byteCount;
  final int chunkCount;
  final String sha256;
  final DateTime updatedAt;

  Map<String, dynamic> toWampKeywords() => {
    'revision': revision,
    'byte_count': byteCount,
    'chunk_count': chunkCount,
    'sha256': sha256,
    'updated_at': updatedAt.toIso8601String(),
  };

  factory BackupMetadata.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Backup metadata is required.');
    }
    return BackupMetadata(
      revision: _readInt(value['revision'], 'revision'),
      byteCount: _readInt(value['byte_count'], 'byte_count'),
      chunkCount: _readInt(value['chunk_count'], 'chunk_count'),
      sha256: _readString(value['sha256'], 'sha256'),
      updatedAt: _readDate(value['updated_at'], 'updated_at'),
    );
  }
}

final class EncryptedBackupDownloadChunk {
  EncryptedBackupDownloadChunk({
    required this.revision,
    required this.chunkIndex,
    required Uint8List bytes,
  }) : _bytes = Uint8List.fromList(bytes) {
    if (revision <= 0) {
      throw const FormatException('Backup revision is invalid.');
    }
    if (chunkIndex < 0 ||
        chunkIndex >= WampAppBackupTransferLimits.maximumChunkCount) {
      throw const FormatException('Backup chunk index is invalid.');
    }
    if (_bytes.isEmpty ||
        _bytes.length > WampAppBackupTransferLimits.chunkBytes) {
      throw const FormatException('Backup chunk size is invalid.');
    }
  }

  final int revision;
  final int chunkIndex;
  final Uint8List _bytes;

  Uint8List get bytes => Uint8List.fromList(_bytes);

  Map<String, dynamic> toWampKeywords() => {
    'revision': revision,
    'chunk_index': chunkIndex,
    'bytes': bytes,
  };

  factory EncryptedBackupDownloadChunk.fromWampKeywords(
    Map<String, dynamic>? value,
  ) {
    if (value == null) {
      throw const FormatException('Backup download chunk is required.');
    }
    return EncryptedBackupDownloadChunk(
      revision: _readInt(value['revision'], 'revision'),
      chunkIndex: _readInt(value['chunk_index'], 'chunk_index'),
      bytes: _readBinary(value['bytes'], 'bytes'),
    );
  }
}

void _validateOpaqueId(String value, String field) {
  if (!RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(value)) {
    throw FormatException('$field is invalid.');
  }
}

void _validateSha256(String value) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const FormatException('Backup SHA-256 is invalid.');
  }
}

String _readString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

int _readInt(Object? value, String field) {
  if (value is! int) throw FormatException('$field must be an integer.');
  return value;
}

Uint8List _readBinary(Object? value, String field) {
  if (value is Uint8List) return Uint8List.fromList(value);
  if (value is List<int>) return Uint8List.fromList(value);
  throw FormatException('$field must be binary data.');
}

DateTime _readDate(Object? value, String field) {
  if (value is! String) {
    throw FormatException('$field must be an ISO-8601 string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$field must be a UTC ISO-8601 string.');
  }
  return parsed;
}
