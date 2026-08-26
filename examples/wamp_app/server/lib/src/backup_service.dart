import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'backup_store.dart';

final class BackupService {
  const BackupService({required this.store});

  final BackupStore store;

  Future<BackupUploadSession> begin(
    String username,
    BackupUploadRequest request,
  ) => store.begin(username, request);

  Future<void> putChunk(String username, EncryptedBackupChunk chunk) =>
      store.putChunk(username, chunk);

  Future<BackupMetadata> commit(String username, String uploadId) =>
      store.commit(username, uploadId);

  Future<BackupMetadata> metadata(String username) => store.metadata(username);

  Future<EncryptedBackupDownloadChunk> readChunk({
    required String username,
    required int revision,
    required int chunkIndex,
  }) => store.readChunk(
    username: username,
    revision: revision,
    chunkIndex: chunkIndex,
  );

  Future<bool> delete(String username, int expectedRevision) =>
      store.delete(username, expectedRevision);
}
