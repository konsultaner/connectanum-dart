import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart' hide Error;
import 'package:connectanum_client/connectanum.dart' as wamp show Error;
import 'package:crypto/crypto.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

abstract interface class AccountGateway {
  Future<RegistrationReceipt> register({
    required ServerEndpoint endpoint,
    required AccountRegistration registration,
  });

  Future<AccountConnection> login({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
  });
}

enum MessageSendFailureKind { retryable, rejected, conflict }

final class MessageSendException implements Exception {
  const MessageSendException(this.kind);

  factory MessageSendException.fromWampError(wamp.Error error) {
    final kind = switch (error.error) {
      WampAppProtocol.errorMessageConflict => MessageSendFailureKind.conflict,
      WampAppProtocol.errorInvalidMessage ||
      WampAppProtocol.errorNotAuthorized ||
      wamp.Error.notAuthorized => MessageSendFailureKind.rejected,
      WampAppProtocol.errorMessageUnavailable ||
      _ => MessageSendFailureKind.retryable,
    };
    return MessageSendException(kind);
  }

  final MessageSendFailureKind kind;

  @override
  String toString() => switch (kind) {
    MessageSendFailureKind.retryable =>
      'Message delivery is temporarily unavailable.',
    MessageSendFailureKind.rejected => 'The server rejected this message.',
    MessageSendFailureKind.conflict =>
      'The message identifier conflicts with server state.',
  };
}

enum AttachmentTransferFailureKind {
  retryable,
  rejected,
  quotaExceeded,
  conflict,
  notFound,
  incomplete,
}

final class AttachmentTransferException implements Exception {
  const AttachmentTransferException(this.kind);

  factory AttachmentTransferException.fromWampError(wamp.Error error) {
    final kind = switch (error.error) {
      WampAppProtocol.errorAttachmentConflict =>
        AttachmentTransferFailureKind.conflict,
      WampAppProtocol.errorAttachmentNotFound =>
        AttachmentTransferFailureKind.notFound,
      WampAppProtocol.errorAttachmentIncomplete =>
        AttachmentTransferFailureKind.incomplete,
      WampAppProtocol.errorAttachmentQuotaExceeded =>
        AttachmentTransferFailureKind.quotaExceeded,
      WampAppProtocol.errorInvalidAttachment ||
      WampAppProtocol.errorNotAuthorized ||
      wamp.Error.notAuthorized => AttachmentTransferFailureKind.rejected,
      WampAppProtocol.errorAttachmentUnavailable ||
      _ => AttachmentTransferFailureKind.retryable,
    };
    return AttachmentTransferException(kind);
  }

  final AttachmentTransferFailureKind kind;

  @override
  String toString() => switch (kind) {
    AttachmentTransferFailureKind.retryable =>
      'Attachment transfer is temporarily unavailable.',
    AttachmentTransferFailureKind.rejected =>
      'The server rejected this attachment transfer.',
    AttachmentTransferFailureKind.quotaExceeded =>
      'The attachment storage quota is exhausted.',
    AttachmentTransferFailureKind.conflict =>
      'The attachment identifier conflicts with server state.',
    AttachmentTransferFailureKind.notFound =>
      'The encrypted attachment chunk was not found.',
    AttachmentTransferFailureKind.incomplete =>
      'The encrypted attachment upload is incomplete.',
  };
}

enum ProfileUpdateFailureKind { invalid, conflict, retryable }

final class ProfileUpdateException implements Exception {
  const ProfileUpdateException(this.kind);

  factory ProfileUpdateException.fromWampError(wamp.Error error) {
    final kind = switch (error.error) {
      WampAppProtocol.errorProfileConflict => ProfileUpdateFailureKind.conflict,
      WampAppProtocol.errorInvalidProfile ||
      WampAppProtocol.errorNotAuthorized ||
      wamp.Error.notAuthorized => ProfileUpdateFailureKind.invalid,
      WampAppProtocol.errorProfileUnavailable ||
      _ => ProfileUpdateFailureKind.retryable,
    };
    return ProfileUpdateException(kind);
  }

  final ProfileUpdateFailureKind kind;

  @override
  String toString() => switch (kind) {
    ProfileUpdateFailureKind.invalid =>
      'The server rejected this profile update.',
    ProfileUpdateFailureKind.conflict =>
      'The profile changed on another device. Review it and try again.',
    ProfileUpdateFailureKind.retryable =>
      'Profile updates are temporarily unavailable.',
  };
}

enum PlatformPushSubscriptionFailureKind { retryable, rejected }

final class PlatformPushSubscriptionException implements Exception {
  const PlatformPushSubscriptionException(this.kind);

  factory PlatformPushSubscriptionException.fromWampError(wamp.Error error) {
    final kind = switch (error.error) {
      WampAppProtocol.errorInvalidPushSubscription ||
      WampAppProtocol.errorDeviceNotFound ||
      WampAppProtocol.errorDeviceRevoked ||
      WampAppProtocol.errorNotAuthorized ||
      wamp.Error.notAuthorized => PlatformPushSubscriptionFailureKind.rejected,
      WampAppProtocol.errorPushSubscriptionUnavailable ||
      _ => PlatformPushSubscriptionFailureKind.retryable,
    };
    return PlatformPushSubscriptionException(kind);
  }

  final PlatformPushSubscriptionFailureKind kind;

  @override
  String toString() => switch (kind) {
    PlatformPushSubscriptionFailureKind.retryable =>
      'Platform push subscriptions are temporarily unavailable.',
    PlatformPushSubscriptionFailureKind.rejected =>
      'The server rejected this platform push subscription.',
  };
}

enum RemoteBackupFailureKind {
  retryable,
  rejected,
  quotaExceeded,
  conflict,
  notFound,
  incomplete,
}

final class RemoteBackupException implements Exception {
  const RemoteBackupException(this.kind);

  factory RemoteBackupException.fromWampError(wamp.Error error) {
    final kind = switch (error.error) {
      WampAppProtocol.errorBackupConflict => RemoteBackupFailureKind.conflict,
      WampAppProtocol.errorBackupNotFound => RemoteBackupFailureKind.notFound,
      WampAppProtocol.errorBackupIncomplete =>
        RemoteBackupFailureKind.incomplete,
      WampAppProtocol.errorBackupQuotaExceeded =>
        RemoteBackupFailureKind.quotaExceeded,
      WampAppProtocol.errorInvalidBackup ||
      WampAppProtocol.errorNotAuthorized ||
      wamp.Error.notAuthorized => RemoteBackupFailureKind.rejected,
      WampAppProtocol.errorBackupUnavailable ||
      _ => RemoteBackupFailureKind.retryable,
    };
    return RemoteBackupException(kind);
  }

  final RemoteBackupFailureKind kind;

  @override
  String toString() => switch (kind) {
    RemoteBackupFailureKind.retryable =>
      'Encrypted cloud backup is temporarily unavailable.',
    RemoteBackupFailureKind.rejected =>
      'The server rejected this encrypted cloud backup.',
    RemoteBackupFailureKind.quotaExceeded =>
      'The server backup upload limit has been reached.',
    RemoteBackupFailureKind.conflict =>
      'The cloud backup changed on another device. Try again.',
    RemoteBackupFailureKind.notFound => 'No encrypted cloud backup was found.',
    RemoteBackupFailureKind.incomplete =>
      'The encrypted cloud backup upload is incomplete.',
  };
}

final class EncryptedRemoteBackup {
  EncryptedRemoteBackup({required this.metadata, required Uint8List archive})
    : _archive = Uint8List.fromList(archive);

  final BackupMetadata metadata;
  final Uint8List _archive;

  Uint8List get archive => Uint8List.fromList(_archive);
}

enum CallSignalingFailureKind {
  retryable,
  rejected,
  conflict,
  notFound,
  answeredElsewhere,
  ended,
}

final class CallSignalingException implements Exception {
  const CallSignalingException(this.kind);

  factory CallSignalingException.fromWampError(wamp.Error error) {
    final kind = switch (error.error) {
      WampAppProtocol.errorCallConflict => CallSignalingFailureKind.conflict,
      WampAppProtocol.errorCallNotFound => CallSignalingFailureKind.notFound,
      WampAppProtocol.errorCallAnswered =>
        CallSignalingFailureKind.answeredElsewhere,
      WampAppProtocol.errorCallEnded => CallSignalingFailureKind.ended,
      WampAppProtocol.errorInvalidCall ||
      WampAppProtocol.errorNotAuthorized ||
      wamp.Error.notAuthorized => CallSignalingFailureKind.rejected,
      WampAppProtocol.errorCallUnavailable ||
      _ => CallSignalingFailureKind.retryable,
    };
    return CallSignalingException(kind);
  }

  final CallSignalingFailureKind kind;

  @override
  String toString() => switch (kind) {
    CallSignalingFailureKind.retryable =>
      'Call signaling is temporarily unavailable.',
    CallSignalingFailureKind.rejected =>
      'The server rejected this call operation.',
    CallSignalingFailureKind.conflict =>
      'The call signal conflicts with existing state.',
    CallSignalingFailureKind.notFound => 'That call was not found.',
    CallSignalingFailureKind.answeredElsewhere =>
      'That call was answered on another device.',
    CallSignalingFailureKind.ended => 'That call has already ended.',
  };
}

class AccountConnection {
  AccountConnection({
    required this.endpoint,
    required this.username,
    required AccountProfile initialProfile,
    required this.closeTransport,
    required this.getProfileCallback,
    required this.updateProfileCallback,
    required this.enrollDeviceCallback,
    required this.listDevicesCallback,
    required this.lookupDevicesCallback,
    required this.revokeDeviceCallback,
    required this.sendMessageCallback,
    required this.syncMessagesCallback,
    required this.markMessageReceiptCallback,
    required this.consumeOneTimeCallback,
    this.putAttachmentChunkCallback,
    this.attachmentUploadStatusCallback,
    this.getAttachmentChunkCallback,
    this.registerPlatformPushCallback,
    this.unregisterPlatformPushCallback,
    this.beginBackupUploadCallback,
    this.putBackupChunkCallback,
    this.commitBackupUploadCallback,
    this.getBackupMetadataCallback,
    this.getBackupChunkCallback,
    this.deleteBackupCallback,
    this.getCallConfigurationCallback,
    this.startCallCallback,
    this.acceptCallCallback,
    this.sendCallSignalCallback,
    this.endCallCallback,
    this.syncCallsCallback,
    Stream<CallWakeup>? callWakeups,
    this.latestCallWakeupCursorCallback,
    this.latestCallWakeupErrorCallback,
    required this.mailboxWakeups,
    required this.latestMailboxWakeupCursorCallback,
    required this.latestMailboxWakeupErrorCallback,
  }) : _profile = initialProfile,
       callWakeups = callWakeups ?? const Stream<CallWakeup>.empty();

  final ServerEndpoint endpoint;
  final String username;
  AccountProfile _profile;
  final Future<void> Function() closeTransport;
  final Future<AccountProfile> Function(String username) getProfileCallback;
  final Future<AccountProfile> Function(AccountProfileUpdate update)
  updateProfileCallback;
  final Future<DeviceRecord> Function(DeviceEnrollment enrollment)
  enrollDeviceCallback;
  final Future<DeviceDirectory> Function(bool includeRevoked)
  listDevicesCallback;
  final Future<DeviceDirectory> Function(String username, bool includeRevoked)
  lookupDevicesCallback;
  final Future<DeviceRecord> Function(String deviceId) revokeDeviceCallback;
  final Future<MessageSendReceipt> Function(EncryptedChatMessage message)
  sendMessageCallback;
  final Future<MailboxBatch> Function(int afterCursor, int limit)
  syncMessagesCallback;
  final Future<MessageReceipt> Function(String messageId, bool read)
  markMessageReceiptCallback;
  final Future<MessageReceipt> Function(OneTimeMessageConsumption consumption)
  consumeOneTimeCallback;
  final Future<AttachmentChunkReceipt> Function(EncryptedAttachmentChunk chunk)?
  putAttachmentChunkCallback;
  final Future<AttachmentUploadStatus> Function(
    String messageId,
    String attachmentId,
    int chunkCount,
  )?
  attachmentUploadStatusCallback;
  final Future<EncryptedAttachmentChunk> Function(
    String messageId,
    String attachmentId,
    int chunkIndex,
  )?
  getAttachmentChunkCallback;
  final Future<PlatformPushSubscriptionReceipt> Function(
    PlatformPushSubscriptionRequest request,
  )?
  registerPlatformPushCallback;
  final Future<bool> Function(PlatformPushSubscriptionKey key)?
  unregisterPlatformPushCallback;
  final Future<BackupUploadSession> Function(BackupUploadRequest request)?
  beginBackupUploadCallback;
  final Future<void> Function(EncryptedBackupChunk chunk)?
  putBackupChunkCallback;
  final Future<BackupMetadata> Function(String uploadId)?
  commitBackupUploadCallback;
  final Future<BackupMetadata?> Function()? getBackupMetadataCallback;
  final Future<EncryptedBackupDownloadChunk> Function(
    int revision,
    int chunkIndex,
  )?
  getBackupChunkCallback;
  final Future<bool> Function(int expectedRevision)? deleteBackupCallback;
  final Future<CallConfiguration> Function()? getCallConfigurationCallback;
  final Future<CallUpdate> Function(CallStartRequest request)?
  startCallCallback;
  final Future<CallUpdate> Function(EncryptedCallSignal answer)?
  acceptCallCallback;
  final Future<CallUpdate> Function(EncryptedCallSignal signal)?
  sendCallSignalCallback;
  final Future<CallUpdate> Function(EncryptedCallSignal signal)?
  endCallCallback;
  final Future<CallBatch> Function(String deviceId, int afterCursor, int limit)?
  syncCallsCallback;
  final Stream<CallWakeup> callWakeups;
  final int Function()? latestCallWakeupCursorCallback;
  final Object? Function()? latestCallWakeupErrorCallback;
  final Stream<MailboxWakeup> mailboxWakeups;
  final int Function() latestMailboxWakeupCursorCallback;
  final Object? Function() latestMailboxWakeupErrorCallback;
  bool _closed = false;

  AccountProfile get profile => _profile;
  String get displayName => _profile.displayName;
  int get latestMailboxWakeupCursor => latestMailboxWakeupCursorCallback();
  Object? get latestMailboxWakeupError => latestMailboxWakeupErrorCallback();
  int get latestCallWakeupCursor => latestCallWakeupCursorCallback?.call() ?? 0;
  Object? get latestCallWakeupError => latestCallWakeupErrorCallback?.call();

  Future<DeviceRecord> enrollDevice(DeviceEnrollment enrollment) {
    _ensureOpen();
    return enrollDeviceCallback(enrollment);
  }

  Future<AccountProfile> getProfile(String username) async {
    _ensureOpen();
    final normalized = AccountRegistration.normalizeUsername(username);
    final profile = await getProfileCallback(normalized);
    if (profile.username != normalized) {
      throw const FormatException(
        'The server returned a profile for another account.',
      );
    }
    return profile;
  }

  Future<AccountProfile> refreshProfile() async {
    final refreshed = await getProfile(username);
    _profile = refreshed;
    return refreshed;
  }

  Future<AccountProfile> updateProfile(AccountProfileUpdate update) async {
    _ensureOpen();
    final updated = await updateProfileCallback(update);
    _profile = updated;
    return updated;
  }

  Future<DeviceDirectory> listDevices({bool includeRevoked = false}) {
    _ensureOpen();
    return listDevicesCallback(includeRevoked);
  }

  Future<DeviceRecord> revokeDevice(String deviceId) {
    _ensureOpen();
    return revokeDeviceCallback(deviceId);
  }

  Future<DeviceDirectory> lookupDevices(
    String username, {
    bool includeRevoked = false,
  }) {
    _ensureOpen();
    return lookupDevicesCallback(username, includeRevoked);
  }

  Future<MessageSendReceipt> sendMessage(EncryptedChatMessage message) {
    _ensureOpen();
    return sendMessageCallback(message);
  }

  Future<MailboxBatch> syncMessages({
    required int afterCursor,
    int limit = 100,
  }) {
    _ensureOpen();
    return syncMessagesCallback(afterCursor, limit);
  }

  Future<MessageReceipt> markMessageDelivered(
    String messageId, {
    bool read = false,
  }) {
    _ensureOpen();
    return markMessageReceiptCallback(messageId, read);
  }

  Future<MessageReceipt> consumeOneTime(OneTimeMessageConsumption consumption) {
    _ensureOpen();
    return consumeOneTimeCallback(consumption);
  }

  Future<AttachmentChunkReceipt> putAttachmentChunk(
    EncryptedAttachmentChunk chunk,
  ) {
    _ensureOpen();
    final callback = putAttachmentChunkCallback;
    if (callback == null) {
      throw StateError('Attachment upload is unavailable on this connection.');
    }
    return callback(chunk);
  }

  Future<AttachmentUploadStatus> attachmentUploadStatus({
    required String messageId,
    required String attachmentId,
    required int chunkCount,
  }) {
    _ensureOpen();
    final callback = attachmentUploadStatusCallback;
    if (callback == null) {
      throw StateError('Attachment status is unavailable on this connection.');
    }
    return callback(messageId, attachmentId, chunkCount);
  }

  Future<EncryptedAttachmentChunk> getAttachmentChunk({
    required String messageId,
    required String attachmentId,
    required int chunkIndex,
  }) {
    _ensureOpen();
    final callback = getAttachmentChunkCallback;
    if (callback == null) {
      throw StateError(
        'Attachment download is unavailable on this connection.',
      );
    }
    return callback(messageId, attachmentId, chunkIndex);
  }

  Future<PlatformPushSubscriptionReceipt> registerPlatformPush(
    PlatformPushSubscriptionRequest request,
  ) {
    _ensureOpen();
    final callback = registerPlatformPushCallback;
    if (callback == null) {
      throw StateError(
        'Platform push registration is unavailable on this connection.',
      );
    }
    return callback(request);
  }

  Future<bool> unregisterPlatformPush(PlatformPushSubscriptionKey key) {
    _ensureOpen();
    final callback = unregisterPlatformPushCallback;
    if (callback == null) {
      throw StateError(
        'Platform push unregistration is unavailable on this connection.',
      );
    }
    return callback(key);
  }

  Future<BackupMetadata?> getRemoteBackupMetadata() {
    _ensureOpen();
    final callback = getBackupMetadataCallback;
    if (callback == null) {
      throw StateError('Cloud backup is unavailable on this connection.');
    }
    return callback();
  }

  Future<BackupMetadata> uploadRemoteBackup(
    Uint8List archive, {
    int? expectedRevision,
  }) async {
    _ensureOpen();
    final begin = beginBackupUploadCallback;
    final put = putBackupChunkCallback;
    final commit = commitBackupUploadCallback;
    if (begin == null || put == null || commit == null) {
      throw StateError('Cloud backup is unavailable on this connection.');
    }
    if (archive.isEmpty ||
        archive.length > WampAppBackupTransferLimits.maximumArchiveBytes) {
      throw const FormatException('Backup size is invalid.');
    }
    final currentRevision =
        expectedRevision ?? (await getRemoteBackupMetadata())?.revision ?? 0;
    final chunkCount =
        (archive.length + WampAppBackupTransferLimits.chunkBytes - 1) ~/
        WampAppBackupTransferLimits.chunkBytes;
    final request = BackupUploadRequest(
      expectedRevision: currentRevision,
      byteCount: archive.length,
      chunkCount: chunkCount,
      sha256: sha256.convert(archive).toString(),
    );
    final upload = await begin(request);
    if (upload.expectedRevision != currentRevision) {
      throw const FormatException(
        'The server returned an invalid backup upload session.',
      );
    }
    for (var index = 0; index < chunkCount; index += 1) {
      final start = index * WampAppBackupTransferLimits.chunkBytes;
      final end = min(
        start + WampAppBackupTransferLimits.chunkBytes,
        archive.length,
      );
      final bytes = Uint8List.sublistView(archive, start, end);
      await put(
        EncryptedBackupChunk(
          uploadId: upload.uploadId,
          chunkIndex: index,
          bytes: bytes,
        ),
      );
    }
    final metadata = await commit(upload.uploadId);
    if (metadata.revision != currentRevision + 1 ||
        metadata.byteCount != request.byteCount ||
        metadata.chunkCount != request.chunkCount ||
        metadata.sha256 != request.sha256) {
      throw const FormatException(
        'The server returned invalid backup metadata.',
      );
    }
    return metadata;
  }

  Future<EncryptedRemoteBackup?> downloadRemoteBackup() async {
    _ensureOpen();
    final getChunk = getBackupChunkCallback;
    if (getChunk == null) {
      throw StateError('Cloud backup is unavailable on this connection.');
    }
    final metadata = await getRemoteBackupMetadata();
    if (metadata == null) return null;
    final builder = BytesBuilder(copy: false);
    for (var index = 0; index < metadata.chunkCount; index += 1) {
      final chunk = await getChunk(metadata.revision, index);
      if (chunk.revision != metadata.revision || chunk.chunkIndex != index) {
        throw const FormatException(
          'The server returned the wrong backup chunk.',
        );
      }
      builder.add(chunk.bytes);
    }
    final archive = builder.takeBytes();
    if (archive.length != metadata.byteCount ||
        sha256.convert(archive).toString() != metadata.sha256) {
      archive.fillRange(0, archive.length, 0);
      throw const FormatException(
        'The downloaded backup failed integrity verification.',
      );
    }
    return EncryptedRemoteBackup(metadata: metadata, archive: archive);
  }

  Future<bool> deleteRemoteBackup(int expectedRevision) {
    _ensureOpen();
    final callback = deleteBackupCallback;
    if (callback == null) {
      throw StateError('Cloud backup is unavailable on this connection.');
    }
    return callback(expectedRevision);
  }

  Future<CallConfiguration> getCallConfiguration() {
    _ensureOpen();
    final callback = getCallConfigurationCallback;
    if (callback == null) {
      throw StateError('Call configuration is unavailable on this connection.');
    }
    return callback();
  }

  Future<CallUpdate> startCall(CallStartRequest request) {
    _ensureOpen();
    final callback = startCallCallback;
    if (callback == null) {
      throw StateError('Call signaling is unavailable on this connection.');
    }
    return callback(request);
  }

  Future<CallUpdate> acceptCall(EncryptedCallSignal answer) {
    _ensureOpen();
    final callback = acceptCallCallback;
    if (callback == null) {
      throw StateError('Call signaling is unavailable on this connection.');
    }
    return callback(answer);
  }

  Future<CallUpdate> sendCallSignal(EncryptedCallSignal signal) {
    _ensureOpen();
    final callback = sendCallSignalCallback;
    if (callback == null) {
      throw StateError('Call signaling is unavailable on this connection.');
    }
    return callback(signal);
  }

  Future<CallUpdate> endCall(EncryptedCallSignal signal) {
    _ensureOpen();
    final callback = endCallCallback;
    if (callback == null) {
      throw StateError('Call signaling is unavailable on this connection.');
    }
    return callback(signal);
  }

  Future<CallBatch> syncCalls({
    required String deviceId,
    required int afterCursor,
    int limit = 100,
  }) {
    _ensureOpen();
    final callback = syncCallsCallback;
    if (callback == null) {
      throw StateError(
        'Call synchronization is unavailable on this connection.',
      );
    }
    return callback(deviceId, afterCursor, limit);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await closeTransport();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Account connection is closed.');
  }
}

class WampAccountGateway implements AccountGateway {
  const WampAccountGateway({
    this.connectionTimeout = const Duration(seconds: 15),
    this.derivationTimeout = const Duration(seconds: 75),
  });

  final Duration connectionTimeout;
  final Duration derivationTimeout;

  @override
  Future<RegistrationReceipt> register({
    required ServerEndpoint endpoint,
    required AccountRegistration registration,
  }) async {
    endpoint.requireSecureRegistration();
    registration.validate();
    final client = Client(
      transport: WebSocketTransport.withCborSerializer(
        endpoint.websocketUri.toString(),
      ),
      realm: WampAppProtocol.registrationRealm,
    );
    Session? session;
    try {
      session = await _connect(client);
      final result = await session
          .callSingle(
            WampAppProtocol.accountRegister,
            argumentsKeywords: registration.toWampKeywords(),
          )
          .timeout(connectionTimeout);
      return RegistrationReceipt.fromWampKeywords(result.argumentsKeywords);
    } finally {
      await _close(client, session);
    }
  }

  @override
  Future<AccountConnection> login({
    required ServerEndpoint endpoint,
    required String username,
    required String password,
  }) async {
    endpoint.requireSecureRegistration();
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    final authentication = ScramAuthentication(
      password,
      derivationTimeout: derivationTimeout,
      challengeTimeout: connectionTimeout + derivationTimeout,
    );
    final client = Client(
      transport: WebSocketTransport.withCborSerializer(
        endpoint.websocketUri.toString(),
      ),
      realm: WampAppProtocol.appRealm,
      authId: normalizedUsername,
      authenticationMethods: [authentication],
    );
    final wakeups = _MailboxWakeupFeed();
    final callWakeups = _CallWakeupFeed();
    try {
      final session = await _connect(client);
      await session
          .subscribePayloadHandler(
            WampAppProtocol.mailboxChanged,
            wakeups.addEvent,
          )
          .timeout(connectionTimeout);
      await session
          .subscribePayloadHandler(
            WampAppProtocol.callChanged,
            callWakeups.addEvent,
          )
          .timeout(connectionTimeout);
      Future<AccountProfile> getProfile(String username) async {
        try {
          final result = await session
              .callSingle(
                WampAppProtocol.profileGet,
                argumentsKeywords: {'username': username},
              )
              .timeout(connectionTimeout);
          return AccountProfile.fromWampKeywords(result.argumentsKeywords);
        } on wamp.Error catch (error) {
          if (error.error == WampAppProtocol.errorProfileNotFound) {
            throw const FormatException('That profile was not found.');
          }
          if (error.error == WampAppProtocol.errorInvalidProfile ||
              error.error == WampAppProtocol.errorNotAuthorized ||
              error.error == wamp.Error.notAuthorized) {
            throw const FormatException(
              'The server rejected this profile lookup.',
            );
          }
          rethrow;
        }
      }

      final authenticatedUsername = session.authId ?? normalizedUsername;
      final profile = await getProfile(authenticatedUsername);
      if (profile.username != authenticatedUsername) {
        throw const FormatException(
          'The server returned a profile for another account.',
        );
      }
      return AccountConnection(
        endpoint: endpoint,
        username: authenticatedUsername,
        initialProfile: profile,
        getProfileCallback: getProfile,
        updateProfileCallback: (update) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.profileUpdate,
                  argumentsKeywords: update.toWampKeywords(),
                )
                .timeout(connectionTimeout);
            final updated = AccountProfile.fromWampKeywords(
              result.argumentsKeywords,
            );
            if (updated.username != authenticatedUsername) {
              throw const FormatException(
                'The server updated a profile for another account.',
              );
            }
            return updated;
          } on wamp.Error catch (error) {
            throw ProfileUpdateException.fromWampError(error);
          }
        },
        enrollDeviceCallback: (enrollment) async {
          final result = await session
              .callSingle(
                WampAppProtocol.deviceEnroll,
                argumentsKeywords: enrollment.toWampKeywords(),
              )
              .timeout(connectionTimeout);
          return DeviceRecord.fromWampKeywords(result.argumentsKeywords!);
        },
        listDevicesCallback: (includeRevoked) async {
          final result = await session
              .callSingle(
                WampAppProtocol.deviceList,
                argumentsKeywords: {'include_revoked': includeRevoked},
              )
              .timeout(connectionTimeout);
          return DeviceDirectory.fromWampKeywords(result.argumentsKeywords);
        },
        revokeDeviceCallback: (deviceId) async {
          final result = await session
              .callSingle(
                WampAppProtocol.deviceRevoke,
                argumentsKeywords: {'device_id': deviceId},
              )
              .timeout(connectionTimeout);
          return DeviceRecord.fromWampKeywords(result.argumentsKeywords!);
        },
        lookupDevicesCallback: (username, includeRevoked) async {
          final result = await session
              .callSingle(
                WampAppProtocol.deviceLookup,
                argumentsKeywords: {
                  'username': username,
                  'include_revoked': includeRevoked,
                },
              )
              .timeout(connectionTimeout);
          return DeviceDirectory.fromWampKeywords(result.argumentsKeywords);
        },
        sendMessageCallback: (message) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.messageSend,
                  argumentsKeywords: message.toWampKeywords(),
                )
                .timeout(connectionTimeout);
            return MessageSendReceipt.fromWampKeywords(
              result.argumentsKeywords,
            );
          } on wamp.Error catch (error) {
            throw MessageSendException.fromWampError(error);
          }
        },
        syncMessagesCallback: (afterCursor, limit) async {
          final result = await session
              .callSingle(
                WampAppProtocol.messageSync,
                argumentsKeywords: {
                  'after_cursor': afterCursor,
                  'limit': limit,
                },
              )
              .timeout(connectionTimeout);
          return MailboxBatch.fromWampKeywords(result.argumentsKeywords);
        },
        markMessageReceiptCallback: (messageId, read) async {
          final result = await session
              .callSingle(
                WampAppProtocol.messageReceipt,
                argumentsKeywords: {
                  'message_id': messageId,
                  'state': read ? 'read' : 'delivered',
                },
              )
              .timeout(connectionTimeout);
          return MessageReceipt.fromWampKeywords(result.argumentsKeywords);
        },
        consumeOneTimeCallback: (consumption) async {
          final result = await session
              .callSingle(
                WampAppProtocol.messageConsume,
                argumentsKeywords: consumption.toWampKeywords(),
              )
              .timeout(connectionTimeout);
          return MessageReceipt.fromWampKeywords(result.argumentsKeywords);
        },
        putAttachmentChunkCallback: (chunk) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.attachmentChunkPut,
                  argumentsKeywords: chunk.toWampKeywords(),
                )
                .timeout(connectionTimeout);
            return AttachmentChunkReceipt.fromWampKeywords(
              result.argumentsKeywords,
            );
          } on wamp.Error catch (error) {
            throw AttachmentTransferException.fromWampError(error);
          }
        },
        attachmentUploadStatusCallback:
            (messageId, attachmentId, chunkCount) async {
              try {
                final result = await session
                    .callSingle(
                      WampAppProtocol.attachmentUploadStatus,
                      argumentsKeywords: {
                        'message_id': messageId,
                        'attachment_id': attachmentId,
                        'chunk_count': chunkCount,
                      },
                    )
                    .timeout(connectionTimeout);
                return AttachmentUploadStatus.fromWampKeywords(
                  result.argumentsKeywords,
                );
              } on wamp.Error catch (error) {
                throw AttachmentTransferException.fromWampError(error);
              }
            },
        getAttachmentChunkCallback:
            (messageId, attachmentId, chunkIndex) async {
              try {
                final result = await session
                    .callSingle(
                      WampAppProtocol.attachmentChunkGet,
                      argumentsKeywords: {
                        'message_id': messageId,
                        'attachment_id': attachmentId,
                        'chunk_index': chunkIndex,
                      },
                    )
                    .timeout(connectionTimeout);
                return EncryptedAttachmentChunk.fromWampKeywords(
                  result.argumentsKeywords,
                );
              } on wamp.Error catch (error) {
                throw AttachmentTransferException.fromWampError(error);
              }
            },
        registerPlatformPushCallback: (request) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.pushRegister,
                  argumentsKeywords: request.toWampKeywords(),
                )
                .timeout(connectionTimeout);
            return PlatformPushSubscriptionReceipt.fromWampKeywords(
              result.argumentsKeywords,
            );
          } on wamp.Error catch (error) {
            throw PlatformPushSubscriptionException.fromWampError(error);
          }
        },
        unregisterPlatformPushCallback: (key) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.pushUnregister,
                  argumentsKeywords: key.toWampKeywords(),
                )
                .timeout(connectionTimeout);
            final removed = result.argumentsKeywords?['removed'];
            if (removed is! bool) {
              throw const FormatException(
                'The server returned an invalid push unregistration receipt.',
              );
            }
            return removed;
          } on wamp.Error catch (error) {
            throw PlatformPushSubscriptionException.fromWampError(error);
          }
        },
        beginBackupUploadCallback: (request) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.backupUploadBegin,
                  argumentsKeywords: request.toWampKeywords(),
                )
                .timeout(connectionTimeout);
            return BackupUploadSession.fromWampKeywords(
              result.argumentsKeywords,
            );
          } on wamp.Error catch (error) {
            throw RemoteBackupException.fromWampError(error);
          }
        },
        putBackupChunkCallback: (chunk) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.backupChunkPut,
                  argumentsKeywords: chunk.toWampKeywords(),
                )
                .timeout(connectionTimeout);
            if (result.argumentsKeywords?['upload_id'] != chunk.uploadId ||
                result.argumentsKeywords?['chunk_index'] != chunk.chunkIndex) {
              throw const FormatException(
                'The server acknowledged the wrong backup chunk.',
              );
            }
          } on wamp.Error catch (error) {
            throw RemoteBackupException.fromWampError(error);
          }
        },
        commitBackupUploadCallback: (uploadId) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.backupUploadCommit,
                  argumentsKeywords: {'upload_id': uploadId},
                )
                .timeout(connectionTimeout);
            return BackupMetadata.fromWampKeywords(result.argumentsKeywords);
          } on wamp.Error catch (error) {
            throw RemoteBackupException.fromWampError(error);
          }
        },
        getBackupMetadataCallback: () async {
          try {
            final result = await session
                .callSingle(WampAppProtocol.backupMetadataGet)
                .timeout(connectionTimeout);
            return BackupMetadata.fromWampKeywords(result.argumentsKeywords);
          } on wamp.Error catch (error) {
            final mapped = RemoteBackupException.fromWampError(error);
            if (mapped.kind == RemoteBackupFailureKind.notFound) return null;
            throw mapped;
          }
        },
        getBackupChunkCallback: (revision, chunkIndex) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.backupChunkGet,
                  argumentsKeywords: {
                    'revision': revision,
                    'chunk_index': chunkIndex,
                  },
                )
                .timeout(connectionTimeout);
            return EncryptedBackupDownloadChunk.fromWampKeywords(
              result.argumentsKeywords,
            );
          } on wamp.Error catch (error) {
            throw RemoteBackupException.fromWampError(error);
          }
        },
        deleteBackupCallback: (expectedRevision) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.backupDelete,
                  argumentsKeywords: {'expected_revision': expectedRevision},
                )
                .timeout(connectionTimeout);
            final removed = result.argumentsKeywords?['removed'];
            if (removed is! bool) {
              throw const FormatException(
                'The server returned an invalid backup deletion receipt.',
              );
            }
            return removed;
          } on wamp.Error catch (error) {
            throw RemoteBackupException.fromWampError(error);
          }
        },
        getCallConfigurationCallback: () async {
          try {
            final result = await session
                .callSingle(WampAppProtocol.callConfiguration)
                .timeout(connectionTimeout);
            return CallConfiguration.fromWampKeywords(result.argumentsKeywords);
          } on wamp.Error catch (error) {
            throw CallSignalingException.fromWampError(error);
          }
        },
        startCallCallback: (request) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.callStart,
                  argumentsKeywords: request.toWampKeywords(),
                )
                .timeout(connectionTimeout);
            return CallUpdate.fromWampKeywords(result.argumentsKeywords);
          } on wamp.Error catch (error) {
            throw CallSignalingException.fromWampError(error);
          }
        },
        acceptCallCallback: (answer) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.callAccept,
                  argumentsKeywords: answer.toWampKeywords(),
                )
                .timeout(connectionTimeout);
            return CallUpdate.fromWampKeywords(result.argumentsKeywords);
          } on wamp.Error catch (error) {
            throw CallSignalingException.fromWampError(error);
          }
        },
        sendCallSignalCallback: (signal) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.callSignal,
                  argumentsKeywords: signal.toWampKeywords(),
                )
                .timeout(connectionTimeout);
            return CallUpdate.fromWampKeywords(result.argumentsKeywords);
          } on wamp.Error catch (error) {
            throw CallSignalingException.fromWampError(error);
          }
        },
        endCallCallback: (signal) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.callEnd,
                  argumentsKeywords: signal.toWampKeywords(),
                )
                .timeout(connectionTimeout);
            return CallUpdate.fromWampKeywords(result.argumentsKeywords);
          } on wamp.Error catch (error) {
            throw CallSignalingException.fromWampError(error);
          }
        },
        syncCallsCallback: (deviceId, afterCursor, limit) async {
          try {
            final result = await session
                .callSingle(
                  WampAppProtocol.callSync,
                  argumentsKeywords: {
                    'device_id': deviceId,
                    'after_cursor': afterCursor,
                    'limit': limit,
                  },
                )
                .timeout(connectionTimeout);
            return CallBatch.fromWampKeywords(result.argumentsKeywords);
          } on wamp.Error catch (error) {
            throw CallSignalingException.fromWampError(error);
          }
        },
        callWakeups: callWakeups.stream,
        latestCallWakeupCursorCallback: () => callWakeups.latestCursor,
        latestCallWakeupErrorCallback: () => callWakeups.latestError,
        mailboxWakeups: wakeups.stream,
        latestMailboxWakeupCursorCallback: () => wakeups.latestCursor,
        latestMailboxWakeupErrorCallback: () => wakeups.latestError,
        closeTransport: () async {
          try {
            await Future.wait([wakeups.close(), callWakeups.close()]);
            await _close(client, session);
          } finally {
            await authentication.dispose();
          }
        },
      );
    } catch (_) {
      try {
        await Future.wait([wakeups.close(), callWakeups.close()]);
        await client.disconnect();
      } finally {
        await authentication.dispose();
      }
      rethrow;
    }
  }

  Future<Session> _connect(Client client) {
    return client
        .connect(
          options: ClientConnectOptions(
            reconnectCount: 0,
            reconnectTime: const Duration(milliseconds: 100),
          ),
        )
        .first
        .timeout(connectionTimeout + derivationTimeout);
  }

  Future<void> _close(Client client, Session? session) async {
    if (session != null && session.isConnected()) {
      await session.close(timeout: Duration.zero);
    }
    await client.disconnect();
  }
}

final class _MailboxWakeupFeed {
  final StreamController<MailboxWakeup> _controller =
      StreamController<MailboxWakeup>.broadcast(sync: true);
  int _latestCursor = 0;
  Object? _latestError;
  bool _closed = false;

  Stream<MailboxWakeup> get stream => _controller.stream;
  int get latestCursor => _latestCursor;
  Object? get latestError => _latestError;

  void addEvent(EventPayload event) {
    if (_closed) return;
    try {
      final wakeup = MailboxWakeup.fromWampKeywords(event.argumentsKeywords);
      if (wakeup.cursor <= _latestCursor) return;
      _latestCursor = wakeup.cursor;
      _controller.add(wakeup);
    } catch (error, stackTrace) {
      _latestError = error;
      _controller.addError(error, stackTrace);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }
}

final class _CallWakeupFeed {
  final StreamController<CallWakeup> _controller =
      StreamController<CallWakeup>.broadcast(sync: true);
  int _latestCursor = 0;
  Object? _latestError;
  bool _closed = false;

  Stream<CallWakeup> get stream => _controller.stream;
  int get latestCursor => _latestCursor;
  Object? get latestError => _latestError;

  void addEvent(EventPayload event) {
    if (_closed) return;
    try {
      final wakeup = CallWakeup.fromWampKeywords(event.argumentsKeywords);
      if (wakeup.cursor <= _latestCursor) return;
      _latestCursor = wakeup.cursor;
      _controller.add(wakeup);
    } catch (error, stackTrace) {
      _latestError = error;
      _controller.addError(error, stackTrace);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }
}
