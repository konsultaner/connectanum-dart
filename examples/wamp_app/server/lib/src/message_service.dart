import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' as ed;
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'account_store.dart';
import 'attachment_store.dart';
import 'mailbox_store.dart';

class MessageService {
  const MessageService({
    required this.accounts,
    required this.mailbox,
    this.attachments,
  });

  static const maximumClockSkew = Duration(minutes: 10);
  static const maximumLifetime = Duration(days: 30);

  final AccountStore accounts;
  final MailboxStore mailbox;
  final AttachmentStore? attachments;

  Future<DeviceDirectory> lookupDevices(
    String username, {
    bool includeRevoked = false,
  }) async {
    final normalized = AccountRegistration.normalizeUsername(username);
    if (normalized.isEmpty) {
      throw const FormatException('username is required.');
    }
    return DeviceDirectory(
      await accounts.listDevices(normalized, includeRevoked: includeRevoked),
    );
  }

  Future<MessageSendReceipt> send(
    String callerUsername,
    EncryptedChatMessage message, {
    DateTime? now,
  }) async {
    message.validate();
    final caller = AccountRegistration.normalizeUsername(callerUsername);
    if (caller != message.senderUsername) {
      throw StateError('The authenticated sender does not match the message.');
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    if (message.createdAt.isBefore(timestamp.subtract(maximumClockSkew)) ||
        message.createdAt.isAfter(timestamp.add(maximumClockSkew))) {
      throw const FormatException(
        'Message creation time is outside the limit.',
      );
    }
    if (message.isExpiredAt(timestamp) ||
        (message.expiresAt != null &&
            message.expiresAt!.isAfter(timestamp.add(maximumLifetime)))) {
      throw const FormatException('Message expiry is outside the limit.');
    }

    final deviceSnapshot = await accounts.listActiveDeviceSnapshot(
      message.participantUsernames,
    );
    final senderDevices = deviceSnapshot[message.senderUsername]!;
    final sender = senderDevices
        .where((device) => device.deviceId == message.senderDeviceId)
        .firstOrNull;
    if (sender == null) {
      throw StateError('The sending device is not active.');
    }
    for (final username in message.recipientUsernames) {
      if (deviceSnapshot[username]!.isEmpty) {
        throw StateError('A message recipient has no active device.');
      }
    }

    final activeDevices = <String, DeviceRecord>{
      for (final devices in deviceSnapshot.values)
        for (final device in devices)
          '${device.username}\n${device.deviceId}': device,
    };
    final wrappedRecipients = <String>{};
    for (final envelope in message.wrappedKeys) {
      final key =
          '${envelope.recipientUsername}\n${envelope.recipientDeviceId}';
      final recipient = activeDevices[key];
      if (recipient == null || !wrappedRecipients.add(key)) {
        throw const FormatException(
          'Message contains an unknown or duplicate wrapped-key recipient.',
        );
      }
      _verifyWrappedKey(envelope, sender);
    }
    if (wrappedRecipients.length != activeDevices.length ||
        !wrappedRecipients.containsAll(activeDevices.keys)) {
      throw const FormatException(
        'Message must encrypt its key for every active participant device.',
      );
    }

    if (message.attachmentIds.isNotEmpty) {
      final attachmentStore = attachments;
      if (attachmentStore == null) {
        throw const AttachmentIncomplete('attachment-storage-unavailable');
      }
      final result = await attachmentStore.commitMessage(
        message,
        () => mailbox.append(message, now: timestamp),
      );
      return MessageSendReceipt(
        messageId: message.messageId,
        cursor: result.message.cursor,
        acceptedAt: result.message.acceptedAt,
        duplicate: result.duplicate,
      );
    }
    final result = await mailbox.append(message, now: timestamp);
    return MessageSendReceipt(
      messageId: message.messageId,
      cursor: result.message.cursor,
      acceptedAt: result.message.acceptedAt,
      duplicate: result.duplicate,
    );
  }

  Future<MailboxReceiptUpdate> consumeOneTime(
    String callerUsername,
    OneTimeMessageConsumption consumption, {
    DateTime? now,
  }) async {
    consumption.validate();
    final caller = AccountRegistration.normalizeUsername(callerUsername);
    final account = await accounts.find(caller);
    final device = account?.devices[consumption.deviceId];
    if (device == null || device.isRevoked) {
      throw StateError('The consuming device is not active for this account.');
    }
    try {
      ed.VerifyKey(
        _decode(
          device.enrollment.signingPublicKey,
          'signing_public_key',
          expectedBytes: ed.VerifyKey.keyLength,
        ),
      ).verify(
        signature: ed.Signature(
          _decode(
            consumption.signature,
            'signature',
            expectedBytes: ed.Signature.signatureLength,
          ),
        ),
        message: Uint8List.fromList(consumption.signaturePayload(caller)),
      );
    } catch (_) {
      throw StateError('The one-time consumption signature is invalid.');
    }
    final message = await mailbox.findVisibleMessage(
      caller,
      consumption.messageId,
      now: now,
    );
    if (message == null) throw MessageNotFound(consumption.messageId);
    final attachmentStore = attachments;
    if (message.message.attachmentIds.isEmpty) {
      return mailbox.consumeOneTime(
        caller,
        consumption.deviceId,
        consumption.messageId,
        now: now,
      );
    }
    if (attachmentStore == null) {
      throw const AttachmentUnavailable('attachment-storage-unavailable');
    }
    return attachmentStore.consumeOneTimeMessage(
      message.message,
      isAlreadyConsumed: () async {
        final latest = await mailbox.findVisibleMessage(
          caller,
          consumption.messageId,
          now: now,
        );
        return latest?.recipientStateFor(caller)?.consumedAt != null;
      },
      commit: () => mailbox.consumeOneTime(
        caller,
        consumption.deviceId,
        consumption.messageId,
        now: now,
      ),
    );
  }

  Future<MailboxBatch> sync(
    String callerUsername, {
    required int afterCursor,
    int limit = 100,
    DateTime? now,
  }) {
    return mailbox.sync(
      AccountRegistration.normalizeUsername(callerUsername),
      afterCursor: afterCursor,
      limit: limit,
      now: now,
    );
  }

  Future<MailboxReceiptUpdate> markReceipt(
    String callerUsername,
    String messageId, {
    required bool read,
    DateTime? now,
  }) {
    return mailbox.markReceipt(
      AccountRegistration.normalizeUsername(callerUsername),
      messageId,
      read: read,
      now: now,
    );
  }

  void _verifyWrappedKey(WrappedConversationKey envelope, DeviceRecord sender) {
    if (envelope.senderUsername != sender.username ||
        envelope.senderDeviceId != sender.deviceId) {
      throw const FormatException('Wrapped-key sender is invalid.');
    }
    try {
      ed.VerifyKey(
        _decode(
          sender.enrollment.signingPublicKey,
          'signing_public_key',
          expectedBytes: ed.VerifyKey.keyLength,
        ),
      ).verify(
        signature: ed.Signature(
          _decode(
            envelope.signature,
            'signature',
            expectedBytes: ed.Signature.signatureLength,
          ),
        ),
        message: Uint8List.fromList(envelope.signaturePayload()),
      );
    } catch (_) {
      throw const FormatException('Wrapped-key signature is invalid.');
    }
  }
}

Uint8List _decode(String value, String field, {required int expectedBytes}) {
  try {
    final decoded = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(value)),
    );
    if (decoded.length != expectedBytes) throw const FormatException();
    return decoded;
  } catch (_) {
    throw FormatException('$field is invalid.');
  }
}
