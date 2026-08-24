import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/x25519.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import '../domain/local_chat_group.dart';
import '../domain/local_chat_message.dart';
import 'device_vault.dart';

class MessageCipher {
  MessageCipher({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  EncryptedChatMessage encrypt({
    required String senderUsername,
    required String recipientUsername,
    required String text,
    required DeviceTrustSession trust,
    required List<DeviceRecord> participantDevices,
    DateTime? now,
    DateTime? expiresAt,
    bool oneTime = false,
  }) {
    final normalizedSender = AccountRegistration.normalizeUsername(
      senderUsername,
    );
    final normalizedRecipient = AccountRegistration.normalizeUsername(
      recipientUsername,
    );
    return _encrypt(
      senderUsername: normalizedSender,
      recipientUsername: normalizedRecipient,
      participantUsernames: [normalizedSender, normalizedRecipient],
      text: text,
      trust: trust,
      participantDevices: participantDevices,
      createdAt: (now ?? DateTime.now()).toUtc(),
      expiresAt: expiresAt,
      oneTime: oneTime,
    );
  }

  EncryptedChatMessage encryptGroup({
    required String senderUsername,
    required LocalChatGroup group,
    required String text,
    required DeviceTrustSession trust,
    required List<DeviceRecord> participantDevices,
    DateTime? now,
    DateTime? expiresAt,
  }) {
    group.validate();
    final normalizedSender = AccountRegistration.normalizeUsername(
      senderUsername,
    );
    if (!group.memberUsernames.contains(normalizedSender)) {
      throw const FormatException('The sender is not a group member.');
    }
    return _encrypt(
      senderUsername: normalizedSender,
      participantUsernames: group.memberUsernames,
      group: group,
      text: text,
      trust: trust,
      participantDevices: participantDevices,
      createdAt: (now ?? DateTime.now()).toUtc(),
      expiresAt: expiresAt,
      oneTime: false,
    );
  }

  EncryptedChatMessage _encrypt({
    required String senderUsername,
    required List<String> participantUsernames,
    required String text,
    required DeviceTrustSession trust,
    required List<DeviceRecord> participantDevices,
    required DateTime createdAt,
    required DateTime? expiresAt,
    required bool oneTime,
    String? recipientUsername,
    LocalChatGroup? group,
  }) {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty || normalizedText.length > 65536) {
      throw const FormatException(
        'Message text must contain 1-65536 characters.',
      );
    }
    final participants =
        participantUsernames
            .map(AccountRegistration.normalizeUsername)
            .toSet()
            .toList(growable: false)
          ..sort();
    final isGroup = group != null;
    if (isGroup != (recipientUsername == null)) {
      throw const FormatException('Message conversation metadata is invalid.');
    }
    final conversationId = isGroup
        ? group.conversationId
        : directConversationId(senderUsername, recipientUsername!);
    final messageId = _token(16);
    final key = _bytes(32);
    Uint8List? plaintext;
    try {
      plaintext = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'schema': isGroup ? 2 : 1,
            'message_id': messageId,
            'conversation_id': conversationId,
            'sender_username': senderUsername,
            if (!isGroup) 'recipient_username': recipientUsername,
            if (isGroup) 'conversation_type': ChatConversationType.group.name,
            if (isGroup) 'group': group.toJson(),
            'created_at': createdAt.toIso8601String(),
            if (expiresAt case final value?)
              'expires_at': value.toUtc().toIso8601String(),
            'one_time': oneTime,
            'text': normalizedText,
          }),
        ),
      );
      final encrypted = SecretBox(key).encrypt(plaintext).asTypedList;
      final devices = [...participantDevices]
        ..sort((left, right) {
          final account = left.username.compareTo(right.username);
          return account != 0
              ? account
              : left.deviceId.compareTo(right.deviceId);
        });
      final deviceAccounts = devices.map((device) => device.username).toSet();
      if (devices.isEmpty ||
          deviceAccounts.length != participants.length ||
          !deviceAccounts.containsAll(participants)) {
        throw const FormatException(
          'Every message participant requires an active device.',
        );
      }
      for (final device in devices) {
        if (!participants.contains(device.username)) {
          throw const FormatException(
            'Message devices contain a non-participant.',
          );
        }
      }
      final wrappedKeys = devices
          .map(
            (device) => trust.wrapConversationKey(
              conversationId: conversationId,
              recipient: device,
              conversationKey: key,
            ),
          )
          .toList(growable: false);
      return isGroup
          ? EncryptedChatMessage.group(
              messageId: messageId,
              conversationId: conversationId,
              senderUsername: senderUsername,
              senderDeviceId: trust.deviceId,
              participantUsernames: participants,
              createdAt: createdAt,
              expiresAt: expiresAt,
              encryptedPayload: encrypted,
              wrappedKeys: wrappedKeys,
            )
          : EncryptedChatMessage(
              messageId: messageId,
              conversationId: conversationId,
              senderUsername: senderUsername,
              senderDeviceId: trust.deviceId,
              recipientUsername: recipientUsername!,
              createdAt: createdAt,
              expiresAt: expiresAt,
              oneTime: oneTime,
              encryptedPayload: encrypted,
              wrappedKeys: wrappedKeys,
            );
    } finally {
      key.fillRange(0, key.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  LocalChatMessage decrypt({
    required EncryptedChatMessage message,
    required String username,
    required DeviceTrustSession trust,
    required DeviceRecord sender,
  }) {
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    final envelope = message.wrappedKeys
        .where(
          (candidate) =>
              candidate.recipientUsername == normalizedUsername &&
              candidate.recipientDeviceId == trust.deviceId,
        )
        .firstOrNull;
    if (envelope == null) {
      throw const FormatException('Message is not encrypted for this device.');
    }
    final key = trust.unwrapConversationKey(
      envelope: envelope,
      sender: sender,
      allowRevokedSender: true,
    );
    Uint8List? plaintext;
    try {
      plaintext = SecretBox(key)
          .decrypt(EncryptedMessage.fromList(message.encryptedPayload));
      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map<String, dynamic> ||
          decoded['message_id'] != message.messageId ||
          decoded['conversation_id'] != message.conversationId ||
          decoded['sender_username'] != message.senderUsername ||
          decoded['created_at'] != message.createdAt.toIso8601String() ||
          decoded['expires_at'] != message.expiresAt?.toIso8601String() ||
          decoded['one_time'] != message.oneTime ||
          decoded['text'] is! String) {
        throw const FormatException('Encrypted message metadata is invalid.');
      }
      LocalChatGroup? group;
      if (message.isGroup) {
        if (decoded['schema'] != 2 ||
            decoded['conversation_type'] != ChatConversationType.group.name ||
            decoded['group'] is! Map) {
          throw const FormatException('Encrypted group metadata is invalid.');
        }
        group = LocalChatGroup.fromJson(
          Map<String, dynamic>.from(decoded['group'] as Map),
        );
        if (group.conversationId != message.conversationId ||
            !_sameStrings(
              group.memberUsernames,
              message.participantUsernames,
            )) {
          throw const FormatException('Encrypted group metadata conflicts.');
        }
      } else if (decoded['schema'] != 1 ||
          decoded['recipient_username'] != message.recipientUsername) {
        throw const FormatException('Encrypted message metadata is invalid.');
      }
      return LocalChatMessage(
        messageId: message.messageId,
        conversationId: message.conversationId,
        peerUsername: message.isGroup
            ? message.senderUsername
            : message.senderUsername == normalizedUsername
            ? message.recipientUsername!
            : message.senderUsername,
        text: decoded['text'] as String,
        sentAt: message.createdAt,
        outgoing: message.senderUsername == normalizedUsername,
        oneTime: message.oneTime,
        expiresAt: message.expiresAt,
        groupTitle: group?.title,
        participantUsernames: group?.memberUsernames ?? const [],
        groupCreatedBy: group?.createdBy,
        groupCreatedAt: group?.createdAt,
      );
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException('Encrypted message could not be opened.');
    } finally {
      key.fillRange(0, key.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  static String directConversationId(String first, String second) {
    final participants = [
      AccountRegistration.normalizeUsername(first),
      AccountRegistration.normalizeUsername(second),
    ]..sort();
    if (participants.first.isEmpty ||
        participants.last.isEmpty ||
        participants.first == participants.last) {
      throw const FormatException(
        'Direct conversation participants are invalid.',
      );
    }
    return base64Url
        .encode(sha256.convert(utf8.encode(participants.join('\n'))).bytes)
        .replaceAll('=', '');
  }

  String newGroupConversationId() => _token(32);

  static bool _sameStrings(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  String _token(int length) =>
      base64Url.encode(_bytes(length)).replaceAll('=', '');

  Uint8List _bytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );
}
