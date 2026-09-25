import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  final digest = 'a' * 64;
  const uploadId = 'abcdefghijklmnop';

  test(
    'backup constructors reject negative revisions and inconsistent counts',
    () {
      final maximum = BackupUploadRequest(
        expectedRevision: 0,
        byteCount: WampAppBackupTransferLimits.maximumArchiveBytes,
        chunkCount: WampAppBackupTransferLimits.maximumChunkCount,
        sha256: digest,
      );
      expect(
        BackupUploadRequest.fromWampKeywords(
          maximum.toWampKeywords(),
        ).byteCount,
        WampAppBackupTransferLimits.maximumArchiveBytes,
      );
      for (final (revision, bytes, chunks) in [
        (-1, 1, 1),
        (0, 0, 0),
        (0, 1, 0),
        (0, 1, 2),
        (0, WampAppBackupTransferLimits.chunkBytes + 1, 1),
      ]) {
        expect(
          () => BackupUploadRequest(
            expectedRevision: revision,
            byteCount: bytes,
            chunkCount: chunks,
            sha256: digest,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => BackupUploadSession(uploadId: uploadId, expectedRevision: -1),
        throwsFormatException,
      );
      for (final revision in [-1, 0]) {
        expect(
          () => EncryptedBackupDownloadChunk(
            revision: revision,
            chunkIndex: 0,
            bytes: Uint8List(1),
          ),
          throwsFormatException,
        );
        expect(
          () => BackupMetadata(
            revision: revision,
            byteCount: 1,
            chunkCount: 1,
            sha256: digest,
            updatedAt: DateTime.utc(2026),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('upload and download chunks enforce index and byte boundaries', () {
    final constructors = <Object Function(int, Uint8List)>[
      (index, bytes) => EncryptedBackupChunk(
        uploadId: uploadId,
        chunkIndex: index,
        bytes: bytes,
      ),
      (index, bytes) => EncryptedBackupDownloadChunk(
        revision: 1,
        chunkIndex: index,
        bytes: bytes,
      ),
    ];
    for (final create in constructors) {
      expect(() => create(0, Uint8List(1)), returnsNormally);
      expect(
        () => create(
          WampAppBackupTransferLimits.maximumChunkCount - 1,
          Uint8List(WampAppBackupTransferLimits.chunkBytes),
        ),
        returnsNormally,
      );
      for (final index in [-1, WampAppBackupTransferLimits.maximumChunkCount]) {
        expect(() => create(index, Uint8List(1)), throwsFormatException);
      }
      for (final size in [0, WampAppBackupTransferLimits.chunkBytes + 1]) {
        expect(() => create(0, Uint8List(size)), throwsFormatException);
      }
    }
  });

  test('backup wire envelopes require every field with its proper type', () {
    final fixtures =
        <(Map<String, dynamic>, Object Function(Map<String, dynamic>?))>[
          (
            BackupUploadRequest(
              expectedRevision: 0,
              byteCount: 1,
              chunkCount: 1,
              sha256: digest,
            ).toWampKeywords(),
            BackupUploadRequest.fromWampKeywords,
          ),
          (
            BackupUploadSession(
              uploadId: uploadId,
              expectedRevision: 0,
            ).toWampKeywords(),
            BackupUploadSession.fromWampKeywords,
          ),
          (
            EncryptedBackupChunk(
              uploadId: uploadId,
              chunkIndex: 0,
              bytes: Uint8List(1),
            ).toWampKeywords(),
            EncryptedBackupChunk.fromWampKeywords,
          ),
          (
            BackupMetadata(
              revision: 1,
              byteCount: 1,
              chunkCount: 1,
              sha256: digest,
              updatedAt: DateTime.utc(2026),
            ).toWampKeywords(),
            BackupMetadata.fromWampKeywords,
          ),
          (
            EncryptedBackupDownloadChunk(
              revision: 1,
              chunkIndex: 0,
              bytes: Uint8List(1),
            ).toWampKeywords(),
            EncryptedBackupDownloadChunk.fromWampKeywords,
          ),
        ];
    for (final (wire, decode) in fixtures) {
      expect(() => decode(wire), returnsNormally);
      expect(() => decode(null), throwsFormatException);
      for (final key in wire.keys) {
        expect(
          () => decode({...wire}..remove(key)),
          throwsFormatException,
          reason: 'missing $key',
        );
        for (final invalid in [null, Object()]) {
          expect(
            () => decode({...wire, key: invalid}),
            throwsFormatException,
            reason: 'invalid $key',
          );
        }
      }
    }
  });
}
