import 'local_chat_message.dart';

enum LocalMessageReadFilter { all, unread, read }

final class LocalMessageQuery {
  LocalMessageQuery({
    required String text,
    required this.readFilter,
    this.selectedGroupId,
  }) : text = _validatedText(text);

  static const maxQueryLength = 200;
  static const maxSearchResults = 200;

  final String text;
  final LocalMessageReadFilter readFilter;
  final String? selectedGroupId;

  bool get isGlobalSearch => text.isNotEmpty;

  List<LocalChatMessage> select(List<LocalChatMessage> messages) {
    final terms = text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    final newestFirst = <LocalChatMessage>[];
    for (var index = messages.length - 1; index >= 0; index -= 1) {
      final message = messages[index];
      if (!_matchesReadFilter(message) ||
          (!_matchesScope(message) && terms.isEmpty) ||
          (terms.isNotEmpty && !_matchesTerms(message, terms))) {
        continue;
      }
      newestFirst.add(message);
      if (terms.isNotEmpty && newestFirst.length == maxSearchResults) break;
    }
    return List<LocalChatMessage>.unmodifiable(newestFirst.reversed);
  }

  bool _matchesReadFilter(LocalChatMessage message) => switch (readFilter) {
    LocalMessageReadFilter.all => true,
    LocalMessageReadFilter.unread =>
      !message.outgoing && message.readAt == null,
    LocalMessageReadFilter.read => !message.outgoing && message.readAt != null,
  };

  bool _matchesScope(LocalChatMessage message) => switch (selectedGroupId) {
    final groupId? => message.isGroup && message.conversationId == groupId,
    null => !message.isGroup,
  };

  bool _matchesTerms(LocalChatMessage message, List<String> terms) {
    final searchableFields = <String>[
      if (!message.oneTime || message.outgoing) message.text,
      message.peerUsername,
      ?message.groupTitle,
      ...message.participantUsernames,
      ?message.groupCreatedBy,
      for (final attachment in message.attachments) ...[
        attachment.name,
        attachment.contentType,
      ],
    ].map((field) => field.toLowerCase()).toList(growable: false);
    return terms.every(
      (term) => searchableFields.any((field) => field.contains(term)),
    );
  }
}

String _validatedText(String value) {
  if (value.length > LocalMessageQuery.maxQueryLength) {
    throw const FormatException('Local message search query is too long.');
  }
  return value.trim();
}
