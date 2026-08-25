import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('private attachment descriptors round-trip with exact bounds', () {
    final descriptor = EncryptedAttachmentDescriptor(
      attachmentId: _token(16, 1),
      kind: ChatAttachmentKind.image,
      name: 'holiday.jpg',
      contentType: 'image/jpeg',
      plaintextBytes: WampAppAttachmentLimits.defaultChunkBytes + 5,
      chunkBytes: WampAppAttachmentLimits.defaultChunkBytes,
      chunkCount: 2,
      plaintextSha256: 'a' * 64,
      key: Uint8List.fromList(List<int>.generate(32, (index) => index)),
    );

    final restored = EncryptedAttachmentDescriptor.fromJson(
      descriptor.toJson(),
    );

    expect(restored.attachmentId, descriptor.attachmentId);
    expect(restored.kind, ChatAttachmentKind.image);
    expect(restored.name, 'holiday.jpg');
    expect(restored.contentType, 'image/jpeg');
    expect(restored.plaintextBytes, descriptor.plaintextBytes);
    expect(restored.key, descriptor.key);
  });

  test('private descriptors reject mismatched chunks and unsafe metadata', () {
    EncryptedAttachmentDescriptor create({
      String name = 'file.bin',
      int plaintextBytes = 1,
      int chunkBytes = 1,
      int chunkCount = 1,
      int keyBytes = 32,
    }) => EncryptedAttachmentDescriptor(
      attachmentId: _token(16, 2),
      kind: ChatAttachmentKind.file,
      name: name,
      contentType: 'application/octet-stream',
      plaintextBytes: plaintextBytes,
      chunkBytes: chunkBytes,
      chunkCount: chunkCount,
      plaintextSha256: 'b' * 64,
      key: Uint8List(keyBytes),
    );

    expect(() => create(chunkCount: 2), throwsFormatException);
    expect(() => create(name: '../secret'), returnsNormally);
    expect(() => create(name: 'bad\u0000name'), throwsFormatException);
    expect(() => create(keyBytes: 31), throwsFormatException);
    expect(
      () => create(
        plaintextBytes: WampAppAttachmentLimits.maxAttachmentBytes + 1,
      ),
      throwsFormatException,
    );
  });

  test('opaque chunks use binary WAMP fields and defensive copies', () {
    final bytes = Uint8List.fromList(
      List<int>.filled(WampAppAttachmentLimits.secretBoxOverheadBytes, 7),
    );
    final chunk = EncryptedAttachmentChunk(
      senderUsername: 'Alice',
      messageId: _token(16, 3),
      attachmentId: _token(16, 4),
      chunkIndex: 0,
      chunkCount: 1,
      ciphertextSha256: 'c' * 64,
      encryptedBytes: bytes,
    );
    bytes.fillRange(0, bytes.length, 99);

    final wire = chunk.toWampKeywords();
    expect(wire['encrypted_bytes'], isA<Uint8List>());
    final restored = EncryptedAttachmentChunk.fromWampKeywords(wire);
    expect(restored.senderUsername, 'alice');
    expect(restored.encryptedBytes, everyElement(7));
    (wire['encrypted_bytes'] as Uint8List).fillRange(0, bytes.length, 42);
    expect(restored.encryptedBytes, everyElement(7));
  });

  test('upload status is sorted, unique, bounded, and self-consistent', () {
    final status = AttachmentUploadStatus(
      messageId: _token(16, 5),
      attachmentId: _token(16, 6),
      chunkCount: 3,
      receivedChunks: const [0, 2],
    );
    expect(status.complete, isFalse);
    expect(
      AttachmentUploadStatus.fromWampKeywords(
        status.toWampKeywords(),
      ).receivedChunks,
      [0, 2],
    );
    expect(
      () => AttachmentUploadStatus(
        messageId: _token(16, 5),
        attachmentId: _token(16, 6),
        chunkCount: 3,
        receivedChunks: const [2, 1],
      ),
      throwsFormatException,
    );
    final wire = status.toWampKeywords()..['complete'] = true;
    expect(
      () => AttachmentUploadStatus.fromWampKeywords(wire),
      throwsFormatException,
    );
  });
}

String _token(int bytes, int seed) => base64Url
    .encode(List<int>.generate(bytes, (index) => (index + seed) % 256))
    .replaceAll('=', '');
