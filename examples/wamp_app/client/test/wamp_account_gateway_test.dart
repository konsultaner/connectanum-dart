import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart' as wamp;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/infrastructure/wamp_account_gateway.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('classifies WAMP message-send failures without exposing payloads', () {
    MessageSendException classified(String? uri) =>
        MessageSendException.fromWampError(wamp.Error(48, 1, const {}, uri));

    expect(
      classified(WampAppProtocol.errorMessageConflict).kind,
      MessageSendFailureKind.conflict,
    );
    expect(
      classified(WampAppProtocol.errorInvalidMessage).kind,
      MessageSendFailureKind.rejected,
    );
    expect(
      classified(wamp.Error.notAuthorized).kind,
      MessageSendFailureKind.rejected,
    );
    expect(
      classified(WampAppProtocol.errorMessageUnavailable).kind,
      MessageSendFailureKind.retryable,
    );
    expect(
      classified('com.example.unknown').kind,
      MessageSendFailureKind.retryable,
    );
    expect(
      classified(null).toString(),
      'Message delivery is temporarily unavailable.',
    );
  });

  test('classifies attachment failures without exposing ciphertext', () {
    AttachmentTransferException classified(String? uri) =>
        AttachmentTransferException.fromWampError(
          wamp.Error(48, 1, const {}, uri),
        );

    expect(
      classified(WampAppProtocol.errorAttachmentConflict).kind,
      AttachmentTransferFailureKind.conflict,
    );
    expect(
      classified(WampAppProtocol.errorAttachmentNotFound).kind,
      AttachmentTransferFailureKind.notFound,
    );
    expect(
      classified(WampAppProtocol.errorAttachmentIncomplete).kind,
      AttachmentTransferFailureKind.incomplete,
    );
    expect(
      classified(WampAppProtocol.errorAttachmentQuotaExceeded).kind,
      AttachmentTransferFailureKind.quotaExceeded,
    );
    expect(
      classified(WampAppProtocol.errorInvalidAttachment).kind,
      AttachmentTransferFailureKind.rejected,
    );
    expect(
      classified('com.example.unknown').kind,
      AttachmentTransferFailureKind.retryable,
    );
  });

  test('classifies profile failures without exposing profile payloads', () {
    ProfileUpdateException classified(String? uri) =>
        ProfileUpdateException.fromWampError(wamp.Error(48, 1, const {}, uri));

    expect(
      classified(WampAppProtocol.errorProfileConflict).kind,
      ProfileUpdateFailureKind.conflict,
    );
    expect(
      classified(WampAppProtocol.errorInvalidProfile).kind,
      ProfileUpdateFailureKind.invalid,
    );
    expect(
      classified(wamp.Error.notAuthorized).kind,
      ProfileUpdateFailureKind.invalid,
    );
    expect(
      classified(WampAppProtocol.errorProfileUnavailable).kind,
      ProfileUpdateFailureKind.retryable,
    );
    expect(
      classified('com.example.unknown').kind,
      ProfileUpdateFailureKind.retryable,
    );
  });

  test('classifies MCP consent failures without exposing account data', () {
    McpConsentException classified(String? uri) =>
        McpConsentException.fromWampError(wamp.Error(48, 1, const {}, uri));

    expect(
      classified(WampAppProtocol.errorMcpConsentConflict).kind,
      McpConsentFailureKind.conflict,
    );
    expect(
      classified(WampAppProtocol.errorInvalidMcpConsent).kind,
      McpConsentFailureKind.invalid,
    );
    expect(
      classified(wamp.Error.notAuthorized).kind,
      McpConsentFailureKind.invalid,
    );
    expect(
      classified(WampAppProtocol.errorMcpUnavailable).kind,
      McpConsentFailureKind.retryable,
    );
    expect(
      classified('com.example.unknown').kind,
      McpConsentFailureKind.retryable,
    );
    expect(
      classified(null).toString(),
      'MCP consent is temporarily unavailable.',
    );
  });

  test('classifies platform push failures without exposing tokens', () {
    PlatformPushSubscriptionException classified(String? uri) =>
        PlatformPushSubscriptionException.fromWampError(
          wamp.Error(48, 1, const {}, uri),
        );

    expect(
      classified(WampAppProtocol.errorInvalidPushSubscription).kind,
      PlatformPushSubscriptionFailureKind.rejected,
    );
    expect(
      classified(WampAppProtocol.errorDeviceRevoked).kind,
      PlatformPushSubscriptionFailureKind.rejected,
    );
    expect(
      classified(WampAppProtocol.errorPushSubscriptionUnavailable).kind,
      PlatformPushSubscriptionFailureKind.retryable,
    );
    expect(
      classified('com.example.unknown').toString(),
      'Platform push subscriptions are temporarily unavailable.',
    );
  });

  test('classifies remote backup failures without exposing archives', () {
    RemoteBackupException classified(String? uri) =>
        RemoteBackupException.fromWampError(wamp.Error(48, 1, const {}, uri));

    expect(
      classified(WampAppProtocol.errorBackupConflict).kind,
      RemoteBackupFailureKind.conflict,
    );
    expect(
      classified(WampAppProtocol.errorBackupNotFound).kind,
      RemoteBackupFailureKind.notFound,
    );
    expect(
      classified(WampAppProtocol.errorBackupQuotaExceeded).kind,
      RemoteBackupFailureKind.quotaExceeded,
    );
    expect(
      classified(WampAppProtocol.errorInvalidBackup).kind,
      RemoteBackupFailureKind.rejected,
    );
    expect(
      classified('com.example.unknown').kind,
      RemoteBackupFailureKind.retryable,
    );
  });

  test('uploads and downloads a verified multi-chunk remote backup', () async {
    final archive = Uint8List(WampAppBackupTransferLimits.chunkBytes + 3);
    for (var index = 0; index < archive.length; index += 1) {
      archive[index] = index % 251;
    }
    BackupUploadRequest? request;
    final uploaded = <Uint8List>[];
    BackupMetadata? metadata;
    final connection = _connection(
      beginBackupUpload: (value) async {
        request = value;
        return BackupUploadSession(
          uploadId: 'abcdefghijklmnop',
          expectedRevision: value.expectedRevision,
        );
      },
      putBackupChunk: (chunk) async => uploaded.add(chunk.bytes),
      commitBackupUpload: (_) async => metadata = BackupMetadata(
        revision: 1,
        byteCount: archive.length,
        chunkCount: 2,
        sha256: sha256.convert(archive).toString(),
        updatedAt: DateTime.utc(2026, 8, 25),
      ),
      getBackupMetadata: () async => metadata,
      getBackupChunk: (revision, index) async {
        final start = index * WampAppBackupTransferLimits.chunkBytes;
        final end = (start + WampAppBackupTransferLimits.chunkBytes).clamp(
          0,
          archive.length,
        );
        return EncryptedBackupDownloadChunk(
          revision: revision,
          chunkIndex: index,
          bytes: Uint8List.sublistView(archive, start, end),
        );
      },
    );
    addTearDown(connection.close);

    final uploadedMetadata = await connection.uploadRemoteBackup(archive);
    expect(request?.expectedRevision, 0);
    expect(request?.chunkCount, 2);
    expect(uploaded, hasLength(2));
    expect(uploaded.expand((chunk) => chunk), archive);
    expect(uploadedMetadata.revision, 1);

    final downloaded = await connection.downloadRemoteBackup();
    expect(downloaded?.metadata.revision, 1);
    expect(downloaded?.archive, archive);
  });

  test(
    'download fails closed when the archive digest does not match',
    () async {
      final connection = _connection(
        getBackupMetadata: () async => BackupMetadata(
          revision: 1,
          byteCount: 3,
          chunkCount: 1,
          sha256: List.filled(64, '0').join(),
          updatedAt: DateTime.utc(2026, 8, 25),
        ),
        getBackupChunk: (revision, index) async => EncryptedBackupDownloadChunk(
          revision: revision,
          chunkIndex: index,
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      addTearDown(connection.close);

      await expectLater(
        connection.downloadRemoteBackup(),
        throwsFormatException,
      );
    },
  );
}

AccountConnection _connection({
  Future<BackupUploadSession> Function(BackupUploadRequest request)?
  beginBackupUpload,
  Future<void> Function(EncryptedBackupChunk chunk)? putBackupChunk,
  Future<BackupMetadata> Function(String uploadId)? commitBackupUpload,
  Future<BackupMetadata?> Function()? getBackupMetadata,
  Future<EncryptedBackupDownloadChunk> Function(int revision, int chunkIndex)?
  getBackupChunk,
}) {
  final profile = AccountProfile(
    username: 'alice',
    displayName: 'Alice',
    status: '',
    revision: 0,
    updatedAt: DateTime.utc(2026, 8, 25),
  );
  return AccountConnection(
    endpoint: ServerEndpoint.parse('wss://chat.example/ws'),
    username: 'alice',
    initialProfile: profile,
    closeTransport: () async {},
    getProfileCallback: (_) async => profile,
    updateProfileCallback: (_) async => profile,
    enrollDeviceCallback: (_) => throw UnimplementedError(),
    listDevicesCallback: (_) => throw UnimplementedError(),
    lookupDevicesCallback: (_, _) => throw UnimplementedError(),
    revokeDeviceCallback: (_) => throw UnimplementedError(),
    sendMessageCallback: (_) => throw UnimplementedError(),
    syncMessagesCallback: (_, _) => throw UnimplementedError(),
    markMessageReceiptCallback: (_, _) => throw UnimplementedError(),
    consumeOneTimeCallback: (_) => throw UnimplementedError(),
    beginBackupUploadCallback: beginBackupUpload,
    putBackupChunkCallback: putBackupChunk,
    commitBackupUploadCallback: commitBackupUpload,
    getBackupMetadataCallback: getBackupMetadata,
    getBackupChunkCallback: getBackupChunk,
    mailboxWakeups: const Stream.empty(),
    latestMailboxWakeupCursorCallback: () => 0,
    latestMailboxWakeupErrorCallback: () => null,
  );
}
