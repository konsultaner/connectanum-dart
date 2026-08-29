import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
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

  test('exact duplicates succeed at quota without consuming bytes', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-files-');
    addTearDown(() => directory.delete(recursive: true));
    final messageId = _token(16, 18);
    final chunk = _chunk(
      messageId: messageId,
      attachmentId: _token(16, 19),
      chunkIndex: 0,
      chunkCount: 1,
      fill: 18,
    );
    final bytes = chunk.encryptedBytes.length;
    final store = AttachmentStore(
      directory.path,
      maxTotalBytes: bytes * 2,
      maxBytesPerSender: bytes,
    );
    await store.initialize();

    await store.put(chunk);
    expect((await store.put(chunk)).receipt.duplicate, isTrue);
    expect(store.totalBytes, bytes);
    expect(store.bytesForSender('alice'), bytes);
    await expectLater(
      store.put(
        _chunk(
          messageId: messageId,
          attachmentId: _token(16, 20),
          chunkIndex: 0,
          chunkCount: 1,
          fill: 19,
        ),
      ),
      throwsA(isA<AttachmentQuotaExceeded>()),
    );
    expect(store.totalBytes, bytes);
  });

  test('global quota is atomic across different attachments', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-files-');
    addTearDown(() => directory.delete(recursive: true));
    final first = _chunk(
      messageId: _token(16, 21),
      attachmentId: _token(16, 22),
      chunkIndex: 0,
      chunkCount: 1,
      fill: 20,
    );
    final second = _chunk(
      senderUsername: 'bob',
      messageId: _token(16, 23),
      attachmentId: _token(16, 24),
      chunkIndex: 0,
      chunkCount: 1,
      fill: 21,
    );
    final bytes = first.encryptedBytes.length;
    final store = AttachmentStore(
      directory.path,
      maxTotalBytes: bytes,
      maxBytesPerSender: bytes,
    );
    await store.initialize();

    final results = await Future.wait([
      _capture(() => store.put(first)),
      _capture(() => store.put(second)),
    ]);

    expect(results.whereType<AttachmentChunkStoreResult>(), hasLength(1));
    expect(results.whereType<AttachmentQuotaExceeded>(), hasLength(1));
    expect(store.totalBytes, bytes);
  });

  test(
    'startup rebuilds usage, migrates manifests, and removes orphans',
    () async {
      final directory = await Directory.systemTemp.createTemp('wampapp-files-');
      addTearDown(() => directory.delete(recursive: true));
      final chunk = _chunk(
        messageId: _token(16, 25),
        attachmentId: _token(16, 26),
        chunkIndex: 0,
        chunkCount: 1,
        fill: 22,
      );
      final first = AttachmentStore(directory.path);
      await first.initialize();
      await first.put(chunk);
      final manifest = await directory
          .list(recursive: true)
          .where(
            (entity) =>
                entity is File && p.basename(entity.path) == 'manifest.json',
          )
          .cast<File>()
          .single;
      final legacy =
          Map<String, dynamic>.from(
              jsonDecode(await manifest.readAsString()) as Map,
            )
            ..['version'] = 1
            ..remove('created_at')
            ..remove('updated_at');
      await manifest.writeAsString(jsonEncode(legacy), flush: true);
      final orphan = File(p.join(manifest.parent.path, 'orphan.bin'));
      await orphan.writeAsBytes([1, 2, 3], flush: true);

      final restarted = AttachmentStore(directory.path);
      await restarted.initialize();

      expect(restarted.totalBytes, chunk.encryptedBytes.length);
      expect(restarted.bytesForSender('alice'), chunk.encryptedBytes.length);
      expect(await orphan.exists(), isFalse);
      final migrated = jsonDecode(await manifest.readAsString()) as Map;
      expect(migrated['version'], 2);
      expect(migrated['created_at'], isA<String>());
      expect(migrated['updated_at'], isA<String>());
    },
  );

  test(
    'staged ciphertext is retained until its TTL and then removed',
    () async {
      final directory = await Directory.systemTemp.createTemp('wampapp-files-');
      addTearDown(() => directory.delete(recursive: true));
      var now = DateTime.utc(2026, 8, 24, 12);
      final chunk = _chunk(
        messageId: _token(16, 27),
        attachmentId: _token(16, 28),
        chunkIndex: 0,
        chunkCount: 1,
        fill: 23,
      );
      final store = AttachmentStore(
        directory.path,
        stagingTtl: const Duration(hours: 1),
        clock: () => now,
      );
      await store.initialize();
      await store.put(chunk);

      now = now.add(const Duration(minutes: 59));
      expect(
        (await store.prune(
          loadActiveMessages: () async => const [],
        )).removedAttachments,
        0,
      );
      now = DateTime.utc(2026, 8, 24, 13);
      final removed = await store.prune(
        loadActiveMessages: () async => const [],
      );
      expect(removed.removedAttachments, 1);
      expect(removed.removedBytes, chunk.encryptedBytes.length);
      expect(store.totalBytes, 0);
    },
  );

  test(
    'pruning retains live mailbox references and removes expired ones',
    () async {
      final directory = await Directory.systemTemp.createTemp('wampapp-files-');
      addTearDown(() => directory.delete(recursive: true));
      final now = DateTime.utc(2026, 8, 24, 12);
      final attachments = AttachmentStore(
        '${directory.path}/attachments',
        stagingTtl: const Duration(minutes: 15),
        clock: () => now,
      );
      final mailbox = MailboxStore('${directory.path}/messages.json');
      await attachments.initialize();
      await mailbox.initialize();
      final live = _message(
        messageId: _token(16, 29),
        attachmentId: _token(16, 30),
        expiresAt: DateTime.utc(2026, 8, 24, 15),
      );
      final expired = _message(
        messageId: _token(16, 31),
        attachmentId: _token(16, 32),
        expiresAt: DateTime.utc(2026, 8, 24, 13),
      );
      await attachments.put(
        _chunk(
          messageId: live.messageId,
          attachmentId: live.attachmentIds.single,
          chunkIndex: 0,
          chunkCount: 1,
          fill: 24,
        ),
      );
      await attachments.put(
        _chunk(
          messageId: expired.messageId,
          attachmentId: expired.attachmentIds.single,
          chunkIndex: 0,
          chunkCount: 1,
          fill: 25,
        ),
      );
      await mailbox.append(live, now: now);
      await mailbox.append(expired, now: now);
      final pruneAt = DateTime.utc(2026, 8, 24, 14);

      final result = await attachments.prune(
        loadActiveMessages: () =>
            mailbox.activeAttachmentMessages(now: pruneAt),
        now: pruneAt,
      );

      expect(result.removedAttachments, 1);
      expect(
        await attachments.readChunk(
          senderUsername: 'alice',
          messageId: live.messageId,
          attachmentId: live.attachmentIds.single,
          chunkIndex: 0,
        ),
        isA<EncryptedAttachmentChunk>(),
      );
      await expectLater(
        attachments.readChunk(
          senderUsername: 'alice',
          messageId: expired.messageId,
          attachmentId: expired.attachmentIds.single,
          chunkIndex: 0,
        ),
        throwsA(isA<AttachmentNotFound>()),
      );
    },
  );

  test(
    'retention retries consumed view-once deletion before staging TTL',
    () async {
      final directory = await Directory.systemTemp.createTemp('wampapp-files-');
      addTearDown(() => directory.delete(recursive: true));
      final now = DateTime.utc(2026, 8, 24, 12);
      final attachments = AttachmentStore(
        '${directory.path}/attachments',
        stagingTtl: const Duration(days: 1),
        clock: () => now,
      );
      final mailbox = MailboxStore('${directory.path}/messages.json');
      await attachments.initialize();
      await mailbox.initialize();
      final message = _message(
        messageId: _token(16, 33),
        attachmentId: _token(16, 34),
        oneTime: true,
      );
      final chunk = _chunk(
        messageId: message.messageId,
        attachmentId: message.attachmentIds.single,
        chunkIndex: 0,
        chunkCount: 1,
        fill: 35,
      );
      await attachments.put(chunk);
      await mailbox.append(message, now: now);
      await mailbox.consumeOneTime(
        'bob',
        _token(32, 15),
        message.messageId,
        now: now.add(const Duration(minutes: 1)),
      );

      final removed = await attachments.prune(
        loadActiveMessages: () => mailbox.activeAttachmentMessages(now: now),
        loadImmediatelyRemovableMessages: () =>
            mailbox.consumedOneTimeAttachmentMessages(),
        now: now,
      );

      expect(removed.removedAttachments, 1);
      expect(removed.removedBytes, chunk.encryptedBytes.length);
      expect(attachments.totalBytes, 0);
    },
  );

  test('message commit is atomic against attachment pruning', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-files-');
    addTearDown(() => directory.delete(recursive: true));
    var now = DateTime.utc(2026, 8, 24, 12);
    final message = _message(
      messageId: _token(16, 33),
      attachmentId: _token(16, 34),
      expiresAt: DateTime.utc(2026, 8, 24, 16),
    );
    final chunk = _chunk(
      messageId: message.messageId,
      attachmentId: message.attachmentIds.single,
      chunkIndex: 0,
      chunkCount: 1,
      fill: 26,
    );
    final store = AttachmentStore(
      directory.path,
      stagingTtl: const Duration(minutes: 15),
      clock: () => now,
    );
    await store.initialize();
    await store.put(chunk);
    now = DateTime.utc(2026, 8, 24, 14);
    final commitEntered = Completer<void>();
    final releaseCommit = Completer<void>();
    var committed = false;
    final commit = store.commitMessage(message, () async {
      commitEntered.complete();
      await releaseCommit.future;
      committed = true;
      return 42;
    });
    await commitEntered.future;
    var pruneCompleted = false;
    final prune = store
        .prune(
          loadActiveMessages: () async => committed ? [message] : const [],
          now: now,
        )
        .whenComplete(() => pruneCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(pruneCompleted, isFalse);

    releaseCommit.complete();
    expect(await commit, 42);
    expect((await prune).removedAttachments, 0);
    expect(store.totalBytes, chunk.encryptedBytes.length);
  });

  test('a send fails closed when pruning wins before message commit', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-files-');
    addTearDown(() => directory.delete(recursive: true));
    var now = DateTime.utc(2026, 8, 24, 12);
    final message = _message(
      messageId: _token(16, 35),
      attachmentId: _token(16, 36),
      expiresAt: DateTime.utc(2026, 8, 24, 16),
    );
    final store = AttachmentStore(
      directory.path,
      stagingTtl: const Duration(minutes: 15),
      clock: () => now,
    );
    await store.initialize();
    await store.put(
      _chunk(
        messageId: message.messageId,
        attachmentId: message.attachmentIds.single,
        chunkIndex: 0,
        chunkCount: 1,
        fill: 27,
      ),
    );
    now = DateTime.utc(2026, 8, 24, 14);
    expect(
      (await store.prune(
        loadActiveMessages: () async => const [],
      )).removedAttachments,
      1,
    );
    var committed = false;

    await expectLater(
      store.commitMessage(message, () async {
        committed = true;
      }),
      throwsA(isA<AttachmentIncomplete>()),
    );
    expect(committed, isFalse);
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

  test('message commit rejects same-length ciphertext corruption', () async {
    final directory = await Directory.systemTemp.createTemp('wampapp-files-');
    addTearDown(() => directory.delete(recursive: true));
    final store = AttachmentStore(directory.path);
    await store.initialize();
    final message = _message(
      messageId: _token(16, 37),
      attachmentId: _token(16, 38),
    );
    final chunk = _chunk(
      messageId: message.messageId,
      attachmentId: message.attachmentIds.single,
      chunkIndex: 0,
      chunkCount: 1,
      fill: 28,
    );
    await store.put(chunk);
    final chunkFile = await directory
        .list(recursive: true)
        .where(
          (entity) =>
              entity is File && p.basename(entity.path) == 'chunk-000.bin',
        )
        .cast<File>()
        .single;
    await chunkFile.writeAsBytes(
      List<int>.filled(chunk.encryptedBytes.length, 29),
      flush: true,
    );

    await expectLater(
      store.commitMessage(message, () async {}),
      throwsA(isA<AttachmentUnavailable>()),
    );
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
  String senderUsername = 'alice',
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
    senderUsername: senderUsername,
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
  DateTime? expiresAt,
  bool oneTime = false,
}) {
  final senderDevice = _token(32, 12);
  return EncryptedChatMessage(
    messageId: messageId,
    conversationId: _token(32, 13),
    senderUsername: 'alice',
    senderDeviceId: senderDevice,
    recipientUsername: 'bob',
    createdAt: DateTime.utc(2026, 8, 24, 12),
    oneTime: oneTime,
    expiresAt: expiresAt ?? DateTime.utc(2026, 8, 24, 13),
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

Future<Object> _capture(Future<Object> Function() action) async {
  try {
    return await action();
  } catch (error) {
    return error;
  }
}
