import 'package:wamp_app_protocol/wamp_app_protocol.dart';

final class LocalChatGroup {
  factory LocalChatGroup({
    required String conversationId,
    required String title,
    required Iterable<String> memberUsernames,
    required String createdBy,
    required DateTime createdAt,
  }) {
    final members =
        memberUsernames
            .map(AccountRegistration.normalizeUsername)
            .toSet()
            .toList(growable: false)
          ..sort();
    return LocalChatGroup._(
      conversationId: conversationId,
      title: title.trim(),
      memberUsernames: members,
      createdBy: AccountRegistration.normalizeUsername(createdBy),
      createdAt: createdAt.toUtc(),
    );
  }

  LocalChatGroup._({
    required this.conversationId,
    required this.title,
    required List<String> memberUsernames,
    required this.createdBy,
    required this.createdAt,
  }) : memberUsernames = List<String>.unmodifiable(memberUsernames) {
    validate();
  }

  static const maxGroups = 256;
  static const maxTitleLength = 100;

  final String conversationId;
  final String title;
  final List<String> memberUsernames;
  final String createdBy;
  final DateTime createdAt;

  void validate() {
    if (conversationId.isEmpty ||
        conversationId.length > 200 ||
        title.isEmpty ||
        title.length > maxTitleLength ||
        memberUsernames.length < 2 ||
        memberUsernames.length > EncryptedChatMessage.maxParticipantUsernames ||
        createdBy.isEmpty ||
        !memberUsernames.contains(createdBy)) {
      throw const FormatException('Local group metadata is invalid.');
    }
    for (var index = 0; index < memberUsernames.length; index += 1) {
      final username = memberUsernames[index];
      if (username.isEmpty ||
          (index > 0 && memberUsernames[index - 1].compareTo(username) >= 0)) {
        throw const FormatException(
          'Local group members must be sorted and unique.',
        );
      }
    }
  }

  bool hasSameDefinition(LocalChatGroup other) {
    if (conversationId != other.conversationId ||
        title != other.title ||
        createdBy != other.createdBy ||
        createdAt != other.createdAt ||
        memberUsernames.length != other.memberUsernames.length) {
      return false;
    }
    for (var index = 0; index < memberUsernames.length; index += 1) {
      if (memberUsernames[index] != other.memberUsernames[index]) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
    'conversation_id': conversationId,
    'title': title,
    'member_usernames': memberUsernames,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
  };

  factory LocalChatGroup.fromJson(Map<String, dynamic> value) {
    final rawMembers = value['member_usernames'];
    if (rawMembers is! List) {
      throw const FormatException('Local group members must be a list.');
    }
    return LocalChatGroup(
      conversationId: _string(value['conversation_id']),
      title: _string(value['title']),
      memberUsernames: rawMembers.map<String>((raw) => _string(raw)),
      createdBy: _string(value['created_by']),
      createdAt: _date(value['created_at']),
    );
  }
}

String _string(Object? value) {
  if (value is! String) throw const FormatException('Expected a string.');
  return value;
}

DateTime _date(Object? value) {
  final parsed = DateTime.tryParse(_string(value));
  if (parsed == null || !parsed.isUtc) {
    throw const FormatException('Expected a UTC date.');
  }
  return parsed;
}
