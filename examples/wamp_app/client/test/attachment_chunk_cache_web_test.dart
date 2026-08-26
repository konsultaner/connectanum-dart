@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/attachment_chunk_cache_factory_web.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test(
    'IndexedDB ciphertext cache survives reopen and removes by message',
    () async {
      final marker = DateTime.now().microsecondsSinceEpoch;
      final scope = 'web-scope-$marker';
      final messageId = 'web_message_$marker';
      final attachmentId = 'web_attachment_$marker';
      final bytes = Uint8List.fromList(
        List<int>.generate(128, (index) => (marker + index) & 0xff),
      );
      final chunk = EncryptedAttachmentChunk(
        senderUsername: 'alice',
        messageId: messageId,
        attachmentId: attachmentId,
        chunkIndex: 0,
        chunkCount: 1,
        ciphertextSha256:
            'a9822e81bcbf5f9dcc70f8e0757f53bbc0929d7d6a6fbfac154d71c4536c1f87',
        encryptedBytes: bytes,
      );

      final first = WebAttachmentChunkCache();
      await first.put(scope: scope, chunk: chunk);
      await first.dispose();

      final reopened = WebAttachmentChunkCache();
      addTearDown(reopened.dispose);
      final cached = await reopened.get(
        scope: scope,
        senderUsername: 'alice',
        messageId: messageId,
        attachmentId: attachmentId,
        chunkIndex: 0,
        chunkCount: 1,
      );
      expect(cached?.encryptedBytes, bytes);

      await reopened.removeMessage(scope: scope, messageId: messageId);
      expect(
        await reopened.get(
          scope: scope,
          senderUsername: 'alice',
          messageId: messageId,
          attachmentId: attachmentId,
          chunkIndex: 0,
          chunkCount: 1,
        ),
        isNull,
      );
    },
  );
}
