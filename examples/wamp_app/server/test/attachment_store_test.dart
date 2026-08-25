import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/src/attachment_service.dart';
import 'package:wamp_app_server/src/attachment_store.dart';
import 'package:wamp_app_server/src/mailbox_store.dart';

void main() {
  test(
    'chunk retries are exact, resumable, and conflict on changed bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp('wampapp-files-');
      addTearDown(() => directory.delete(recursive: true));
      final store = AttachmentStore(directory.path);
      await store.initialize();
      final messageId = _token(16, 1);
      final attachmentId = _token(16, 2);
      final first = _chunk(
        messageId: messageId,
        attachmentId: attachmentId,
        chunkIndex: 0,
        chunkCount: 2,
        fill: 3,
      );
      final second = _chunk(
        messageId: messageId,
        attachmentId: attachmentId,
        chunkIndex: 1,
        chunkCount: 2,
        fill: 4,
      );

      expect(
        await store
            .status(
              senderUsername: 'alice',
              messageId: messageId,
              attachmentId: attachmentId,
              chunkCount: 2,
            )
            .then((status) => status.receivedChunks),
        isEmpty,
      );
      final accepted = await store.put(first);
      expect(accepted.receipt.duplicate, isFalse);
      expect(accepted.receipt.complete, isFalse);
      final duplicate = await store.put(first);
      expect(duplicate.receipt.duplicate, isTrue);
      expect(duplicate.status.receivedChunks, [0]);
      await store.put(second);
      final status = await store.status(
        senderUsername: 'alice',
        messageId: messageId,
        attachmentId: attachmentId,
        chunkCount: 2,
      );
      expect(status.complete, isTrue);
      expect(status.receivedChunks, [0, 1]);
      expect(
        (await store.readChunk(
          senderUsername: 'alice',
          messageId: messageId,
          attachmentId: attachmentId,
          chunkIndex: 1,
        )).encryptedBytes,
        second.encryptedBytes,
      );

      await expectLater(
        store.put(
          _chunk(
            messageId: messageId,
            attachmentId: attachmentId,
            chunkIndex: 0,
            chunkCount: 2,
            fill: 9,
          ),
        ),
        throwsA(isA<AttachmentConflict>()),
      );
      await expectLater(
        store.status(
          senderUsername: 'alice',
          messageId: messageId,
          attachmentId: attachmentId,
          chunkCount: 3,
        ),
        throwsA(isA<AttachmentConflict>()),
      );
    },
  );

  test('concurrent duplicate writes converge to one verified chunk', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-files-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AttachmentStore(directory.path);
    await store.initialize();
    final chunk = _chunk(
      messageId: _token(16, 3),
      attachmentId: _token(16, 4),
      chunkIndex: 0,
      chunkCount: 1,
      fill: 5,
    );

    final results = await Future.wait(
      List.generate(8, (_) => store.put(chunk)),
    );

    expect(results.where((result) => !result.receipt.duplicate), hasLength(1));
    expect(results.every((result) => result.status.complete), isTrue);
    expect(
      (await store.readChunk(
        senderUsername: 'alice',
        messageId: chunk.messageId,
        attachmentId: chunk.attachmentId,
        chunkIndex: 0,
      )).encryptedBytes,
      chunk.encryptedBytes,
    );
  });

  test('message acceptance requires every opaque chunk', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-files-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AttachmentStore(directory.path);
    await store.initialize();
    final attachmentId = _token(16, 6);
    final message = _message(
      messageId: _token(16, 5),
      attachmentId: attachmentId,
    );
    await store.put(
      _chunk(
        messageId: message.messageId,
        attachmentId: attachmentId,
        chunkIndex: 0,
        chunkCount: 2,
        fill: 6,
      ),
    );

    await expectLater(
      store.requireComplete(message),
      throwsA(isA<AttachmentIncomplete>()),
    );
    await store.put(
      _chunk(
        messageId: message.messageId,
        attachmentId: attachmentId,
        chunkIndex: 1,
        chunkCount: 2,
        fill: 7,
      ),
    );
    await store.requireComplete(message);
  });

  test(
    'mailbox participants alone can download accepted unexpired chunks',
    () async {
      final directory = await Directory.systemTemp.createTemp('wampapp-files-');
      addTearDown(() => directory.delete(recursive: true));
      final attachments = AttachmentStore('${directory.path}/attachments');
      final mailbox = MailboxStore('${directory.path}/messages.json');
      await attachments.initialize();
      await mailbox.initialize();
      final service = AttachmentService(store: attachments, mailbox: mailbox);
      final attachmentId = _token(16, 8);
      final message = _message(
        messageId: _token(16, 7),
        attachmentId: attachmentId,
      );
      final chunk = _chunk(
        messageId: message.messageId,
        attachmentId: attachmentId,
        chunkIndex: 0,
        chunkCount: 1,
        fill: 8,
      );
      await service.putChunk('alice', chunk);

      await expectLater(
        service.getChunk(
          'bob',
          messageId: message.messageId,
          attachmentId: attachmentId,
          chunkIndex: 0,
        ),
        throwsA(isA<AttachmentNotFound>()),
      );
      await mailbox.append(message, now: DateTime.utc(2026, 8, 24, 12));
      expect(
        (await service.getChunk(
          'bob',
          messageId: message.messageId,
          attachmentId: attachmentId,
          chunkIndex: 0,
          now: DateTime.utc(2026, 8, 24, 12, 1),
        )).encryptedBytes,
        chunk.encryptedBytes,
      );
      await expectLater(
        service.getChunk(
          'mallory',
          messageId: message.messageId,
          attachmentId: attachmentId,
          chunkIndex: 0,
          now: DateTime.utc(2026, 8, 24, 12, 1),
        ),
        throwsA(isA<AttachmentNotFound>()),
      );
      await expectLater(
        service.getChunk(
          'bob',
          messageId: message.messageId,
          attachmentId: attachmentId,
          chunkIndex: 0,
          now: DateTime.utc(2026, 8, 24, 14),
        ),
        throwsA(isA<AttachmentNotFound>()),
      );
    },
  );

  test('disk state contains no private attachment metadata', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-files-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AttachmentStore(directory.path);
    await store.initialize();
    await store.put(
      _chunk(
        messageId: _token(16, 9),
        attachmentId: _token(16, 10),
        chunkIndex: 0,
        chunkCount: 1,
        fill: 10,
      ),
    );

    final persisted = StringBuffer();
    await for (final entity in directory.list(recursive: true)) {
      persisted.write(entity.path);
      if (entity is File) persisted.write(await entity.readAsBytes());
    }
    final state = persisted.toString();
    expect(state, isNot(contains('private-photo.jpg')));
    expect(state, isNot(contains('image/jpeg')));
    expect(state, isNot(contains('plaintext_sha256')));
    expect(state, isNot(contains('attachment_key')));
  });

  test('unsafe identifiers fail before filesystem mutation', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-files-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AttachmentStore(directory.path);
    await store.initialize();

    expect(
      () => store.status(
        senderUsername: 'alice',
        messageId: '../../../../escape',
        attachmentId: _token(16, 11),
        chunkCount: 1,
      ),
      throwsFormatException,
    );
    expect(await directory.list().toList(), isEmpty);
  });
}

EncryptedAttachmentChunk _chunk({
  required String messageId,
  required String attachmentId,
  required int chunkIndex,
  required int chunkCount,
  required int fill,
}) {
  final bytes = Uint8List.fromList(
    List<int>.filled(WampAppAttachmentLimits.secretBoxOverheadBytes + 7, fill),
  );
  return EncryptedAttachmentChunk(
    senderUsername: 'alice',
    messageId: messageId,
    attachmentId: attachmentId,
    chunkIndex: chunkIndex,
    chunkCount: chunkCount,
    ciphertextSha256: sha256.convert(bytes).toString(),
    encryptedBytes: bytes,
  );
}

EncryptedChatMessage _message({
  required String messageId,
  required String attachmentId,
}) {
  final senderDevice = _token(32, 12);
  return EncryptedChatMessage(
    messageId: messageId,
    conversationId: _token(32, 13),
    senderUsername: 'alice',
    senderDeviceId: senderDevice,
    recipientUsername: 'bob',
    createdAt: DateTime.utc(2026, 8, 24, 12),
    expiresAt: DateTime.utc(2026, 8, 24, 13),
    encryptedPayload: Uint8List.fromList(List<int>.filled(64, 14)),
    attachmentIds: [attachmentId],
    wrappedKeys: [
      WrappedConversationKey(
        conversationId: _token(32, 13),
        senderUsername: 'alice',
        senderDeviceId: senderDevice,
        recipientUsername: 'bob',
        recipientDeviceId: _token(32, 15),
        sealedKey: _token(80, 16),
        signature: _token(64, 17),
        createdAt: DateTime.utc(2026, 8, 24, 12),
      ),
    ],
  );
}

String _token(int length, int value) =>
    base64Url.encode(List<int>.filled(length, value)).replaceAll('=', '');
