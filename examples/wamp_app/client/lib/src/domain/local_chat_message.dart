import 'package:wamp_app_protocol/wamp_app_protocol.dart';

import 'local_chat_group.dart';

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
    String? groupTitle,
    Iterable<String> participantUsernames = const [],
    String? groupCreatedBy,
    DateTime? groupCreatedAt,
    Iterable<EncryptedAttachmentDescriptor> attachments = const [],
  }) : peerUsername = peerUsername.trim().toLowerCase(),
       sentAt = sentAt.toUtc(),
       expiresAt = expiresAt?.toUtc(),
       deliveredAt = deliveredAt?.toUtc(),
       readAt = readAt?.toUtc(),
       groupTitle = groupTitle?.trim(),
       participantUsernames = List<String>.unmodifiable(
         (participantUsernames
               .map((value) => value.trim().toLowerCase())
               .toSet()
               .toList(growable: false))
           ..sort(),
       ),
       groupCreatedBy = groupCreatedBy?.trim().toLowerCase(),
       groupCreatedAt = groupCreatedAt?.toUtc(),
       attachments = List<EncryptedAttachmentDescriptor>.unmodifiable(
         attachments.toList(growable: false)..sort(
           (left, right) => left.attachmentId.compareTo(right.attachmentId),
         ),
       ) {
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
  final String? groupTitle;
  final List<String> participantUsernames;
  final String? groupCreatedBy;
  final DateTime? groupCreatedAt;
  final List<EncryptedAttachmentDescriptor> attachments;

  bool get isGroup => groupTitle != null;

  LocalChatGroup? get group => !isGroup
      ? null
      : LocalChatGroup(
          conversationId: conversationId,
          title: groupTitle!,
          memberUsernames: participantUsernames,
          createdBy: groupCreatedBy!,
          createdAt: groupCreatedAt!,
        );

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now.toUtc());

  void validate() {
    if (messageId.isEmpty ||
        messageId.length > 128 ||
        conversationId.isEmpty ||
        conversationId.length > 200 ||
        peerUsername.isEmpty ||
        peerUsername.length > 64 ||
        (text.trim().isEmpty && attachments.isEmpty) ||
        text.length > 65536) {
      throw const FormatException('Local chat message is invalid.');
    }
    if (attachments.length > WampAppAttachmentLimits.maxAttachmentsPerMessage) {
      throw const FormatException('Local attachment count is invalid.');
    }
    for (var index = 0; index < attachments.length; index += 1) {
      attachments[index].validate();
      if (index > 0 &&
          attachments[index - 1].attachmentId ==
              attachments[index].attachmentId) {
        throw const FormatException('Local attachment identifiers conflict.');
      }
    }
    final groupFields = [
      groupTitle,
      groupCreatedBy,
      groupCreatedAt,
    ].where((value) => value != null).length;
    if (groupFields != 0 && groupFields != 3) {
      throw const FormatException(
        'Local group message metadata is incomplete.',
      );
    }
    if (isGroup) {
      if (oneTime) {
        throw const FormatException('Group messages cannot be view-once.');
      }
      group!.validate();
    } else if (participantUsernames.isNotEmpty) {
      throw const FormatException(
        'Direct messages cannot contain group participants.',
      );
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
        groupTitle: groupTitle,
        participantUsernames: participantUsernames,
        groupCreatedBy: groupCreatedBy,
        groupCreatedAt: groupCreatedAt,
        attachments: attachments,
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
    'group_title': ?groupTitle,
    if (participantUsernames.isNotEmpty)
      'participant_usernames': participantUsernames,
    'group_created_by': ?groupCreatedBy,
    if (groupCreatedAt case final value?)
      'group_created_at': value.toIso8601String(),
    if (attachments.isNotEmpty)
      'attachments': attachments
          .map((attachment) => attachment.toJson())
          .toList(growable: false),
  };

  factory LocalChatMessage.fromJson(Map<String, dynamic> value) {
    final rawParticipants = value['participant_usernames'];
    final rawAttachments = value['attachments'];
    if (rawParticipants != null && rawParticipants is! List) {
      throw const FormatException('Group participants must be a list.');
    }
    if (rawAttachments != null && rawAttachments is! List) {
      throw const FormatException('Message attachments must be a list.');
    }
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
      groupTitle: switch (value['group_title']) {
        null => null,
        final Object raw => _string(raw),
      },
      participantUsernames:
          rawParticipants
              ?.map<String>((raw) => _string(raw))
              .toList(growable: false) ??
          const [],
      groupCreatedBy: switch (value['group_created_by']) {
        null => null,
        final Object raw => _string(raw),
      },
      groupCreatedAt: _optionalDate(value['group_created_at']),
      attachments:
          rawAttachments
              ?.map<EncryptedAttachmentDescriptor>(
                (raw) => EncryptedAttachmentDescriptor.fromJson(
                  raw is Map ? Map<String, dynamic>.from(raw) : null,
                ),
              )
              .toList(growable: false) ??
          const [],
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
