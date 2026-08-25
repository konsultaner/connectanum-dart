import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/attachment_chunk_cache.dart';
import 'package:wamp_app/src/infrastructure/attachment_chunk_cache_factory_io.dart';
import 'package:wamp_app/src/infrastructure/attachment_cipher.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
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

  test('native ciphertext cache survives a new cache instance', () async {
    final root = await Directory.systemTemp.createTemp('wamp-app-cache-');
    addTearDown(() => root.delete(recursive: true));
    final plaintext = Uint8List.fromList(
      List<int>.generate(65537, (index) => (index * 13) % 256),
    );
    final first = NativeAttachmentChunkCache(rootDirectory: () async => root);
    final cipher = AttachmentCipher(random: Random(11));
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
}
