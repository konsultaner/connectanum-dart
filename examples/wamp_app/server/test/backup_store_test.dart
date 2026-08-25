import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/src/backup_store.dart';

void main() {
  late Directory temporary;
  late BackupStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('wampapp-backups-');
    store = BackupStore(temporary.path);
    await store.initialize();
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'commits, downloads, and reloads a multi-chunk opaque archive',
    () async {
      final bytes = Uint8List(WampAppBackupTransferLimits.chunkBytes + 7);
      for (var index = 0; index < bytes.length; index += 1) {
        bytes[index] = index % 251;
      }
      final metadata = await _upload(store, 'alice', bytes);
      expect(metadata.revision, 1);
      expect(metadata.chunkCount, 2);

      final downloaded = await _download(store, 'alice', metadata);
      expect(downloaded, bytes);

      final reloaded = BackupStore(temporary.path);
      await reloaded.initialize();
      expect(
        (await reloaded.metadata('alice')).toWampKeywords(),
        metadata.toWampKeywords(),
      );
      expect(await _download(reloaded, 'alice', metadata), bytes);
    },
  );

  test('revision conflicts preserve the last committed archive', () async {
    final original = Uint8List.fromList([1, 2, 3]);
    final metadata = await _upload(store, 'alice', original);
    final replacement = Uint8List.fromList([4, 5, 6]);
    await expectLater(
      _upload(store, 'alice', replacement, expectedRevision: 0),
      throwsA(isA<BackupConflict>()),
    );
    expect(await _download(store, 'alice', metadata), original);
  });

  test(
    'upload identifiers are caller-bound and incomplete commits fail closed',
    () async {
      final request = _request(Uint8List.fromList([1, 2, 3]));
      final upload = await store.begin('alice', request);
      await expectLater(
        store.putChunk(
          'bob',
          EncryptedBackupChunk(
            uploadId: upload.uploadId,
            chunkIndex: 0,
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ),
        throwsA(isA<BackupUploadNotFound>()),
      );
      await expectLater(
        store.commit('alice', upload.uploadId),
        throwsA(isA<BackupIncomplete>()),
      );
      await expectLater(
        store.metadata('alice'),
        throwsA(isA<BackupNotFound>()),
      );
    },
  );

  test(
    'checksum mismatch and changed chunks fail without publishing',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final upload = await store.begin(
        'alice',
        BackupUploadRequest(
          expectedRevision: 0,
          byteCount: bytes.length,
          chunkCount: 1,
          sha256: List.filled(64, '0').join(),
        ),
      );
      await store.putChunk(
        'alice',
        EncryptedBackupChunk(
          uploadId: upload.uploadId,
          chunkIndex: 0,
          bytes: bytes,
        ),
      );
      await expectLater(
        store.commit('alice', upload.uploadId),
        throwsFormatException,
      );
      await expectLater(
        store.metadata('alice'),
        throwsA(isA<BackupNotFound>()),
      );
    },
  );

  test('delete uses compare-and-swap revision', () async {
    final metadata = await _upload(
      store,
      'alice',
      Uint8List.fromList([1, 2, 3]),
    );
    await expectLater(
      store.delete('alice', metadata.revision + 1),
      throwsA(isA<BackupConflict>()),
    );
    expect(await store.delete('alice', metadata.revision), isTrue);
    expect(await store.delete('alice', 0), isFalse);
  });

  test('expired uploads are discarded before later operations', () async {
    var now = DateTime.utc(2026, 8, 25, 12);
    final expiringStore = BackupStore(
      temporary.path,
      uploadTtl: const Duration(minutes: 1),
      clock: () => now,
    );
    await expiringStore.initialize();
    final bytes = Uint8List.fromList([1, 2, 3]);
    final upload = await expiringStore.begin('alice', _request(bytes));

    now = now.add(const Duration(minutes: 1, seconds: 1));

    await expectLater(
      expiringStore.putChunk(
        'alice',
        EncryptedBackupChunk(
          uploadId: upload.uploadId,
          chunkIndex: 0,
          bytes: bytes,
        ),
      ),
      throwsA(isA<BackupUploadNotFound>()),
    );
    expect(
      await temporary
          .list(recursive: true)
          .where((entity) => entity.path.endsWith('.part'))
          .isEmpty,
      isTrue,
    );
  });

  test('out-of-order and duplicate chunks fail without advancing', () async {
    final bytes = Uint8List(WampAppBackupTransferLimits.chunkBytes + 1);
    final upload = await store.begin('alice', _request(bytes));

    await expectLater(
      store.putChunk(
        'alice',
        EncryptedBackupChunk(
          uploadId: upload.uploadId,
          chunkIndex: 1,
          bytes: Uint8List.fromList([0]),
        ),
      ),
      throwsFormatException,
    );
    await store.putChunk(
      'alice',
      EncryptedBackupChunk(
        uploadId: upload.uploadId,
        chunkIndex: 0,
        bytes: Uint8List.sublistView(
          bytes,
          0,
          WampAppBackupTransferLimits.chunkBytes,
        ),
      ),
    );
    await expectLater(
      store.putChunk(
        'alice',
        EncryptedBackupChunk(
          uploadId: upload.uploadId,
          chunkIndex: 0,
          bytes: Uint8List(WampAppBackupTransferLimits.chunkBytes),
        ),
      ),
      throwsFormatException,
    );
    await store.putChunk(
      'alice',
      EncryptedBackupChunk(
        uploadId: upload.uploadId,
        chunkIndex: 1,
        bytes: Uint8List.fromList([0]),
      ),
    );
    expect((await store.commit('alice', upload.uploadId)).revision, 1);
  });

  test('archives are isolated by normalized account identity', () async {
    final aliceBytes = Uint8List.fromList([1, 2, 3]);
    final bobBytes = Uint8List.fromList([4, 5, 6]);
    final alice = await _upload(store, 'Alice', aliceBytes);
    final bob = await _upload(store, 'bob', bobBytes);

    expect(await _download(store, 'alice', alice), aliceBytes);
    expect(await _download(store, 'BOB', bob), bobBytes);
  });

  test('corrupt committed archives fail closed during restart', () async {
    await _upload(store, 'alice', Uint8List.fromList([1, 2, 3]));
    final archive = await temporary
        .list(recursive: true)
        .where((entity) => entity.path.endsWith('.bin'))
        .cast<File>()
        .single;
    await archive.writeAsBytes([3, 2, 1], flush: true);

    await expectLater(
      BackupStore(temporary.path).initialize(),
      throwsA(isA<BackupUnavailable>()),
    );
  });

  test('global quota reserves committed and staged archive bytes', () async {
    final quotaStore = BackupStore(temporary.path, maximumTotalBytes: 8);
    await quotaStore.initialize();
    await _upload(quotaStore, 'alice', Uint8List.fromList([1, 2, 3]));
    final bobUpload = await quotaStore.begin(
      'bob',
      _request(Uint8List.fromList([4, 5, 6])),
    );

    await expectLater(
      quotaStore.begin('carol', _request(Uint8List.fromList([7, 8, 9]))),
      throwsA(isA<BackupQuotaExceeded>()),
    );
    await quotaStore.putChunk(
      'bob',
      EncryptedBackupChunk(
        uploadId: bobUpload.uploadId,
        chunkIndex: 0,
        bytes: Uint8List.fromList([4, 5, 6]),
      ),
    );
    await quotaStore.commit('bob', bobUpload.uploadId);
    await expectLater(
      quotaStore.begin(
        'alice',
        _request(Uint8List.fromList([9, 9, 9]), expectedRevision: 1),
      ),
      throwsA(isA<BackupQuotaExceeded>()),
    );
  });

  test('global quota rejects an oversized first upload', () async {
    final quotaStore = BackupStore(temporary.path, maximumTotalBytes: 2);
    await quotaStore.initialize();

    await expectLater(
      quotaStore.begin('alice', _request(Uint8List.fromList([1, 2, 3]))),
      throwsA(isA<BackupQuotaExceeded>()),
    );
  });

  test('restart rejects committed data above the configured quota', () async {
    await _upload(store, 'alice', Uint8List.fromList([1, 2, 3]));

    await expectLater(
      BackupStore(temporary.path, maximumTotalBytes: 2).initialize(),
      throwsA(isA<BackupQuotaExceeded>()),
    );
  });
}

BackupUploadRequest _request(Uint8List bytes, {int expectedRevision = 0}) {
  return BackupUploadRequest(
    expectedRevision: expectedRevision,
    byteCount: bytes.length,
    chunkCount:
        (bytes.length + WampAppBackupTransferLimits.chunkBytes - 1) ~/
        WampAppBackupTransferLimits.chunkBytes,
    sha256: sha256.convert(bytes).toString(),
  );
}

Future<BackupMetadata> _upload(
  BackupStore store,
  String username,
  Uint8List bytes, {
  int expectedRevision = 0,
}) async {
  final request = _request(bytes, expectedRevision: expectedRevision);
  final upload = await store.begin(username, request);
  for (var index = 0; index < request.chunkCount; index += 1) {
    final start = index * WampAppBackupTransferLimits.chunkBytes;
    final end = (start + WampAppBackupTransferLimits.chunkBytes).clamp(
      0,
      bytes.length,
    );
    await store.putChunk(
      username,
      EncryptedBackupChunk(
        uploadId: upload.uploadId,
        chunkIndex: index,
        bytes: Uint8List.sublistView(bytes, start, end),
      ),
    );
  }
  return store.commit(username, upload.uploadId);
}

Future<Uint8List> _download(
  BackupStore store,
  String username,
  BackupMetadata metadata,
) async {
  final builder = BytesBuilder(copy: false);
  for (var index = 0; index < metadata.chunkCount; index += 1) {
    final chunk = await store.readChunk(
      username: username,
      revision: metadata.revision,
      chunkIndex: index,
    );
    builder.add(chunk.bytes);
  }
  return builder.takeBytes();
}
