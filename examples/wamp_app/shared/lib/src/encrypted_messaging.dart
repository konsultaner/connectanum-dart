import 'dart:convert';
import 'dart:typed_data';

import 'account_registration.dart';
import 'device_identity.dart';

final class EncryptedChatMessage {
  EncryptedChatMessage({
    required this.messageId,
    required this.conversationId,
    required String senderUsername,
    required this.senderDeviceId,
    required String recipientUsername,
    required DateTime createdAt,
    required Uint8List encryptedPayload,
    required List<WrappedConversationKey> wrappedKeys,
    this.oneTime = false,
    DateTime? expiresAt,
  }) : senderUsername = AccountRegistration.normalizeUsername(senderUsername),
       recipientUsername = AccountRegistration.normalizeUsername(
         recipientUsername,
       ),
       createdAt = createdAt.toUtc(),
       expiresAt = expiresAt?.toUtc(),
       _encryptedPayload = Uint8List.fromList(encryptedPayload),
       wrappedKeys = List<WrappedConversationKey>.unmodifiable(wrappedKeys) {
    validate();
  }

  static const version = 'wampapp-message-v1';
  static const algorithm = 'xsalsa20poly1305';
  static const maxEncryptedPayloadBytes = 1024 * 1024 + 64;
  static const maxWrappedKeys = 128;

  final String messageId;
  final String conversationId;
  final String senderUsername;
  final String senderDeviceId;
  final String recipientUsername;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool oneTime;
  final Uint8List _encryptedPayload;
  final List<WrappedConversationKey> wrappedKeys;

  Uint8List get encryptedPayload => Uint8List.fromList(_encryptedPayload);

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now.toUtc());

  void validate() {
    _validateToken(messageId, 'message_id', maxLength: 128);
    _validateToken(conversationId, 'conversation_id', maxLength: 200);
    if (senderUsername.isEmpty || recipientUsername.isEmpty) {
      throw const FormatException('Message participants are required.');
    }
    if (senderUsername == recipientUsername) {
      throw const FormatException('Direct messages require two accounts.');
    }
    _validateBase64Url(
      senderDeviceId,
      expectedBytes: 32,
      field: 'sender_device_id',
    );
    if (_encryptedPayload.length < 40 ||
        _encryptedPayload.length > maxEncryptedPayloadBytes) {
      throw const FormatException('Encrypted message payload is invalid.');
    }
    if (expiresAt != null && !expiresAt!.isAfter(createdAt)) {
      throw const FormatException('Message expiry must follow creation time.');
    }
    if (wrappedKeys.isEmpty || wrappedKeys.length > maxWrappedKeys) {
      throw const FormatException('Message wrapped-key count is invalid.');
    }
    final recipients = <String>{};
    for (final envelope in wrappedKeys) {
      envelope.validate();
      if (envelope.conversationId != conversationId ||
          envelope.senderUsername != senderUsername ||
          envelope.senderDeviceId != senderDeviceId ||
          (envelope.recipientUsername != senderUsername &&
              envelope.recipientUsername != recipientUsername)) {
        throw const FormatException(
          'Message wrapped-key identities do not match.',
        );
      }
      final recipient =
          '${envelope.recipientUsername}\n${envelope.recipientDeviceId}';
      if (!recipients.add(recipient)) {
        throw const FormatException('Message wrapped keys contain duplicates.');
      }
    }
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'version': version,
      'algorithm': algorithm,
      'message_id': messageId,
      'conversation_id': conversationId,
      'sender_username': senderUsername,
      'sender_device_id': senderDeviceId,
      'recipient_username': recipientUsername,
      'created_at': createdAt.toIso8601String(),
      if (expiresAt case final value?) 'expires_at': value.toIso8601String(),
      'one_time': oneTime,
      'encrypted_payload': encryptedPayload,
      'wrapped_keys': wrappedKeys
          .map((envelope) => envelope.toWampKeywords())
          .toList(growable: false),
    };
  }

  Map<String, dynamic> toJson() {
    final value = toWampKeywords();
    value['encrypted_payload'] = base64Url.encode(_encryptedPayload);
    return value;
  }

  factory EncryptedChatMessage.fromWampKeywords(Map<String, dynamic>? value) =>
      _fromMap(value, binaryPayload: true);

  factory EncryptedChatMessage.fromJson(Map<String, dynamic>? value) =>
      _fromMap(value, binaryPayload: false);

  static EncryptedChatMessage _fromMap(
    Map<String, dynamic>? value, {
    required bool binaryPayload,
  }) {
    if (value == null ||
        value['version'] != version ||
        value['algorithm'] != algorithm) {
      throw const FormatException('Unsupported encrypted message envelope.');
    }
    final rawKeys = value['wrapped_keys'];
    if (rawKeys is! List) {
      throw const FormatException('wrapped_keys must be a list.');
    }
    final payload = binaryPayload
        ? _readBinary(value['encrypted_payload'], 'encrypted_payload')
        : _decodeBase64Url(
            _readString(value['encrypted_payload'], 'encrypted_payload'),
            'encrypted_payload',
          );
    return EncryptedChatMessage(
      messageId: _readString(value['message_id'], 'message_id'),
      conversationId: _readString(value['conversation_id'], 'conversation_id'),
      senderUsername: _readString(value['sender_username'], 'sender_username'),
      senderDeviceId: _readString(
        value['sender_device_id'],
        'sender_device_id',
      ),
      recipientUsername: _readString(
        value['recipient_username'],
        'recipient_username',
      ),
      createdAt: _readUtcDate(value['created_at'], 'created_at'),
      expiresAt: switch (value['expires_at']) {
        null => null,
        final Object raw => _readUtcDate(raw, 'expires_at'),
      },
      oneTime: _readBool(value['one_time'], 'one_time'),
      encryptedPayload: payload,
      wrappedKeys: rawKeys
          .map((raw) {
            if (raw is! Map) {
              throw const FormatException('wrapped_keys entries must be maps.');
            }
            return WrappedConversationKey.fromWampKeywords(
              Map<String, dynamic>.from(raw),
            );
          })
          .toList(growable: false),
    );
  }
}

final class MailboxMessage {
  MailboxMessage({
    required this.cursor,
    required this.message,
    required DateTime acceptedAt,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) : acceptedAt = acceptedAt.toUtc(),
       deliveredAt = deliveredAt?.toUtc(),
       readAt = readAt?.toUtc() {
    validate();
  }

  final int cursor;
  final EncryptedChatMessage message;
  final DateTime acceptedAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  void validate() {
    if (cursor < 1) throw const FormatException('Mailbox cursor is invalid.');
    message.validate();
    if (deliveredAt != null && deliveredAt!.isBefore(acceptedAt)) {
      throw const FormatException('Delivery receipt predates acceptance.');
    }
    if (readAt != null && deliveredAt == null) {
      throw const FormatException('Read receipt requires delivery.');
    }
    if (readAt != null &&
        (readAt!.isBefore(acceptedAt) ||
            (deliveredAt != null && readAt!.isBefore(deliveredAt!)))) {
      throw const FormatException('Read receipt has invalid ordering.');
    }
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'cursor': cursor,
      'message': message.toWampKeywords(),
      'accepted_at': acceptedAt.toIso8601String(),
      if (deliveredAt case final value?)
        'delivered_at': value.toIso8601String(),
      if (readAt case final value?) 'read_at': value.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() {
    final value = toWampKeywords();
    value['message'] = message.toJson();
    return value;
  }

  factory MailboxMessage.fromWampKeywords(Map<String, dynamic>? value) =>
      _fromMap(value, binaryPayload: true);

  factory MailboxMessage.fromJson(Map<String, dynamic>? value) =>
      _fromMap(value, binaryPayload: false);

  static MailboxMessage _fromMap(
    Map<String, dynamic>? value, {
    required bool binaryPayload,
  }) {
    if (value == null || value['message'] is! Map) {
      throw const FormatException('Mailbox message is invalid.');
    }
    final rawMessage = Map<String, dynamic>.from(value['message'] as Map);
    return MailboxMessage(
      cursor: _readInt(value['cursor'], 'cursor', min: 1),
      message: binaryPayload
          ? EncryptedChatMessage.fromWampKeywords(rawMessage)
          : EncryptedChatMessage.fromJson(rawMessage),
      acceptedAt: _readUtcDate(value['accepted_at'], 'accepted_at'),
      deliveredAt: _readOptionalUtcDate(value['delivered_at'], 'delivered_at'),
      readAt: _readOptionalUtcDate(value['read_at'], 'read_at'),
    );
  }
}

final class MailboxBatch {
  MailboxBatch({
    required this.nextCursor,
    required List<MailboxMessage> messages,
  }) : messages = List<MailboxMessage>.unmodifiable(messages) {
    if (nextCursor < 0) {
      throw const FormatException('Mailbox next cursor is invalid.');
    }
    var previous = 0;
    for (final message in this.messages) {
      message.validate();
      if (message.cursor <= previous || message.cursor > nextCursor) {
        throw const FormatException('Mailbox messages are out of order.');
      }
      previous = message.cursor;
    }
  }

  final int nextCursor;
  final List<MailboxMessage> messages;

  Map<String, dynamic> toWampKeywords() => {
    'next_cursor': nextCursor,
    'messages': messages
        .map((message) => message.toWampKeywords())
        .toList(growable: false),
  };

  factory MailboxBatch.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null || value['messages'] is! List) {
      throw const FormatException('Mailbox batch is invalid.');
    }
    return MailboxBatch(
      nextCursor: _readInt(value['next_cursor'], 'next_cursor', min: 0),
      messages: (value['messages'] as List)
          .map((raw) {
            if (raw is! Map) {
              throw const FormatException('Mailbox batch entry must be a map.');
            }
            return MailboxMessage.fromWampKeywords(
              Map<String, dynamic>.from(raw),
            );
          })
          .toList(growable: false),
    );
  }
}

final class MessageSendReceipt {
  MessageSendReceipt({
    required this.messageId,
    required this.cursor,
    required DateTime acceptedAt,
    required this.duplicate,
  }) : acceptedAt = acceptedAt.toUtc() {
    _validateToken(messageId, 'message_id', maxLength: 128);
    if (cursor < 1) throw const FormatException('Message cursor is invalid.');
  }

  final String messageId;
  final int cursor;
  final DateTime acceptedAt;
  final bool duplicate;

  Map<String, dynamic> toWampKeywords() => {
    'message_id': messageId,
    'cursor': cursor,
    'accepted_at': acceptedAt.toIso8601String(),
    'duplicate': duplicate,
  };

  factory MessageSendReceipt.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Message send receipt is required.');
    }
    return MessageSendReceipt(
      messageId: _readString(value['message_id'], 'message_id'),
      cursor: _readInt(value['cursor'], 'cursor', min: 1),
      acceptedAt: _readUtcDate(value['accepted_at'], 'accepted_at'),
      duplicate: _readBool(value['duplicate'], 'duplicate'),
    );
  }
}

final class MailboxWakeup {
  MailboxWakeup({required this.cursor}) {
    if (cursor < 1) throw const FormatException('Mailbox cursor is invalid.');
  }

  final int cursor;

  Map<String, dynamic> toWampKeywords() => {'cursor': cursor};

  factory MailboxWakeup.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Mailbox wakeup is required.');
    }
    return MailboxWakeup(cursor: _readInt(value['cursor'], 'cursor', min: 1));
  }
}

final class MessageReceipt {
  MessageReceipt({
    required this.messageId,
    required this.cursor,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) : deliveredAt = deliveredAt?.toUtc(),
       readAt = readAt?.toUtc() {
    _validateToken(messageId, 'message_id', maxLength: 128);
    if (cursor < 1) throw const FormatException('Message cursor is invalid.');
    if (readAt != null && deliveredAt == null) {
      throw const FormatException('Read receipt requires delivery.');
    }
    if (readAt != null && readAt.isBefore(deliveredAt!)) {
      throw const FormatException('Read receipt predates delivery.');
    }
  }

  final String messageId;
  final int cursor;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  Map<String, dynamic> toWampKeywords() => {
    'message_id': messageId,
    'cursor': cursor,
    if (deliveredAt case final value?) 'delivered_at': value.toIso8601String(),
    if (readAt case final value?) 'read_at': value.toIso8601String(),
  };

  factory MessageReceipt.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Message receipt is required.');
    }
    return MessageReceipt(
      messageId: _readString(value['message_id'], 'message_id'),
      cursor: _readInt(value['cursor'], 'cursor', min: 1),
      deliveredAt: _readOptionalUtcDate(value['delivered_at'], 'delivered_at'),
      readAt: _readOptionalUtcDate(value['read_at'], 'read_at'),
    );
  }
}

void _validateToken(String value, String field, {required int maxLength}) {
  if (value.isEmpty || value.length > maxLength || value.trim() != value) {
    throw FormatException('$field is invalid.');
  }
}

void _validateBase64Url(
  String value, {
  required int expectedBytes,
  required String field,
}) {
  final decoded = _decodeBase64Url(value, field);
  if (decoded.length != expectedBytes) {
    throw FormatException('$field has an invalid length.');
  }
}

Uint8List _decodeBase64Url(String value, String field) {
  try {
    return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } catch (_) {
    throw FormatException('$field must be base64url.');
  }
}

Uint8List _readBinary(Object? value, String field) {
  if (value is Uint8List) return Uint8List.fromList(value);
  if (value is List<int>) return Uint8List.fromList(value);
  throw FormatException('$field must be a binary field.');
}

String _readString(Object? value, String field) {
  if (value is! String) throw FormatException('$field must be a string.');
  return value;
}

bool _readBool(Object? value, String field) {
  if (value is! bool) throw FormatException('$field must be a boolean.');
  return value;
}

int _readInt(Object? value, String field, {required int min}) {
  if (value is! int || value < min) {
    throw FormatException('$field must be an integer at least $min.');
  }
  return value;
}

DateTime _readUtcDate(Object? value, String field) {
  if (value is! String) throw FormatException('$field must be a timestamp.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !value.endsWith('Z')) {
    throw FormatException('$field must be a UTC timestamp.');
  }
  return parsed.toUtc();
}

DateTime? _readOptionalUtcDate(Object? value, String field) => switch (value) {
  null => null,
  final Object raw => _readUtcDate(raw, field),
};
