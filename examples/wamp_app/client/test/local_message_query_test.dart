import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/domain/local_chat_message.dart';
import 'package:wamp_app/src/domain/local_message_query.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';

void main() {
  test('global search combines normalized terms across safe local fields', () {
    final messages = [
      _message(id: 'direct', text: 'Release plan', peer: 'bob'),
      _message(
        id: 'group',
        text: 'Release checklist',
        peer: 'alice',
        groupTitle: 'Launch Crew',
        participants: const ['alice', 'bob'],
      ),
      _message(id: 'other', text: 'Release notes', peer: 'carol'),
    ];

    final results = LocalMessageQuery(
      text: '  BOB   CHECKLIST ',
      readFilter: LocalMessageReadFilter.all,
    ).select(messages);

    expect(results.map((message) => message.messageId), ['group']);
  });

  test('global search includes attachment metadata', () {
    final message = _message(
      id: 'attachment',
      text: '',
      peer: 'bob',
      attachments: [_attachment('quarterly-report.pdf')],
    );

    final results = LocalMessageQuery(
      text: 'REPORT application/pdf',
      readFilter: LocalMessageReadFilter.all,
    ).select([message]);

    expect(results, [message]);
  });

  test('global search never indexes hidden incoming view-once text', () {
    final hidden = _message(
      id: 'hidden',
      text: 'private launch code',
      peer: 'bob',
      oneTime: true,
    );
    final visible = _message(
      id: 'visible',
      text: 'private launch code',
      peer: 'carol',
    );

    final byText = LocalMessageQuery(
      text: 'launch code',
      readFilter: LocalMessageReadFilter.all,
    ).select([hidden, visible]);
    final bySafeMetadata = LocalMessageQuery(
      text: 'bob',
      readFilter: LocalMessageReadFilter.all,
    ).select([hidden, visible]);

    expect(byText.map((message) => message.messageId), ['visible']);
    expect(bySafeMetadata.map((message) => message.messageId), ['hidden']);
  });

  test('read filters apply only to received messages', () {
    final unread = _message(id: 'unread', text: 'one', peer: 'bob');
    final deliveredUnread = _message(
      id: 'delivered-unread',
      text: 'two',
      peer: 'bob',
      deliveredAt: DateTime.utc(2026, 8, 25, 12, 1),
    );
    final read = _message(
      id: 'read',
      text: 'three',
      peer: 'bob',
      deliveredAt: DateTime.utc(2026, 8, 25, 12, 1),
      readAt: DateTime.utc(2026, 8, 25, 12, 2),
    );
    final outgoingRead = _message(
      id: 'outgoing-read',
      text: 'four',
      peer: 'bob',
      outgoing: true,
      deliveredAt: DateTime.utc(2026, 8, 25, 12, 1),
      readAt: DateTime.utc(2026, 8, 25, 12, 2),
    );
    final messages = [unread, deliveredUnread, read, outgoingRead];

    final unreadResults = LocalMessageQuery(
      text: '',
      readFilter: LocalMessageReadFilter.unread,
    ).select(messages);
    final readResults = LocalMessageQuery(
      text: '',
      readFilter: LocalMessageReadFilter.read,
    ).select(messages);

    expect(unreadResults.map((message) => message.messageId), [
      'unread',
      'delivered-unread',
    ]);
    expect(readResults.map((message) => message.messageId), ['read']);
  });

  test('empty search stays in scope while active search is global', () {
    final direct = _message(id: 'direct', text: 'needle', peer: 'bob');
    final group = _message(
      id: 'group',
      text: 'needle',
      peer: 'bob',
      groupTitle: 'Launch crew',
      participants: const ['alice', 'bob'],
    );

    final directScope = LocalMessageQuery(
      text: '',
      readFilter: LocalMessageReadFilter.all,
    ).select([direct, group]);
    final groupScope = LocalMessageQuery(
      text: '',
      readFilter: LocalMessageReadFilter.all,
      selectedGroupId: group.conversationId,
    ).select([direct, group]);
    final global = LocalMessageQuery(
      text: 'needle',
      readFilter: LocalMessageReadFilter.all,
      selectedGroupId: group.conversationId,
    ).select([direct, group]);

    expect(directScope, [direct]);
    expect(groupScope, [group]);
    expect(global, [direct, group]);
  });

  test('global search retains the newest bounded result window', () {
    final messages = List<LocalChatMessage>.generate(
      LocalMessageQuery.maxSearchResults + 5,
      (index) => _message(
        id: 'message-$index',
        text: 'matching text',
        peer: 'bob',
        sentAt: DateTime.utc(2026, 8, 25).add(Duration(seconds: index)),
      ),
    );

    final results = LocalMessageQuery(
      text: 'matching',
      readFilter: LocalMessageReadFilter.all,
    ).select(messages);

    expect(results, hasLength(LocalMessageQuery.maxSearchResults));
    expect(results.first.messageId, 'message-5');
    expect(results.last.messageId, 'message-204');
  });

  test('rejects a query beyond the UI and resource bound', () {
    expect(
      () => LocalMessageQuery(
        text: List<String>.filled(
          LocalMessageQuery.maxQueryLength + 1,
          'a',
        ).join(),
        readFilter: LocalMessageReadFilter.all,
      ),
      throwsFormatException,
    );
  });
}

LocalChatMessage _message({
  required String id,
  required String text,
  required String peer,
  bool outgoing = false,
  bool oneTime = false,
  DateTime? sentAt,
  DateTime? deliveredAt,
  DateTime? readAt,
  String? groupTitle,
  List<String> participants = const [],
  List<EncryptedAttachmentDescriptor> attachments = const [],
}) => LocalChatMessage(
  messageId: id,
  conversationId: groupTitle == null ? 'alice-$peer' : 'launch-crew',
  peerUsername: peer,
  text: text,
  sentAt: sentAt ?? DateTime.utc(2026, 8, 25, 12),
  outgoing: outgoing,
  oneTime: oneTime,
  deliveredAt: deliveredAt,
  readAt: readAt,
  groupTitle: groupTitle,
  participantUsernames: participants,
  groupCreatedBy: groupTitle == null ? null : 'alice',
  groupCreatedAt: groupTitle == null ? null : DateTime.utc(2026, 8, 25, 11),
  attachments: attachments,
);

EncryptedAttachmentDescriptor _attachment(String name) =>
    EncryptedAttachmentDescriptor(
      attachmentId: 'attachment_12345678',
      kind: ChatAttachmentKind.file,
      name: name,
      contentType: 'application/pdf',
      plaintextBytes: 1,
      chunkBytes: WampAppAttachmentLimits.defaultChunkBytes,
      chunkCount: 1,
      plaintextSha256: List<String>.filled(64, '0').join(),
      key: Uint8List(32),
    );
