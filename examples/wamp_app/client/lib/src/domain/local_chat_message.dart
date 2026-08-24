final class LocalChatMessage {
  LocalChatMessage({
    required this.messageId,
    required this.conversationId,
    required String peerUsername,
    required this.text,
    required DateTime sentAt,
    required this.outgoing,
    this.oneTime = false,
    DateTime? expiresAt,
    DateTime? deliveredAt,
    DateTime? readAt,
  }) : peerUsername = peerUsername.trim().toLowerCase(),
       sentAt = sentAt.toUtc(),
       expiresAt = expiresAt?.toUtc(),
       deliveredAt = deliveredAt?.toUtc(),
       readAt = readAt?.toUtc() {
    validate();
  }

  final String messageId;
  final String conversationId;
  final String peerUsername;
  final String text;
  final DateTime sentAt;
  final bool outgoing;
  final bool oneTime;
  final DateTime? expiresAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now.toUtc());

  void validate() {
    if (messageId.isEmpty ||
        messageId.length > 128 ||
        conversationId.isEmpty ||
        conversationId.length > 200 ||
        peerUsername.isEmpty ||
        peerUsername.length > 64 ||
        text.trim().isEmpty ||
        text.length > 65536) {
      throw const FormatException('Local chat message is invalid.');
    }
    if (expiresAt != null && !expiresAt!.isAfter(sentAt)) {
      throw const FormatException('Local message expiry is invalid.');
    }
    if (readAt != null && deliveredAt == null) {
      throw const FormatException('Local read receipt requires delivery.');
    }
    if (readAt != null && readAt!.isBefore(deliveredAt!)) {
      throw const FormatException('Local receipt ordering is invalid.');
    }
  }

  LocalChatMessage withReceipts({DateTime? deliveredAt, DateTime? readAt}) =>
      LocalChatMessage(
        messageId: messageId,
        conversationId: conversationId,
        peerUsername: peerUsername,
        text: text,
        sentAt: sentAt,
        outgoing: outgoing,
        oneTime: oneTime,
        expiresAt: expiresAt,
        deliveredAt: deliveredAt ?? this.deliveredAt,
        readAt: readAt ?? this.readAt,
      );

  Map<String, dynamic> toJson() => {
    'message_id': messageId,
    'conversation_id': conversationId,
    'peer_username': peerUsername,
    'text': text,
    'sent_at': sentAt.toIso8601String(),
    'outgoing': outgoing,
    'one_time': oneTime,
    if (expiresAt case final value?) 'expires_at': value.toIso8601String(),
    if (deliveredAt case final value?) 'delivered_at': value.toIso8601String(),
    if (readAt case final value?) 'read_at': value.toIso8601String(),
  };

  factory LocalChatMessage.fromJson(Map<String, dynamic> value) {
    return LocalChatMessage(
      messageId: _string(value['message_id']),
      conversationId: _string(value['conversation_id']),
      peerUsername: _string(value['peer_username']),
      text: _string(value['text']),
      sentAt: _date(value['sent_at']),
      outgoing: _boolean(value['outgoing']),
      oneTime: _boolean(value['one_time']),
      expiresAt: _optionalDate(value['expires_at']),
      deliveredAt: _optionalDate(value['delivered_at']),
      readAt: _optionalDate(value['read_at']),
    );
  }
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected a string.');
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) throw const FormatException('Expected a boolean.');
  return value;
}

DateTime _date(Object? value) {
  if (value is! String || !value.endsWith('Z')) {
    throw const FormatException('Expected a UTC timestamp.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('Timestamp is invalid.');
  return parsed.toUtc();
}

DateTime? _optionalDate(Object? value) => value == null ? null : _date(value);
