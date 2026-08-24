import 'dart:convert';
import 'dart:typed_data';

import 'account_registration.dart';
import 'device_identity.dart';

enum ChatConversationType { direct, group }

final class EncryptedChatMessage {
  factory EncryptedChatMessage({
    required String messageId,
    required String conversationId,
    required String senderUsername,
    required String senderDeviceId,
    required String recipientUsername,
    required DateTime createdAt,
    required Uint8List encryptedPayload,
    required List<WrappedConversationKey> wrappedKeys,
    bool oneTime = false,
    DateTime? expiresAt,
  }) {
    final sender = AccountRegistration.normalizeUsername(senderUsername);
    final recipient = AccountRegistration.normalizeUsername(recipientUsername);
    return EncryptedChatMessage._(
      messageId: messageId,
      conversationId: conversationId,
      conversationType: ChatConversationType.direct,
      senderUsername: sender,
      senderDeviceId: senderDeviceId,
      recipientUsername: recipient,
      participantUsernames: _normalizedParticipants([sender, recipient]),
      createdAt: createdAt,
      expiresAt: expiresAt,
      oneTime: oneTime,
      encryptedPayload: encryptedPayload,
      wrappedKeys: wrappedKeys,
    );
  }

  factory EncryptedChatMessage.group({
    required String messageId,
    required String conversationId,
    required String senderUsername,
    required String senderDeviceId,
    required List<String> participantUsernames,
    required DateTime createdAt,
    required Uint8List encryptedPayload,
    required List<WrappedConversationKey> wrappedKeys,
    DateTime? expiresAt,
  }) {
    final sender = AccountRegistration.normalizeUsername(senderUsername);
    return EncryptedChatMessage._(
      messageId: messageId,
      conversationId: conversationId,
      conversationType: ChatConversationType.group,
      senderUsername: sender,
      senderDeviceId: senderDeviceId,
      participantUsernames: _normalizedParticipants(participantUsernames),
      createdAt: createdAt,
      expiresAt: expiresAt,
      oneTime: false,
      encryptedPayload: encryptedPayload,
      wrappedKeys: wrappedKeys,
    );
  }

  EncryptedChatMessage._({
    required this.messageId,
    required this.conversationId,
    required this.conversationType,
    required this.senderUsername,
    required this.senderDeviceId,
    required List<String> participantUsernames,
    required DateTime createdAt,
    required Uint8List encryptedPayload,
    required List<WrappedConversationKey> wrappedKeys,
    required this.oneTime,
    this.recipientUsername,
    DateTime? expiresAt,
  }) : createdAt = createdAt.toUtc(),
       expiresAt = expiresAt?.toUtc(),
       _encryptedPayload = Uint8List.fromList(encryptedPayload),
       wrappedKeys = List<WrappedConversationKey>.unmodifiable(wrappedKeys),
       participantUsernames = List<String>.unmodifiable(participantUsernames) {
    validate();
  }

  static const version = 'wampapp-message-v1';
  static const groupVersion = 'wampapp-message-v2';
  static const algorithm = 'xsalsa20poly1305';
  static const maxEncryptedPayloadBytes = 1024 * 1024 + 64;
  static const maxWrappedKeys = 128;
  static const maxParticipantUsernames = 32;

  final String messageId;
  final String conversationId;
  final ChatConversationType conversationType;
  final String senderUsername;
  final String senderDeviceId;
  final String? recipientUsername;
  final List<String> participantUsernames;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool oneTime;
  final Uint8List _encryptedPayload;
  final List<WrappedConversationKey> wrappedKeys;

  bool get isGroup => conversationType == ChatConversationType.group;

  List<String> get recipientUsernames => List<String>.unmodifiable(
    participantUsernames.where((username) => username != senderUsername),
  );

  Uint8List get encryptedPayload => Uint8List.fromList(_encryptedPayload);

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now.toUtc());

  void validate() {
    _validateToken(messageId, 'message_id', maxLength: 128);
    _validateToken(conversationId, 'conversation_id', maxLength: 200);
    if (senderUsername.isEmpty ||
        participantUsernames.length < 2 ||
        participantUsernames.length > maxParticipantUsernames ||
        !participantUsernames.contains(senderUsername)) {
      throw const FormatException('Message participants are invalid.');
    }
    for (var index = 0; index < participantUsernames.length; index += 1) {
      final username = participantUsernames[index];
      if (username.isEmpty ||
          (index > 0 &&
              participantUsernames[index - 1].compareTo(username) >= 0)) {
        throw const FormatException(
          'Message participants must be sorted and unique.',
        );
      }
    }
    if (isGroup) {
      if (recipientUsername != null || oneTime) {
        throw const FormatException(
          'Group messages cannot use a direct recipient or view-once.',
        );
      }
    } else {
      final recipient = recipientUsername;
      if (recipient == null ||
          recipient == senderUsername ||
          participantUsernames.length != 2 ||
          !participantUsernames.contains(recipient)) {
        throw const FormatException('Direct message participants are invalid.');
      }
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
    final wrappedAccounts = <String>{};
    for (final envelope in wrappedKeys) {
      envelope.validate();
      if (envelope.conversationId != conversationId ||
          envelope.senderUsername != senderUsername ||
          envelope.senderDeviceId != senderDeviceId ||
          !participantUsernames.contains(envelope.recipientUsername)) {
        throw const FormatException(
          'Message wrapped-key identities do not match.',
        );
      }
      final recipient =
          '${envelope.recipientUsername}\n${envelope.recipientDeviceId}';
      if (!recipients.add(recipient)) {
        throw const FormatException('Message wrapped keys contain duplicates.');
      }
      wrappedAccounts.add(envelope.recipientUsername);
    }
    if (isGroup && !wrappedAccounts.containsAll(participantUsernames)) {
      throw const FormatException(
        'Group messages require a wrapped key for every participant.',
      );
    }
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'version': isGroup ? groupVersion : version,
      'algorithm': algorithm,
      'message_id': messageId,
      'conversation_id': conversationId,
      'conversation_type': conversationType.name,
      'sender_username': senderUsername,
      'sender_device_id': senderDeviceId,
      'recipient_username': ?recipientUsername,
      if (isGroup) 'participant_usernames': participantUsernames,
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
    if (value == null || value['algorithm'] != algorithm) {
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
    final wrappedKeys = rawKeys
        .map((raw) {
          if (raw is! Map) {
            throw const FormatException('wrapped_keys entries must be maps.');
          }
          return WrappedConversationKey.fromWampKeywords(
            Map<String, dynamic>.from(raw),
          );
        })
        .toList(growable: false);
    final envelopeVersion = value['version'];
    if (envelopeVersion == version) {
      final type = value['conversation_type'];
      if (type != null && type != ChatConversationType.direct.name) {
        throw const FormatException('Direct message type is invalid.');
      }
      return EncryptedChatMessage(
        messageId: _readString(value['message_id'], 'message_id'),
        conversationId: _readString(
          value['conversation_id'],
          'conversation_id',
        ),
        senderUsername: _readString(
          value['sender_username'],
          'sender_username',
        ),
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
        wrappedKeys: wrappedKeys,
      );
    }
    if (envelopeVersion != groupVersion ||
        value['conversation_type'] != ChatConversationType.group.name ||
        value['recipient_username'] != null ||
        _readBool(value['one_time'], 'one_time')) {
      throw const FormatException('Unsupported encrypted message envelope.');
    }
    final rawParticipants = value['participant_usernames'];
    if (rawParticipants is! List) {
      throw const FormatException('participant_usernames must be a list.');
    }
    return EncryptedChatMessage.group(
      messageId: _readString(value['message_id'], 'message_id'),
      conversationId: _readString(value['conversation_id'], 'conversation_id'),
      senderUsername: _readString(value['sender_username'], 'sender_username'),
      senderDeviceId: _readString(
        value['sender_device_id'],
        'sender_device_id',
      ),
      participantUsernames: rawParticipants
          .map((raw) => _readString(raw, 'participant_usernames'))
          .toList(growable: false),
      createdAt: _readUtcDate(value['created_at'], 'created_at'),
      expiresAt: switch (value['expires_at']) {
        null => null,
        final Object raw => _readUtcDate(raw, 'expires_at'),
      },
      encryptedPayload: payload,
      wrappedKeys: wrappedKeys,
    );
  }

  static List<String> _normalizedParticipants(Iterable<String> usernames) {
    final normalized =
        usernames
            .map(AccountRegistration.normalizeUsername)
            .toSet()
            .toList(growable: false)
          ..sort();
    return normalized;
  }
}

final class MailboxRecipientState {
  MailboxRecipientState({
    DateTime? deliveredAt,
    DateTime? readAt,
    DateTime? consumedAt,
    this.consumedByDeviceId,
  }) : deliveredAt = deliveredAt?.toUtc(),
       readAt = readAt?.toUtc(),
       consumedAt = consumedAt?.toUtc();

  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? consumedAt;
  final String? consumedByDeviceId;

  void validate({required DateTime acceptedAt, required bool oneTime}) {
    if (deliveredAt != null && deliveredAt!.isBefore(acceptedAt)) {
      throw const FormatException('Delivery receipt predates acceptance.');
    }
    if (readAt != null && deliveredAt == null) {
      throw const FormatException('Read receipt requires delivery.');
    }
    if (readAt != null &&
        (readAt!.isBefore(acceptedAt) || readAt!.isBefore(deliveredAt!))) {
      throw const FormatException('Read receipt has invalid ordering.');
    }
    if ((consumedAt == null) != (consumedByDeviceId == null)) {
      throw const FormatException('One-time consumption state is incomplete.');
    }
    if (consumedAt != null) {
      if (!oneTime || readAt == null || consumedAt != readAt) {
        throw const FormatException('One-time consumption state is invalid.');
      }
      _validateBase64Url(
        consumedByDeviceId!,
        expectedBytes: 32,
        field: 'consumed_by_device_id',
      );
    }
  }

  Map<String, dynamic> toWampKeywords() => {
    if (deliveredAt case final value?) 'delivered_at': value.toIso8601String(),
    if (readAt case final value?) 'read_at': value.toIso8601String(),
    if (consumedAt case final value?) 'consumed_at': value.toIso8601String(),
    'consumed_by_device_id': ?consumedByDeviceId,
  };

  factory MailboxRecipientState.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Mailbox recipient state is required.');
    }
    return MailboxRecipientState(
      deliveredAt: _readOptionalUtcDate(value['delivered_at'], 'delivered_at'),
      readAt: _readOptionalUtcDate(value['read_at'], 'read_at'),
      consumedAt: _readOptionalUtcDate(value['consumed_at'], 'consumed_at'),
      consumedByDeviceId: switch (value['consumed_by_device_id']) {
        null => null,
        final Object raw => _readString(raw, 'consumed_by_device_id'),
      },
    );
  }
}

final class MailboxMessage {
  factory MailboxMessage({
    required int cursor,
    required EncryptedChatMessage message,
    required DateTime acceptedAt,
    DateTime? deliveredAt,
    DateTime? readAt,
    DateTime? consumedAt,
    String? consumedByDeviceId,
    Map<String, MailboxRecipientState> recipientStates = const {},
  }) {
    if (recipientStates.isNotEmpty &&
        (deliveredAt != null ||
            readAt != null ||
            consumedAt != null ||
            consumedByDeviceId != null)) {
      throw const FormatException(
        'Mailbox records cannot mix legacy and recipient receipt state.',
      );
    }
    final states = <String, MailboxRecipientState>{};
    for (final entry in recipientStates.entries) {
      final username = AccountRegistration.normalizeUsername(entry.key);
      if (username.isEmpty || states.containsKey(username)) {
        throw const FormatException('Mailbox receipt username is invalid.');
      }
      states[username] = entry.value;
    }
    if (states.isEmpty &&
        (deliveredAt != null ||
            readAt != null ||
            consumedAt != null ||
            consumedByDeviceId != null)) {
      final recipient = message.recipientUsername;
      if (recipient == null) {
        throw const FormatException(
          'Legacy receipt state requires a direct message.',
        );
      }
      states[recipient] = MailboxRecipientState(
        deliveredAt: deliveredAt,
        readAt: readAt,
        consumedAt: consumedAt,
        consumedByDeviceId: consumedByDeviceId,
      );
    }
    return MailboxMessage._(
      cursor: cursor,
      message: message,
      acceptedAt: acceptedAt,
      recipientStates: states,
    );
  }

  MailboxMessage._({
    required this.cursor,
    required this.message,
    required DateTime acceptedAt,
    required Map<String, MailboxRecipientState> recipientStates,
  }) : acceptedAt = acceptedAt.toUtc(),
       recipientStates = Map<String, MailboxRecipientState>.unmodifiable(
         recipientStates,
       ) {
    validate();
  }

  final int cursor;
  final EncryptedChatMessage message;
  final DateTime acceptedAt;
  final Map<String, MailboxRecipientState> recipientStates;

  MailboxRecipientState? recipientStateFor(String username) =>
      recipientStates[AccountRegistration.normalizeUsername(username)];

  DateTime? get deliveredAt => message.recipientUsername == null
      ? null
      : recipientStates[message.recipientUsername!]?.deliveredAt;

  DateTime? get readAt => message.recipientUsername == null
      ? null
      : recipientStates[message.recipientUsername!]?.readAt;

  DateTime? get consumedAt => message.recipientUsername == null
      ? null
      : recipientStates[message.recipientUsername!]?.consumedAt;

  String? get consumedByDeviceId => message.recipientUsername == null
      ? null
      : recipientStates[message.recipientUsername!]?.consumedByDeviceId;

  DateTime? deliveredAtFor(String viewerUsername) =>
      _aggregateFor(viewerUsername, (state) => state.deliveredAt);

  DateTime? readAtFor(String viewerUsername) =>
      _aggregateFor(viewerUsername, (state) => state.readAt);

  DateTime? _aggregateFor(
    String viewerUsername,
    DateTime? Function(MailboxRecipientState state) select,
  ) {
    final viewer = AccountRegistration.normalizeUsername(viewerUsername);
    if (viewer != message.senderUsername) {
      final state = recipientStates[viewer];
      return state == null ? null : select(state);
    }
    DateTime? aggregate;
    for (final username in message.recipientUsernames) {
      final state = recipientStates[username];
      if (state == null) return null;
      final value = select(state);
      if (value == null) return null;
      if (aggregate == null || value.isAfter(aggregate)) aggregate = value;
    }
    return aggregate;
  }

  void validate() {
    if (cursor < 1) throw const FormatException('Mailbox cursor is invalid.');
    message.validate();
    final recipients = message.recipientUsernames.toSet();
    for (final entry in recipientStates.entries) {
      if (!recipients.contains(entry.key)) {
        throw const FormatException(
          'Mailbox receipt belongs to a non-recipient.',
        );
      }
      entry.value.validate(acceptedAt: acceptedAt, oneTime: message.oneTime);
    }
  }

  Map<String, dynamic> toWampKeywords() {
    validate();
    return {
      'cursor': cursor,
      'message': message.toWampKeywords(),
      'accepted_at': acceptedAt.toIso8601String(),
      if (recipientStates.isNotEmpty)
        'recipient_receipts': recipientStates.map(
          (username, state) => MapEntry(username, state.toWampKeywords()),
        ),
      if (deliveredAt case final value?)
        'delivered_at': value.toIso8601String(),
      if (readAt case final value?) 'read_at': value.toIso8601String(),
      if (consumedAt case final value?) 'consumed_at': value.toIso8601String(),
      'consumed_by_device_id': ?consumedByDeviceId,
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
    final message = binaryPayload
        ? EncryptedChatMessage.fromWampKeywords(rawMessage)
        : EncryptedChatMessage.fromJson(rawMessage);
    final rawStates = value['recipient_receipts'];
    if (rawStates != null && rawStates is! Map) {
      throw const FormatException('recipient_receipts must be a map.');
    }
    final states = <String, MailboxRecipientState>{};
    if (rawStates is Map) {
      for (final entry in rawStates.entries) {
        if (entry.key is! String || entry.value is! Map) {
          throw const FormatException(
            'recipient_receipts entries are invalid.',
          );
        }
        states[entry.key as String] = MailboxRecipientState.fromWampKeywords(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
    }
    return MailboxMessage(
      cursor: _readInt(value['cursor'], 'cursor', min: 1),
      message: message,
      acceptedAt: _readUtcDate(value['accepted_at'], 'accepted_at'),
      recipientStates: states,
      deliveredAt: rawStates == null
          ? _readOptionalUtcDate(value['delivered_at'], 'delivered_at')
          : null,
      readAt: rawStates == null
          ? _readOptionalUtcDate(value['read_at'], 'read_at')
          : null,
      consumedAt: rawStates == null
          ? _readOptionalUtcDate(value['consumed_at'], 'consumed_at')
          : null,
      consumedByDeviceId: rawStates == null
          ? switch (value['consumed_by_device_id']) {
              null => null,
              final Object raw => _readString(raw, 'consumed_by_device_id'),
            }
          : null,
    );
  }
}

final class MailboxBatch {
  MailboxBatch({
    required this.nextCursor,
    required List<MailboxMessage> messages,
  }) : messages = List<MailboxMessage>.unmodifiable(messages) {
    if (nextCursor < 0 || messages.length > maxMessages) {
      throw const FormatException('Mailbox batch is invalid.');
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

  static const maxMessages = 500;

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
    String? recipientUsername,
    DateTime? deliveredAt,
    DateTime? readAt,
    DateTime? consumedAt,
  }) : recipientUsername = recipientUsername == null
           ? null
           : AccountRegistration.normalizeUsername(recipientUsername),
       deliveredAt = deliveredAt?.toUtc(),
       readAt = readAt?.toUtc(),
       consumedAt = consumedAt?.toUtc() {
    _validateToken(messageId, 'message_id', maxLength: 128);
    if (cursor < 1) throw const FormatException('Message cursor is invalid.');
    if (this.recipientUsername case final username?) {
      if (username.isEmpty) {
        throw const FormatException('Receipt recipient is invalid.');
      }
    }
    if (readAt != null && deliveredAt == null) {
      throw const FormatException('Read receipt requires delivery.');
    }
    if (readAt != null && readAt.isBefore(deliveredAt!)) {
      throw const FormatException('Read receipt predates delivery.');
    }
    if (consumedAt != null && (readAt == null || consumedAt != readAt)) {
      throw const FormatException(
        'Consumed receipt requires matching read time.',
      );
    }
  }

  final String messageId;
  final int cursor;
  final String? recipientUsername;
  final DateTime? deliveredAt;
  final DateTime? readAt;
  final DateTime? consumedAt;

  Map<String, dynamic> toWampKeywords() => {
    'message_id': messageId,
    'cursor': cursor,
    'recipient_username': ?recipientUsername,
    if (deliveredAt case final value?) 'delivered_at': value.toIso8601String(),
    if (readAt case final value?) 'read_at': value.toIso8601String(),
    if (consumedAt case final value?) 'consumed_at': value.toIso8601String(),
  };

  factory MessageReceipt.fromWampKeywords(Map<String, dynamic>? value) {
    if (value == null) {
      throw const FormatException('Message receipt is required.');
    }
    return MessageReceipt(
      messageId: _readString(value['message_id'], 'message_id'),
      cursor: _readInt(value['cursor'], 'cursor', min: 1),
      recipientUsername: switch (value['recipient_username']) {
        null => null,
        final Object raw => _readString(raw, 'recipient_username'),
      },
      deliveredAt: _readOptionalUtcDate(value['delivered_at'], 'delivered_at'),
      readAt: _readOptionalUtcDate(value['read_at'], 'read_at'),
      consumedAt: _readOptionalUtcDate(value['consumed_at'], 'consumed_at'),
    );
  }
}

final class OneTimeMessageConsumption {
  OneTimeMessageConsumption({
    required this.messageId,
    required this.deviceId,
    required this.signature,
  }) {
    validate();
  }

  static const signatureVersion = 'wampapp-consume-v1';

  final String messageId;
  final String deviceId;
  final String signature;

  void validate() {
    _validateToken(messageId, 'message_id', maxLength: 128);
    _validateBase64Url(deviceId, expectedBytes: 32, field: 'device_id');
    _validateBase64Url(signature, expectedBytes: 64, field: 'signature');
  }

  List<int> signaturePayload(String username) => signaturePayloadFor(
    username: username,
    messageId: messageId,
    deviceId: deviceId,
  );

  static List<int> signaturePayloadFor({
    required String username,
    required String messageId,
    required String deviceId,
  }) {
    final normalizedUsername = AccountRegistration.normalizeUsername(username);
    if (normalizedUsername.isEmpty) {
      throw const FormatException('Consumption username is required.');
    }
    _validateToken(messageId, 'message_id', maxLength: 128);
    _validateBase64Url(deviceId, expectedBytes: 32, field: 'device_id');
    return utf8.encode(
      <String>[
        signatureVersion,
        normalizedUsername,
        messageId,
        deviceId,
      ].join('\n'),
    );
  }

  Map<String, dynamic> toWampKeywords() => {
    'message_id': messageId,
    'device_id': deviceId,
    'signature': signature,
  };

  factory OneTimeMessageConsumption.fromWampKeywords(
    Map<String, dynamic>? value,
  ) {
    if (value == null) {
      throw const FormatException('One-time consumption proof is required.');
    }
    return OneTimeMessageConsumption(
      messageId: _readString(value['message_id'], 'message_id'),
      deviceId: _readString(value['device_id'], 'device_id'),
      signature: _readString(value['signature'], 'signature'),
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
