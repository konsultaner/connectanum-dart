import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  final digest = List.filled(64, 'a').join();

  test('backup transfer models round-trip binary WAMP payloads', () {
    final request = BackupUploadRequest(
      expectedRevision: 3,
      byteCount: WampAppBackupTransferLimits.chunkBytes + 1,
      chunkCount: 2,
      sha256: digest,
    );
    expect(
      BackupUploadRequest.fromWampKeywords(request.toWampKeywords()).sha256,
      digest,
    );

    final session = BackupUploadSession(
      uploadId: 'abcdefghijklmnop',
      expectedRevision: 3,
    );
    expect(
      BackupUploadSession.fromWampKeywords(session.toWampKeywords()).uploadId,
      session.uploadId,
    );

    final chunk = EncryptedBackupChunk(
      uploadId: session.uploadId,
      chunkIndex: 1,
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(
      EncryptedBackupChunk.fromWampKeywords(chunk.toWampKeywords()).bytes,
      [1, 2, 3],
    );
    final download = EncryptedBackupDownloadChunk(
      revision: 4,
      chunkIndex: 0,
      bytes: Uint8List.fromList([4, 5, 6]),
    );
    expect(
      EncryptedBackupDownloadChunk.fromWampKeywords(
        download.toWampKeywords(),
      ).bytes,
      [4, 5, 6],
    );

    final metadata = BackupMetadata(
      revision: 4,
      byteCount: request.byteCount,
      chunkCount: request.chunkCount,
      sha256: request.sha256,
      updatedAt: DateTime.utc(2026, 8, 25),
    );
    expect(
      BackupMetadata.fromWampKeywords(
        metadata.toWampKeywords(),
      ).toWampKeywords(),
      metadata.toWampKeywords(),
    );
  });

  test('backup transfer bounds fail closed', () {
    expect(
      () => BackupUploadRequest(
        expectedRevision: 0,
        byteCount: WampAppBackupTransferLimits.maximumArchiveBytes + 1,
        chunkCount: WampAppBackupTransferLimits.maximumChunkCount + 1,
        sha256: digest,
      ),
      throwsFormatException,
    );
    expect(
      () => EncryptedBackupChunk(
        uploadId: 'abcdefghijklmnop',
        chunkIndex: 0,
        bytes: Uint8List(WampAppBackupTransferLimits.chunkBytes + 1),
      ),
      throwsFormatException,
    );
    expect(
      () => BackupUploadRequest(
        expectedRevision: 0,
        byteCount: 1,
        chunkCount: 1,
        sha256: 'not-a-digest',
      ),
      throwsFormatException,
    );
  });
}
