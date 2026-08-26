import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/x25519.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'attachment_chunk_cache.dart';
import 'attachment_crypto_worker.dart';

final class AttachmentPlaintextSource {
  AttachmentPlaintextSource({
    required this.name,
    required this.contentType,
    required this.kind,
    required this.byteCount,
    this.durationMilliseconds,
    required this.openRead,
  }) {
    if (byteCount < 0 ||
        byteCount > WampAppAttachmentLimits.maxAttachmentBytes) {
      throw const FormatException('Attachment size is outside the limit.');
    }
    if (kind == ChatAttachmentKind.voiceNote) {
      final duration = durationMilliseconds;
      if (duration == null ||
          duration <= 0 ||
          duration > WampAppAttachmentLimits.maxVoiceNoteDurationMilliseconds) {
        throw const FormatException('Voice-note duration is invalid.');
      }
    } else if (durationMilliseconds != null) {
      throw const FormatException(
        'Only voice notes may include duration metadata.',
      );
    }
  }

  final String name;
  final String contentType;
  final ChatAttachmentKind kind;
  final int byteCount;
  final int? durationMilliseconds;
  final Stream<List<int>> Function() openRead;
}

final class AttachmentTransferCancelled implements Exception {
  const AttachmentTransferCancelled();

  @override
  String toString() => 'Encrypted attachment transfer was cancelled.';
}

final class AttachmentCipher {
  AttachmentCipher({
    Random? random,
    AttachmentCryptoWorker? cryptoWorker,
    this.workerTimeout = const Duration(seconds: 30),
  }) : _random = random ?? Random.secure(),
       _cryptoWorker = cryptoWorker ?? AttachmentCryptoWorker();

  final Random _random;
  final AttachmentCryptoWorker _cryptoWorker;
  final Duration workerTimeout;
  bool _disposed = false;

  Future<List<EncryptedAttachmentDescriptor>> encryptSources({
    required String scope,
    required String senderUsername,
    required String messageId,
    required List<AttachmentPlaintextSource> sources,
    required AttachmentChunkCache cache,
    bool Function()? isCancelled,
  }) async {
    _throwIfDisposed();
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
    _throwIfDisposed();
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
    _throwIfDisposed();
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
          attachmentVersion: attachment.version,
          algorithm: attachment.algorithm,
          messageId: messageId,
          attachmentId: attachment.attachmentId,
          chunkIndex: chunkIndex,
          chunkCount: attachment.chunkCount,
        );
        attachmentKey.fillRange(0, attachmentKey.length, 0);
        Uint8List? plaintext;
        try {
          if (attachment.algorithm ==
              EncryptedAttachmentDescriptor.legacyAlgorithm) {
            await Future<void>.delayed(Duration.zero);
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
          } else {
            if (encrypted.length <
                WampAppAttachmentLimits.aesGcmOverheadBytes) {
              throw const FormatException(
                'Encrypted attachment chunk is too short.',
              );
            }
            final nonce = Uint8List.fromList(
              Uint8List.sublistView(encrypted, 0, 12),
            );
            final ciphertextAndTag = Uint8List.fromList(
              Uint8List.sublistView(encrypted, 12),
            );
            final additionalData = _chunkAdditionalData(
              attachmentVersion: attachment.version,
              algorithm: attachment.algorithm,
              messageId: messageId,
              attachmentId: attachment.attachmentId,
              chunkIndex: chunkIndex,
              chunkCount: attachment.chunkCount,
            );
            try {
              plaintext = await _runCrypto(
                AttachmentCryptoRequest(
                  operation: AttachmentCryptoOperation.decrypt,
                  key: chunkKey,
                  nonce: nonce,
                  additionalData: additionalData,
                  input: ciphertextAndTag,
                ),
                isCancelled: isCancelled,
              );
            } finally {
              nonce.fillRange(0, nonce.length, 0);
              ciphertextAndTag.fillRange(0, ciphertextAndTag.length, 0);
              additionalData.fillRange(0, additionalData.length, 0);
            }
          }
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
          if (error is FormatException ||
              error is AttachmentTransferCancelled) {
            rethrow;
          }
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
        attachmentVersion: EncryptedAttachmentDescriptor.currentVersion,
        algorithm: EncryptedAttachmentDescriptor.currentAlgorithm,
        messageId: messageId,
        attachmentId: attachmentId,
        chunkIndex: chunkIndex,
        chunkCount: chunkCount,
      );
      final nonce = _bytes(12);
      final additionalData = _chunkAdditionalData(
        attachmentVersion: EncryptedAttachmentDescriptor.currentVersion,
        algorithm: EncryptedAttachmentDescriptor.currentAlgorithm,
        messageId: messageId,
        attachmentId: attachmentId,
        chunkIndex: chunkIndex,
        chunkCount: chunkCount,
      );
      try {
        final ciphertextAndTag = await _runCrypto(
          AttachmentCryptoRequest(
            operation: AttachmentCryptoOperation.encrypt,
            key: chunkKey,
            nonce: nonce,
            additionalData: additionalData,
            input: plaintext,
          ),
          isCancelled: isCancelled,
        );
        if (ciphertextAndTag.length != plaintext.length + 16) {
          throw const AttachmentCryptoException(
            'attachment crypto returned an invalid payload',
          );
        }
        final encrypted = Uint8List(nonce.length + ciphertextAndTag.length)
          ..setRange(0, nonce.length, nonce)
          ..setRange(
            nonce.length,
            nonce.length + ciphertextAndTag.length,
            ciphertextAndTag,
          );
        ciphertextAndTag.fillRange(0, ciphertextAndTag.length, 0);
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
        nonce.fillRange(0, nonce.length, 0);
        additionalData.fillRange(0, additionalData.length, 0);
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
        durationMilliseconds: source.durationMilliseconds,
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
    required String attachmentVersion,
    required String algorithm,
    required String messageId,
    required String attachmentId,
    required int chunkIndex,
    required int chunkCount,
  }) {
    final context =
        attachmentVersion == EncryptedAttachmentDescriptor.legacyVersion
        ? '${EncryptedAttachmentChunk.version}\n$messageId\n$attachmentId\n'
              '$chunkIndex\n$chunkCount'
        : '$attachmentVersion\n$algorithm\n'
              '${EncryptedAttachmentChunk.version}\n$messageId\n$attachmentId\n'
              '$chunkIndex\n$chunkCount';
    return Uint8List.fromList(
      Hmac(sha256, attachmentKey).convert(utf8.encode(context)).bytes,
    );
  }

  Uint8List _chunkAdditionalData({
    required String attachmentVersion,
    required String algorithm,
    required String messageId,
    required String attachmentId,
    required int chunkIndex,
    required int chunkCount,
  }) => Uint8List.fromList(
    utf8.encode(
      '$attachmentVersion\n$algorithm\n'
      '${EncryptedAttachmentChunk.version}\n$messageId\n$attachmentId\n'
      '$chunkIndex\n$chunkCount',
    ),
  );

  Future<Uint8List> _runCrypto(
    AttachmentCryptoRequest request, {
    required bool Function()? isCancelled,
  }) async {
    _throwIfCancelled(isCancelled);
    final task = _cryptoWorker.start(request, timeout: workerTimeout);
    Timer? cancellationTimer;
    if (isCancelled != null) {
      cancellationTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        if (isCancelled()) unawaited(task.cancel());
      });
    }
    try {
      return await task.result;
    } on AttachmentCryptoCancelledException {
      throw const AttachmentTransferCancelled();
    } finally {
      cancellationTimer?.cancel();
    }
  }

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

  void _throwIfDisposed() {
    if (_disposed) throw StateError('Attachment cipher is disposed');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _cryptoWorker.dispose();
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
