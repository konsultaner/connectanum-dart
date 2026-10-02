import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('file descriptor bounds include empty files and exactly 64 MiB', () {
    for (final (bytes, chunks) in [
      (0, 1),
      (1, 1),
      (1048576, 1),
      (1048577, 2),
      (67108864, 64),
    ]) {
      final descriptor = _descriptor(
        bytes: bytes,
        chunkBytes: 1048576,
        chunks: chunks,
      );
      final decoded = EncryptedAttachmentDescriptor.fromJson(
        descriptor.toJson(),
      );
      expect(decoded.plaintextBytes, bytes);
      expect(decoded.chunkCount, chunks);
      expect(decoded.chunkBytes, 1048576);
    }
    for (final create in <EncryptedAttachmentDescriptor Function()>[
      () => _descriptor(bytes: -1, chunks: 0),
      () => _descriptor(bytes: 67108865, chunkBytes: 1048576, chunks: 65),
      () => _descriptor(bytes: 0, chunks: 0),
      () => _descriptor(bytes: 1, chunkBytes: 0),
      () => _descriptor(bytes: 1, chunkBytes: 1048577),
      () => _descriptor(bytes: 65, chunks: 65),
      () => _descriptor(bytes: 2, chunks: 1),
    ]) {
      expect(create, throwsFormatException);
    }
  });

  test(
    'direct descriptor names and media types retain their full allowed length',
    () {
      final maximum = _descriptor(name: 'n' * 255, contentType: 't' * 255);
      expect(maximum.name, 'n' * 255);
      expect(maximum.contentType, 't' * 255);
      for (final invalid in [
        '',
        'n' * 256,
        ' leading',
        'trailing ',
        'mid\u0000dle',
        'mid\u007fdle',
      ]) {
        expect(() => _descriptor(name: invalid), throwsFormatException);
        expect(() => _descriptor(contentType: invalid), throwsFormatException);
      }
    },
  );

  test('voice-note PCM duration rounding and five-minute limits agree', () {
    // Mono 16-bit PCM at 16 kHz uses 32 bytes/ms after the 44-byte WAV header.
    for (final (bytes, milliseconds) in [
      (46, 1),
      (76, 1),
      (78, 2),
      (9600044, 300000),
    ]) {
      final chunks = (bytes + 1048575) ~/ 1048576;
      final descriptor = _descriptor(
        kind: ChatAttachmentKind.voiceNote,
        contentType: 'audio/wav',
        bytes: bytes,
        chunkBytes: 1048576,
        chunks: chunks,
        duration: milliseconds,
      );
      final decoded = EncryptedAttachmentDescriptor.fromJson(
        descriptor.toJson(),
      );
      expect(decoded.durationMilliseconds, milliseconds);
      expect(decoded.plaintextBytes, bytes);
    }
    for (final duration in <int?>[null, -1, 0, 2, 300001]) {
      expect(
        () => _descriptor(
          kind: ChatAttachmentKind.voiceNote,
          contentType: 'audio/wav',
          bytes: 76,
          chunkBytes: 76,
          duration: duration,
        ),
        throwsFormatException,
      );
    }
    for (final bytes in [0, 43, 44, 45, 47, 9600046]) {
      expect(
        () => _descriptor(
          kind: ChatAttachmentKind.voiceNote,
          contentType: 'audio/wav',
          bytes: bytes,
          chunkBytes: 1048576,
          chunks: bytes == 0 ? 1 : (bytes + 1048575) ~/ 1048576,
          duration: bytes > 9600044 ? 300001 : 1,
        ),
        throwsFormatException,
      );
    }
    expect(
      () => _descriptor(
        kind: ChatAttachmentKind.voiceNote,
        contentType: 'audio/ogg',
        bytes: 76,
        chunkBytes: 76,
        duration: 1,
      ),
      throwsFormatException,
    );
    expect(() => _descriptor(duration: 1), throwsFormatException);
  });

  test(
    'last chunk preserves maximum ciphertext length through wire round-trip',
    () {
      final bytes = Uint8List(1048576 + 40)..[1048615] = 255;
      final chunk = EncryptedAttachmentChunk(
        senderUsername: 'alice',
        messageId: _token(16, 1),
        attachmentId: _token(16, 2),
        chunkIndex: 63,
        chunkCount: 64,
        ciphertextSha256: 'a' * 64,
        encryptedBytes: bytes,
      );
      bytes[1048615] = 0;
      final decoded = EncryptedAttachmentChunk.fromWampKeywords(
        chunk.toWampKeywords(),
      );
      expect(decoded.chunkIndex, 63);
      expect(decoded.chunkCount, 64);
      expect(decoded.encryptedBytes, hasLength(1048616));
      expect(decoded.encryptedBytes.last, 255);
      final status = AttachmentUploadStatus(
        messageId: chunk.messageId,
        attachmentId: chunk.attachmentId,
        chunkCount: 64,
        receivedChunks: List.generate(64, (index) => index),
      );
      expect(status.complete, isTrue);
      expect(
        AttachmentUploadStatus.fromWampKeywords(
          status.toWampKeywords(),
        ).receivedChunks,
        orderedEquals(List.generate(64, (index) => index)),
      );
      for (final indices in [
        [-1],
        [64],
      ]) {
        expect(
          () => AttachmentUploadStatus(
            messageId: chunk.messageId,
            attachmentId: chunk.attachmentId,
            chunkCount: 64,
            receivedChunks: indices,
          ),
          throwsFormatException,
        );
      }
    },
  );
}

EncryptedAttachmentDescriptor _descriptor({
  ChatAttachmentKind kind = ChatAttachmentKind.file,
  String name = 'file.bin',
  String contentType = 'application/octet-stream',
  int bytes = 1,
  int chunkBytes = 1,
  int chunks = 1,
  int? duration,
}) => EncryptedAttachmentDescriptor(
  attachmentId: _token(16, 1),
  kind: kind,
  name: name,
  contentType: contentType,
  plaintextBytes: bytes,
  chunkBytes: chunkBytes,
  chunkCount: chunks,
  plaintextSha256: 'a' * 64,
  durationMilliseconds: duration,
  key: Uint8List(32),
);

String _token(int bytes, int value) =>
    base64Url.encode(List<int>.filled(bytes, value)).replaceAll('=', '');
