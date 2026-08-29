import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/x25519.dart';
import 'package:wamp_app/src/infrastructure/attachment_chunk_cache.dart';
import 'package:wamp_app/src/infrastructure/attachment_chunk_cache_factory_io.dart';
import 'package:wamp_app/src/infrastructure/attachment_cipher.dart';
import 'package:wamp_app/src/infrastructure/attachment_crypto_worker.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('voice-note duration stays inside the encrypted descriptor', () async {
    final cache = MemoryAttachmentChunkCache();
    addTearDown(cache.dispose);
    final cipher = AttachmentCipher();
    addTearDown(cipher.dispose);
    final plaintext = Uint8List.fromList(
      List<int>.generate(40044, (i) => i % 256),
    );

    final attachment = (await cipher.encryptSources(
      scope: 'voice-scope',
      senderUsername: 'alice',
      messageId: 'voice_message_identifier_31',
      sources: [
        AttachmentPlaintextSource(
          name: 'voice.wav',
          contentType: 'audio/wav',
          kind: ChatAttachmentKind.voiceNote,
          byteCount: plaintext.length,
          durationMilliseconds: 1250,
          openRead: () => Stream.value(plaintext),
        ),
      ],
      cache: cache,
    )).single;

    expect(attachment.kind, ChatAttachmentKind.voiceNote);
    expect(attachment.durationMilliseconds, 1250);
  });

  test('sticker kind stays inside the encrypted descriptor', () async {
    final cache = MemoryAttachmentChunkCache();
    addTearDown(cache.dispose);
    final cipher = AttachmentCipher();
    addTearDown(cipher.dispose);
    final plaintext = Uint8List.fromList(const [137, 80, 78, 71, 13, 10]);

    final attachment = (await cipher.encryptSources(
      scope: 'sticker-scope',
      senderUsername: 'alice',
      messageId: 'sticker_message_identifier_31',
      sources: [
        AttachmentPlaintextSource(
          name: 'nice.png',
          contentType: 'image/png',
          kind: ChatAttachmentKind.sticker,
          byteCount: plaintext.length,
          openRead: () => Stream.value(plaintext),
        ),
      ],
      cache: cache,
    )).single;

    expect(attachment.kind, ChatAttachmentKind.sticker);
    expect(attachment.contentType, 'image/png');
    expect(attachment.durationMilliseconds, isNull);
  });

  const scope = 'cache-scope';
  const messageId = 'message_identifier_1234';

  test(
    'streams, encrypts, caches, and verifies multiple bounded chunks',
    () async {
      final plaintext = Uint8List.fromList(
        List<int>.generate(
          (2 * WampAppAttachmentLimits.defaultChunkBytes) + 193,
          (index) => index % 251,
        ),
      );
      final cache = MemoryAttachmentChunkCache();
      addTearDown(cache.dispose);
      final cipher = AttachmentCipher(random: Random(7));
      addTearDown(cipher.dispose);

      final attachments = await cipher.encryptSources(
        scope: scope,
        senderUsername: 'alice',
        messageId: messageId,
        sources: [
          AttachmentPlaintextSource(
            name: 'photo.jpg',
            contentType: 'image/jpeg',
            kind: ChatAttachmentKind.image,
            byteCount: plaintext.length,
            openRead: () => Stream.fromIterable([
              plaintext.sublist(0, 17),
              plaintext.sublist(17, 1500000),
              plaintext.sublist(1500000),
            ]),
          ),
        ],
        cache: cache,
      );

      final attachment = attachments.single;
      expect(attachment.version, EncryptedAttachmentDescriptor.currentVersion);
      expect(
        attachment.algorithm,
        EncryptedAttachmentDescriptor.currentAlgorithm,
      );
      expect(attachment.chunkCount, 3);
      expect(attachment.plaintextBytes, plaintext.length);
      for (var index = 0; index < attachment.chunkCount; index += 1) {
        final chunk = await cache.get(
          scope: scope,
          senderUsername: 'alice',
          messageId: messageId,
          attachmentId: attachment.attachmentId,
          chunkIndex: index,
          chunkCount: attachment.chunkCount,
        );
        expect(chunk, isNotNull);
        expect(chunk!.encryptedBytes, isNot(contains('photo.jpg'.codeUnits)));
      }

      final opened = await cipher.decryptToBytes(
        scope: scope,
        senderUsername: 'alice',
        messageId: messageId,
        attachment: attachment,
        cache: cache,
      );
      expect(opened, plaintext);
    },
  );

  test(
    'prefetch authenticates ciphertext for later offline decryption',
    () async {
      final plaintext = Uint8List.fromList(
        List<int>.generate(65537, (index) => (index * 17) % 251),
      );
      final producer = MemoryAttachmentChunkCache();
      final consumer = MemoryAttachmentChunkCache();
      addTearDown(producer.dispose);
      addTearDown(consumer.dispose);
      final cipher = AttachmentCipher(random: Random(9));
      addTearDown(cipher.dispose);
      final attachment = (await cipher.encryptSources(
        scope: 'producer',
        senderUsername: 'alice',
        messageId: messageId,
        sources: [
          AttachmentPlaintextSource(
            name: 'view-once.bin',
            contentType: 'application/octet-stream',
            kind: ChatAttachmentKind.file,
            byteCount: plaintext.length,
            openRead: () => Stream.value(plaintext),
          ),
        ],
        cache: producer,
      )).single;
      var fetches = 0;

      await cipher.cacheEncryptedChunks(
        scope: scope,
        senderUsername: 'alice',
        messageId: messageId,
        attachment: attachment,
        cache: consumer,
        fetchChunk: (chunkIndex) async {
          fetches += 1;
          return (await producer.get(
            scope: 'producer',
            senderUsername: 'alice',
            messageId: messageId,
            attachmentId: attachment.attachmentId,
            chunkIndex: chunkIndex,
            chunkCount: attachment.chunkCount,
          ))!;
        },
      );
      await producer.removeMessage(scope: 'producer', messageId: messageId);

      expect(fetches, attachment.chunkCount);
      expect(
        await cipher.decryptToBytes(
          scope: scope,
          senderUsername: 'alice',
          messageId: messageId,
          attachment: attachment,
          cache: consumer,
        ),
        plaintext,
      );
    },
  );

  test('native ciphertext cache survives a new cache instance', () async {
    final root = await Directory.systemTemp.createTemp('wamp-app-cache-');
    addTearDown(() => root.delete(recursive: true));
    final plaintext = Uint8List.fromList(
      List<int>.generate(65537, (index) => (index * 13) % 256),
    );
    final first = NativeAttachmentChunkCache(rootDirectory: () async => root);
    final cipher = AttachmentCipher(random: Random(11));
    addTearDown(cipher.dispose);
    final attachment = (await cipher.encryptSources(
      scope: scope,
      senderUsername: 'alice',
      messageId: messageId,
      sources: [
        AttachmentPlaintextSource(
          name: 'archive.bin',
          contentType: 'application/octet-stream',
          kind: ChatAttachmentKind.file,
          byteCount: plaintext.length,
          openRead: () => Stream.value(plaintext),
        ),
      ],
      cache: first,
    )).single;
    await first.dispose();

    final reopened = NativeAttachmentChunkCache(
      rootDirectory: () async => root,
    );
    addTearDown(reopened.dispose);
    expect(
      await cipher.decryptToBytes(
        scope: scope,
        senderUsername: 'alice',
        messageId: messageId,
        attachment: attachment,
        cache: reopened,
      ),
      plaintext,
    );
  });

  test(
    'changed ciphertext, cancellation, and size mismatch fail closed',
    () async {
      final sourceBytes = Uint8List.fromList(List<int>.generate(128, (i) => i));
      final cache = MemoryAttachmentChunkCache();
      addTearDown(cache.dispose);
      final cipher = AttachmentCipher(random: Random(19));
      addTearDown(cipher.dispose);
      final attachment = (await cipher.encryptSources(
        scope: scope,
        senderUsername: 'alice',
        messageId: messageId,
        sources: [
          AttachmentPlaintextSource(
            name: 'note.bin',
            contentType: 'application/octet-stream',
            kind: ChatAttachmentKind.file,
            byteCount: sourceBytes.length,
            openRead: () => Stream.value(sourceBytes),
          ),
        ],
        cache: cache,
      )).single;
      final original = (await cache.get(
        scope: scope,
        senderUsername: 'alice',
        messageId: messageId,
        attachmentId: attachment.attachmentId,
        chunkIndex: 0,
        chunkCount: 1,
      ))!;
      final changed = original.encryptedBytes..[50] ^= 0xff;
      final corrupt = MemoryAttachmentChunkCache();
      addTearDown(corrupt.dispose);
      await corrupt.put(
        scope: scope,
        chunk: EncryptedAttachmentChunk(
          senderUsername: original.senderUsername,
          messageId: original.messageId,
          attachmentId: original.attachmentId,
          chunkIndex: original.chunkIndex,
          chunkCount: original.chunkCount,
          ciphertextSha256: attachmentCacheDigest(changed),
          encryptedBytes: changed,
        ),
      );
      await expectLater(
        cipher.decryptToBytes(
          scope: scope,
          senderUsername: 'alice',
          messageId: messageId,
          attachment: attachment,
          cache: corrupt,
        ),
        throwsFormatException,
      );

      var cancellationChecks = 0;
      await expectLater(
        cipher.decryptToBytes(
          scope: scope,
          senderUsername: 'alice',
          messageId: messageId,
          attachment: attachment,
          cache: cache,
          isCancelled: () => cancellationChecks++ > 0,
        ),
        throwsA(isA<AttachmentTransferCancelled>()),
      );

      await expectLater(
        cipher.encryptSources(
          scope: scope,
          senderUsername: 'alice',
          messageId: 'cancelled_message_1234',
          sources: [
            AttachmentPlaintextSource(
              name: 'cancel.bin',
              contentType: 'application/octet-stream',
              kind: ChatAttachmentKind.file,
              byteCount: sourceBytes.length,
              openRead: () => Stream.value(sourceBytes),
            ),
          ],
          cache: cache,
          isCancelled: () => true,
        ),
        throwsA(isA<AttachmentTransferCancelled>()),
      );

      await expectLater(
        cipher.encryptSources(
          scope: scope,
          senderUsername: 'alice',
          messageId: 'short_stream_message',
          sources: [
            AttachmentPlaintextSource(
              name: 'short.bin',
              contentType: 'application/octet-stream',
              kind: ChatAttachmentKind.file,
              byteCount: sourceBytes.length + 1,
              openRead: () => Stream.value(sourceBytes),
            ),
          ],
          cache: cache,
        ),
        throwsFormatException,
      );
    },
  );

  test('legacy XSalsa20-Poly1305 cached chunks remain readable', () async {
    final cache = MemoryAttachmentChunkCache();
    addTearDown(cache.dispose);
    final cipher = AttachmentCipher(random: Random(23));
    addTearDown(cipher.dispose);
    final plaintext = Uint8List.fromList(
      List<int>.generate(1025, (index) => index % 251),
    );
    final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
    const attachmentId = 'legacy_attachment_id_1234';
    final chunkKey = Uint8List.fromList(
      Hmac(sha256, key)
          .convert(
            utf8.encode(
              '${EncryptedAttachmentChunk.version}\n$messageId\n'
              '$attachmentId\n0\n1',
            ),
          )
          .bytes,
    );
    final encrypted = SecretBox(chunkKey).encrypt(plaintext).asTypedList;
    chunkKey.fillRange(0, chunkKey.length, 0);
    await cache.put(
      scope: scope,
      chunk: EncryptedAttachmentChunk(
        senderUsername: 'alice',
        messageId: messageId,
        attachmentId: attachmentId,
        chunkIndex: 0,
        chunkCount: 1,
        ciphertextSha256: attachmentCacheDigest(encrypted),
        encryptedBytes: encrypted,
      ),
    );
    final descriptor = EncryptedAttachmentDescriptor(
      version: EncryptedAttachmentDescriptor.legacyVersion,
      algorithm: EncryptedAttachmentDescriptor.legacyAlgorithm,
      attachmentId: attachmentId,
      kind: ChatAttachmentKind.file,
      name: 'legacy.bin',
      contentType: 'application/octet-stream',
      plaintextBytes: plaintext.length,
      chunkBytes: WampAppAttachmentLimits.defaultChunkBytes,
      chunkCount: 1,
      plaintextSha256: sha256.convert(plaintext).toString(),
      key: key,
    );

    expect(
      await cipher.decryptToBytes(
        scope: scope,
        senderUsername: 'alice',
        messageId: messageId,
        attachment: descriptor,
        cache: cache,
      ),
      plaintext,
    );
  });

  test('rejects malformed crypto backend output before caching', () async {
    final cache = MemoryAttachmentChunkCache();
    addTearDown(cache.dispose);
    final cipher = AttachmentCipher(
      random: Random(29),
      cryptoWorker: _MalformedAttachmentCryptoWorker(),
    );
    addTearDown(cipher.dispose);

    await expectLater(
      cipher.encryptSources(
        scope: scope,
        senderUsername: 'alice',
        messageId: 'malformed_crypto_message',
        sources: [
          AttachmentPlaintextSource(
            name: 'invalid.bin',
            contentType: 'application/octet-stream',
            kind: ChatAttachmentKind.file,
            byteCount: 1,
            openRead: () => Stream.value(Uint8List.fromList([1])),
          ),
        ],
        cache: cache,
      ),
      throwsA(isA<AttachmentCryptoException>()),
    );
  });
}

final class _MalformedAttachmentCryptoWorker implements AttachmentCryptoWorker {
  @override
  AttachmentCryptoTask start(
    AttachmentCryptoRequest request, {
    Duration? timeout,
  }) => _MalformedAttachmentCryptoTask(request);

  @override
  Future<void> dispose() async {}
}

final class _MalformedAttachmentCryptoTask implements AttachmentCryptoTask {
  _MalformedAttachmentCryptoTask(AttachmentCryptoRequest request)
    : result = Future<Uint8List>.value(Uint8List(request.input.length));

  @override
  final Future<Uint8List> result;

  @override
  Future<void> cancel() async {}
}
