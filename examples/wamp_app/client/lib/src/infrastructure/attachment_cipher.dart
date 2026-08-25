import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/x25519.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'attachment_chunk_cache.dart';

final class AttachmentPlaintextSource {
  AttachmentPlaintextSource({
    required this.name,
    required this.contentType,
    required this.kind,
    required this.byteCount,
    required this.openRead,
  }) {
    if (byteCount < 0 ||
        byteCount > WampAppAttachmentLimits.maxAttachmentBytes) {
      throw const FormatException('Attachment size is outside the limit.');
    }
  }

  final String name;
  final String contentType;
  final ChatAttachmentKind kind;
  final int byteCount;
  final Stream<List<int>> Function() openRead;
}

final class AttachmentTransferCancelled implements Exception {
  const AttachmentTransferCancelled();

  @override
  String toString() => 'Encrypted attachment transfer was cancelled.';
}

final class AttachmentCipher {
  AttachmentCipher({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  Future<List<EncryptedAttachmentDescriptor>> encryptSources({
    required String scope,
    required String senderUsername,
    required String messageId,
    required List<AttachmentPlaintextSource> sources,
    required AttachmentChunkCache cache,
    bool Function()? isCancelled,
  }) async {
    if (sources.isEmpty ||
        sources.length > WampAppAttachmentLimits.maxAttachmentsPerMessage) {
      throw const FormatException('Attachment count is outside the limit.');
    }
    final attachments = <EncryptedAttachmentDescriptor>[];
    try {
      for (final source in sources) {
        _throwIfCancelled(isCancelled);
        attachments.add(
          await _encryptSource(
            scope: scope,
            senderUsername: senderUsername,
            messageId: messageId,
            source: source,
            cache: cache,
            isCancelled: isCancelled,
          ),
        );
      }
      attachments.sort(
        (left, right) => left.attachmentId.compareTo(right.attachmentId),
      );
      return List<EncryptedAttachmentDescriptor>.unmodifiable(attachments);
    } catch (_) {
      await cache.removeMessage(scope: scope, messageId: messageId);
      rethrow;
    }
  }

  Future<Uint8List> decryptToBytes({
    required String scope,
    required String senderUsername,
    required String messageId,
    required EncryptedAttachmentDescriptor attachment,
    required AttachmentChunkCache cache,
    Future<EncryptedAttachmentChunk> Function(int chunkIndex)? fetchChunk,
    bool Function()? isCancelled,
  }) async {
    final chunks = <Uint8List>[];
    try {
      await decryptToSink(
        scope: scope,
        senderUsername: senderUsername,
        messageId: messageId,
        attachment: attachment,
        cache: cache,
        fetchChunk: fetchChunk,
        isCancelled: isCancelled,
        write: (bytes) => chunks.add(Uint8List.fromList(bytes)),
      );
      final output = Uint8List(attachment.plaintextBytes);
      var offset = 0;
      for (final chunk in chunks) {
        output.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      return output;
    } finally {
      for (final chunk in chunks) {
        chunk.fillRange(0, chunk.length, 0);
      }
      chunks.clear();
    }
  }

  Future<void> decryptToSink({
    required String scope,
    required String senderUsername,
    required String messageId,
    required EncryptedAttachmentDescriptor attachment,
    required AttachmentChunkCache cache,
    required FutureOr<void> Function(Uint8List bytes) write,
    Future<EncryptedAttachmentChunk> Function(int chunkIndex)? fetchChunk,
    bool Function()? isCancelled,
  }) async {
    attachment.validate();
    final digest = _Sha256Digest();
    var plaintextBytes = 0;
    try {
      for (
        var chunkIndex = 0;
        chunkIndex < attachment.chunkCount;
        chunkIndex++
      ) {
        _throwIfCancelled(isCancelled);
        var chunk = await cache.get(
          scope: scope,
          senderUsername: senderUsername,
          messageId: messageId,
          attachmentId: attachment.attachmentId,
          chunkIndex: chunkIndex,
          chunkCount: attachment.chunkCount,
        );
        _throwIfCancelled(isCancelled);
        if (chunk == null) {
          final fetch = fetchChunk;
          if (fetch == null) {
            throw StateError('Encrypted attachment chunk is unavailable.');
          }
          chunk = await fetch(chunkIndex);
          _throwIfCancelled(isCancelled);
          _validateChunk(
            chunk: chunk,
            senderUsername: senderUsername,
            messageId: messageId,
            attachment: attachment,
            chunkIndex: chunkIndex,
          );
          await cache.put(scope: scope, chunk: chunk);
          _throwIfCancelled(isCancelled);
        }
        _validateChunk(
          chunk: chunk,
          senderUsername: senderUsername,
          messageId: messageId,
          attachment: attachment,
          chunkIndex: chunkIndex,
        );

        final encrypted = chunk.encryptedBytes;
        if (attachmentCacheDigest(encrypted) != chunk.ciphertextSha256) {
          throw const FormatException(
            'Encrypted attachment chunk digest does not match.',
          );
        }
        final attachmentKey = attachment.key;
        final chunkKey = _chunkKey(
          attachmentKey,
          messageId: messageId,
          attachmentId: attachment.attachmentId,
          chunkIndex: chunkIndex,
          chunkCount: attachment.chunkCount,
        );
        attachmentKey.fillRange(0, attachmentKey.length, 0);
        Uint8List? plaintext;
        try {
          plaintext = SecretBox(chunkKey).decrypt(
            EncryptedMessage(
              nonce: Uint8List.sublistView(
                encrypted,
                0,
                EncryptedMessage.nonceLength,
              ),
              cipherText: Uint8List.sublistView(
                encrypted,
                EncryptedMessage.nonceLength,
              ),
            ),
          );
          final expectedBytes = _expectedPlaintextBytes(attachment, chunkIndex);
          if (plaintext.length != expectedBytes) {
            throw const FormatException(
              'Decrypted attachment chunk length does not match.',
            );
          }
          digest.add(plaintext);
          plaintextBytes += plaintext.length;
          await write(plaintext);
          _throwIfCancelled(isCancelled);
        } catch (error) {
          if (error is FormatException) rethrow;
          throw const FormatException(
            'Encrypted attachment chunk could not be opened.',
          );
        } finally {
          chunkKey.fillRange(0, chunkKey.length, 0);
          plaintext?.fillRange(0, plaintext.length, 0);
        }
      }
      if (plaintextBytes != attachment.plaintextBytes ||
          digest.finish() != attachment.plaintextSha256) {
        throw const FormatException(
          'Attachment plaintext digest does not match.',
        );
      }
    } finally {
      digest.close();
    }
  }

  Future<EncryptedAttachmentDescriptor> _encryptSource({
    required String scope,
    required String senderUsername,
    required String messageId,
    required AttachmentPlaintextSource source,
    required AttachmentChunkCache cache,
    required bool Function()? isCancelled,
  }) async {
    final attachmentId = _token(16);
    final key = _bytes(32);
    final chunkBytes = WampAppAttachmentLimits.defaultChunkBytes;
    final chunkCount = source.byteCount == 0
        ? 1
        : (source.byteCount + chunkBytes - 1) ~/ chunkBytes;
    final digest = _Sha256Digest();
    final pending = BytesBuilder(copy: true);
    var readBytes = 0;
    var chunkIndex = 0;

    Future<void> encryptPending() async {
      final plaintext = pending.takeBytes();
      final chunkKey = _chunkKey(
        key,
        messageId: messageId,
        attachmentId: attachmentId,
        chunkIndex: chunkIndex,
        chunkCount: chunkCount,
      );
      try {
        final encrypted = SecretBox(chunkKey).encrypt(plaintext).asTypedList;
        final chunk = EncryptedAttachmentChunk(
          senderUsername: senderUsername,
          messageId: messageId,
          attachmentId: attachmentId,
          chunkIndex: chunkIndex,
          chunkCount: chunkCount,
          ciphertextSha256: attachmentCacheDigest(encrypted),
          encryptedBytes: encrypted,
        );
        await cache.put(scope: scope, chunk: chunk);
        _throwIfCancelled(isCancelled);
        chunkIndex += 1;
      } finally {
        chunkKey.fillRange(0, chunkKey.length, 0);
        plaintext.fillRange(0, plaintext.length, 0);
      }
    }

    try {
      await for (final raw in source.openRead()) {
        _throwIfCancelled(isCancelled);
        if (raw.isEmpty) continue;
        if (readBytes + raw.length > source.byteCount) {
          throw const FormatException(
            'Attachment stream exceeds its declared size.',
          );
        }
        digest.add(raw);
        readBytes += raw.length;
        var offset = 0;
        while (offset < raw.length) {
          final available = chunkBytes - pending.length;
          final take = min(available, raw.length - offset);
          pending.add(raw.sublist(offset, offset + take));
          offset += take;
          if (pending.length == chunkBytes) await encryptPending();
        }
      }
      if (readBytes != source.byteCount) {
        throw const FormatException(
          'Attachment stream does not match its declared size.',
        );
      }
      if (pending.isNotEmpty || source.byteCount == 0) await encryptPending();
      if (chunkIndex != chunkCount) {
        throw const FormatException('Attachment chunk count does not match.');
      }
      _throwIfCancelled(isCancelled);
      return EncryptedAttachmentDescriptor(
        attachmentId: attachmentId,
        kind: source.kind,
        name: source.name,
        contentType: source.contentType,
        plaintextBytes: source.byteCount,
        chunkBytes: chunkBytes,
        chunkCount: chunkCount,
        plaintextSha256: digest.finish(),
        key: key,
      );
    } finally {
      digest.close();
      key.fillRange(0, key.length, 0);
      final remaining = pending.takeBytes();
      remaining.fillRange(0, remaining.length, 0);
    }
  }

  void _validateChunk({
    required EncryptedAttachmentChunk chunk,
    required String senderUsername,
    required String messageId,
    required EncryptedAttachmentDescriptor attachment,
    required int chunkIndex,
  }) {
    chunk.validate();
    if (chunk.senderUsername != senderUsername.toLowerCase() ||
        chunk.messageId != messageId ||
        chunk.attachmentId != attachment.attachmentId ||
        chunk.chunkIndex != chunkIndex ||
        chunk.chunkCount != attachment.chunkCount) {
      throw const FormatException(
        'Encrypted attachment chunk metadata conflicts.',
      );
    }
  }

  Uint8List _chunkKey(
    Uint8List attachmentKey, {
    required String messageId,
    required String attachmentId,
    required int chunkIndex,
    required int chunkCount,
  }) => Uint8List.fromList(
    Hmac(sha256, attachmentKey)
        .convert(
          utf8.encode(
            '${EncryptedAttachmentChunk.version}\n$messageId\n$attachmentId\n'
            '$chunkIndex\n$chunkCount',
          ),
        )
        .bytes,
  );

  int _expectedPlaintextBytes(
    EncryptedAttachmentDescriptor attachment,
    int chunkIndex,
  ) {
    if (attachment.plaintextBytes == 0) return 0;
    if (chunkIndex < attachment.chunkCount - 1) return attachment.chunkBytes;
    return attachment.plaintextBytes -
        (attachment.chunkBytes * (attachment.chunkCount - 1));
  }

  void _throwIfCancelled(bool Function()? isCancelled) {
    if (isCancelled?.call() ?? false) {
      throw const AttachmentTransferCancelled();
    }
  }

  String _token(int length) =>
      base64Url.encode(_bytes(length)).replaceAll('=', '');

  Uint8List _bytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );
}

final class _Sha256Digest {
  _Sha256Digest() {
    _input = sha256.startChunkedConversion(
      ChunkedConversionSink<Digest>.withCallback((digests) {
        _digest = digests.single;
      }),
    );
  }

  late final ByteConversionSink _input;
  Digest? _digest;
  bool _closed = false;

  void add(List<int> bytes) {
    if (_closed) throw StateError('Attachment digest is already finalized.');
    _input.add(bytes);
  }

  String finish() {
    close();
    return _digest!.toString();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _input.close();
  }
}
