import 'dart:convert';
import 'dart:typed_data';

import 'account_registration.dart';

enum ChatAttachmentKind { file, image, gif, sticker, voiceNote }

abstract final class WampAppAttachmentLimits {
  static const maxAttachmentsPerMessage = 8;
  static const maxAttachmentBytes = 64 * 1024 * 1024;
  static const defaultChunkBytes = 1024 * 1024;
  static const maxChunkBytes = defaultChunkBytes;
  static const maxChunkCount = 64;
  static const aesGcmOverheadBytes = 28;
  static const secretBoxOverheadBytes = 40;
  static const minEncryptedChunkBytes = aesGcmOverheadBytes;
  static const maxEncryptedChunkBytes = maxChunkBytes + secretBoxOverheadBytes;
}

/// Private attachment metadata carried inside an encrypted chat payload.
final class EncryptedAttachmentDescriptor {
  EncryptedAttachmentDescriptor({
    this.version = currentVersion,
    this.algorithm = currentAlgorithm,
    required this.attachmentId,
    required this.kind,
    required this.name,
    required this.contentType,
    required this.plaintextBytes,
    required this.chunkBytes,
    required this.chunkCount,
    required this.plaintextSha256,
    required Uint8List key,
  }) : _key = Uint8List.fromList(key) {
    validate();
  }

  static const legacyVersion = 'wampapp-attachment-v1';
  static const legacyAlgorithm = 'xsalsa20poly1305-chunked';
  static const currentVersion = 'wampapp-attachment-v2';
  static const currentAlgorithm = 'aes256gcm-chunked';

  final String version;
  final String algorithm;
  final String attachmentId;
  final ChatAttachmentKind kind;
  final String name;
  final String contentType;
  final int plaintextBytes;
  final int chunkBytes;
  final int chunkCount;
  final String plaintextSha256;
  final Uint8List _key;

  Uint8List get key => Uint8List.fromList(_key);

  void validate() {
    final supported =
        (version == legacyVersion && algorithm == legacyAlgorithm) ||
        (version == currentVersion && algorithm == currentAlgorithm);
    if (!supported) {
      throw const FormatException('Unsupported attachment descriptor.');
    }
    _validateOpaqueId(attachmentId, 'attachment_id');
    if (name.isEmpty ||
        name.length > 255 ||
        name.trim() != name ||
        RegExp(r'[\u0000-\u001f\u007f]').hasMatch(name)) {
      throw const FormatException('Attachment name is invalid.');
    }
    if (contentType.isEmpty ||
        contentType.length > 255 ||
        contentType.trim() != contentType ||
        RegExp(r'[\u0000-\u001f\u007f]').hasMatch(contentType)) {
      throw const FormatException('Attachment content type is invalid.');
    }
    if (plaintextBytes < 0 ||
        plaintextBytes > WampAppAttachmentLimits.maxAttachmentBytes) {
      throw const FormatException('Attachment size is outside the limit.');
    }
    if (chunkBytes <= 0 || chunkBytes > WampAppAttachmentLimits.maxChunkBytes) {
      throw const FormatException(
        'Attachment chunk size is outside the limit.',
      );
    }
    final expectedChunks = plaintextBytes == 0
        ? 1
        : (plaintextBytes + chunkBytes - 1) ~/ chunkBytes;
    if (chunkCount != expectedChunks ||
        chunkCount > WampAppAttachmentLimits.maxChunkCount) {
      throw const FormatException('Attachment chunk count is invalid.');
    }
    _validateSha256(plaintextSha256, 'plaintext_sha256');
    if (_key.length != 32) {
      throw const FormatException('Attachment key is invalid.');
    }
  }

  Map<String, dynamic> toJson() {
    validate();
    return {
      'version': version,
      'algorithm': algorithm,
      'attachment_id': attachmentId,
      'kind': kind.name,
      'name': name,
      'content_type': contentType,
      'plaintext_bytes': plaintextBytes,
      'chunk_bytes': chunkBytes,
      'chunk_count': chunkCount,
      'plaintext_sha256': plaintextSha256.toLowerCase(),
      'key': base64Url.encode(_key),
    };
  }

  factory EncryptedAttachmentDescriptor.fromJson(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Unsupported attachment descriptor.');
    }
    final kindName = _readString(value['kind'], 'kind');
    final kind = ChatAttachmentKind.values
        .where((candidate) => candidate.name == kindName)
        .firstOrNull;
    if (kind == null) {
      throw const FormatException('Attachment kind is invalid.');
    }
    return EncryptedAttachmentDescriptor(
      version: _readString(value['version'], 'version'),
      algorithm: _readString(value['algorithm'], 'algorithm'),
      attachmentId: _readString(value['attachment_id'], 'attachment_id'),
      kind: kind,
      name: _readString(value['name'], 'name'),
      contentType: _readString(value['content_type'], 'content_type'),
      plaintextBytes: _readInt(value['plaintext_bytes'], 'plaintext_bytes'),
      chunkBytes: _readInt(value['chunk_bytes'], 'chunk_bytes'),
      chunkCount: _readInt(value['chunk_count'], 'chunk_count'),
      plaintextSha256: _readString(
        value['plaintext_sha256'],
        'plaintext_sha256',
      ),
      key: _decodeBase64Url(_readString(value['key'], 'key'), 'key'),
    );
  }
}

/// One independently retryable opaque ciphertext chunk.
final class EncryptedAttachmentChunk {
  EncryptedAttachmentChunk({
    required String senderUsername,
    required this.messageId,
    required this.attachmentId,
    required this.chunkIndex,
    required this.chunkCount,
    required this.ciphertextSha256,
    required Uint8List encryptedBytes,
  }) : senderUsername = AccountRegistration.normalizeUsername(senderUsername),
       _encryptedBytes = Uint8List.fromList(encryptedBytes) {
    validate();
  }

  static const version = 'wampapp-attachment-chunk-v1';

  final String senderUsername;
  final String messageId;
  final String attachmentId;
  final int chunkIndex;
  final int chunkCount;
  final String ciphertextSha256;
  final Uint8List _encryptedBytes;

  Uint8List get encryptedBytes => Uint8List.fromList(_encryptedBytes);

  void validate() {
    if (!RegExp(r'^[a-z0-9][a-z0-9_.-]{2,63}$').hasMatch(senderUsername)) {
      throw const FormatException('Attachment sender is invalid.');
    }
    _validateOpaqueId(messageId, 'message_id');
    _validateOpaqueId(attachmentId, 'attachment_id');
    if (chunkCount <= 0 ||
        chunkCount > WampAppAttachmentLimits.maxChunkCount ||
        chunkIndex < 0 ||
        chunkIndex >= chunkCount) {
      throw const FormatException('Attachment chunk position is invalid.');
    }
    if (_encryptedBytes.length <
            WampAppAttachmentLimits.minEncryptedChunkBytes ||
        _encryptedBytes.length >
            WampAppAttachmentLimits.maxEncryptedChunkBytes) {
      throw const FormatException('Encrypted attachment chunk is invalid.');
    }
    _validateSha256(ciphertextSha256, 'ciphertext_sha256');
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'version': version,
      'sender_username': senderUsername,
      'message_id': messageId,
      'attachment_id': attachmentId,
      'chunk_index': chunkIndex,
      'chunk_count': chunkCount,
      'ciphertext_sha256': ciphertextSha256.toLowerCase(),
      'encrypted_bytes': encryptedBytes,
    };
  }

  factory EncryptedAttachmentChunk.fromWampKeywords(
    Map<String, dynamic>? value,
  ) {
    if (value == null || value['version'] != version) {
      throw const FormatException('Unsupported attachment chunk.');
    }
    return EncryptedAttachmentChunk(
      senderUsername: _readString(value['sender_username'], 'sender_username'),
      messageId: _readString(value['message_id'], 'message_id'),
      attachmentId: _readString(value['attachment_id'], 'attachment_id'),
      chunkIndex: _readInt(value['chunk_index'], 'chunk_index'),
      chunkCount: _readInt(value['chunk_count'], 'chunk_count'),
      ciphertextSha256: _readString(
        value['ciphertext_sha256'],
        'ciphertext_sha256',
      ),
      encryptedBytes: _readBinary(value['encrypted_bytes'], 'encrypted_bytes'),
    );
  }
}

final class AttachmentChunkReceipt {
  AttachmentChunkReceipt({
    required this.messageId,
    required this.attachmentId,
    required this.chunkIndex,
    required this.ciphertextSha256,
    required this.duplicate,
    required this.complete,
  }) {
    _validateOpaqueId(messageId, 'message_id');
    _validateOpaqueId(attachmentId, 'attachment_id');
    if (chunkIndex < 0) {
      throw const FormatException('Attachment chunk index is invalid.');
    }
    _validateSha256(ciphertextSha256, 'ciphertext_sha256');
  }

  final String messageId;
  final String attachmentId;
  final int chunkIndex;
  final String ciphertextSha256;
  final bool duplicate;
  final bool complete;

  Map<String, dynamic> toWampKeywords() => {
    'message_id': messageId,
    'attachment_id': attachmentId,
    'chunk_index': chunkIndex,
    'ciphertext_sha256': ciphertextSha256.toLowerCase(),
    'duplicate': duplicate,
    'complete': complete,
  };

  factory AttachmentChunkReceipt.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Attachment receipt is required.');
    }
    return AttachmentChunkReceipt(
      messageId: _readString(value['message_id'], 'message_id'),
      attachmentId: _readString(value['attachment_id'], 'attachment_id'),
      chunkIndex: _readInt(value['chunk_index'], 'chunk_index'),
      ciphertextSha256: _readString(
        value['ciphertext_sha256'],
        'ciphertext_sha256',
      ),
      duplicate: _readBool(value['duplicate'], 'duplicate'),
      complete: _readBool(value['complete'], 'complete'),
    );
  }
}

final class AttachmentUploadStatus {
  AttachmentUploadStatus({
    required this.messageId,
    required this.attachmentId,
    required this.chunkCount,
    required Iterable<int> receivedChunks,
  }) : receivedChunks = List<int>.unmodifiable(receivedChunks) {
    _validateOpaqueId(messageId, 'message_id');
    _validateOpaqueId(attachmentId, 'attachment_id');
    if (chunkCount <= 0 || chunkCount > WampAppAttachmentLimits.maxChunkCount) {
      throw const FormatException('Attachment chunk count is invalid.');
    }
    for (var index = 0; index < this.receivedChunks.length; index += 1) {
      final chunk = this.receivedChunks[index];
      if (chunk < 0 ||
          chunk >= chunkCount ||
          (index > 0 && this.receivedChunks[index - 1] >= chunk)) {
        throw const FormatException(
          'Received attachment chunks must be sorted and unique.',
        );
      }
    }
  }

  final String messageId;
  final String attachmentId;
  final int chunkCount;
  final List<int> receivedChunks;

  bool get complete => receivedChunks.length == chunkCount;

  Map<String, dynamic> toWampKeywords() => {
    'message_id': messageId,
    'attachment_id': attachmentId,
    'chunk_count': chunkCount,
    'received_chunks': receivedChunks,
    'complete': complete,
  };

  factory AttachmentUploadStatus.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null || value['received_chunks'] is! List) {
      throw const FormatException('Attachment upload status is invalid.');
    }
    final status = AttachmentUploadStatus(
      messageId: _readString(value['message_id'], 'message_id'),
      attachmentId: _readString(value['attachment_id'], 'attachment_id'),
      chunkCount: _readInt(value['chunk_count'], 'chunk_count'),
      receivedChunks: (value['received_chunks'] as List).map(
        (item) => _readInt(item, 'received_chunks'),
      ),
    );
    if (_readBool(value['complete'], 'complete') != status.complete) {
      throw const FormatException('Attachment completion state is invalid.');
    }
    return status;
  }
}

void _validateOpaqueId(String value, String field) {
  if (!RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(value)) {
    throw FormatException('$field is invalid.');
  }
}

void _validateSha256(String value, String field) {
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
    throw FormatException('$field is invalid.');
  }
}

String _readString(Object? value, String field) {
  if (value is! String) throw FormatException('$field must be a string.');
  return value;
}

int _readInt(Object? value, String field) {
  if (value is! int) throw FormatException('$field must be an integer.');
  return value;
}

bool _readBool(Object? value, String field) {
  if (value is! bool) throw FormatException('$field must be a boolean.');
  return value;
}

Uint8List _readBinary(Object? value, String field) {
  if (value is Uint8List) return Uint8List.fromList(value);
  if (value is List<int>) return Uint8List.fromList(value);
  throw FormatException('$field must be binary.');
}

Uint8List _decodeBase64Url(String value, String field) {
  try {
    return base64Url.decode(value);
  } on FormatException {
    throw FormatException('$field must be base64url data.');
  }
}
