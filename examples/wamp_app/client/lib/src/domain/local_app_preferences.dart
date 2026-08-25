enum WampAppThemePreference {
  system('system'),
  light('light'),
  dark('dark');

  const WampAppThemePreference(this.wireName);

  final String wireName;

  static WampAppThemePreference parse(Object? value) {
    if (value is! String) {
      throw const FormatException('The saved theme preference is invalid.');
    }
    return values
            .where((candidate) => candidate.wireName == value)
            .firstOrNull ??
        (throw const FormatException('The saved theme preference is invalid.'));
  }
}

final class LocalAppPreferences {
  factory LocalAppPreferences({
    WampAppThemePreference theme = WampAppThemePreference.system,
    Iterable<String> mutedConversationIds = const [],
  }) {
    final rawIds = mutedConversationIds.toList(growable: false);
    final uniqueIds = rawIds.toSet();
    if (uniqueIds.length != rawIds.length) {
      throw const FormatException(
        'Muted conversation identifiers must be unique.',
      );
    }
    return LocalAppPreferences._(theme, uniqueIds);
  }

  LocalAppPreferences._(this.theme, Set<String> mutedConversationIds)
    : mutedConversationIds = Set<String>.unmodifiable(mutedConversationIds) {
    _validate();
  }

  static const maxMutedConversations = 500;
  static const maxConversationIdLength = 200;
  static final defaults = LocalAppPreferences();

  final WampAppThemePreference theme;
  final Set<String> mutedConversationIds;

  bool isMuted(String conversationId) =>
      mutedConversationIds.contains(conversationId);

  LocalAppPreferences withTheme(WampAppThemePreference value) =>
      LocalAppPreferences(
        theme: value,
        mutedConversationIds: mutedConversationIds,
      );

  LocalAppPreferences withConversationMuted(String conversationId, bool muted) {
    final updated = mutedConversationIds.toSet();
    if (muted) {
      updated.add(conversationId);
    } else {
      updated.remove(conversationId);
    }
    return LocalAppPreferences(theme: theme, mutedConversationIds: updated);
  }

  Map<String, dynamic> toJson() {
    final muted = mutedConversationIds.toList(growable: false)..sort();
    return {'theme': theme.wireName, 'muted_conversation_ids': muted};
  }

  factory LocalAppPreferences.fromJson(Object? value) {
    if (value == null) return defaults;
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Saved application preferences are invalid.');
    }
    final muted = value['muted_conversation_ids'];
    if (muted is! List) {
      throw const FormatException('Saved muted conversations are invalid.');
    }
    return LocalAppPreferences(
      theme: WampAppThemePreference.parse(value['theme']),
      mutedConversationIds: muted.map((raw) {
        if (raw is! String) {
          throw const FormatException(
            'Saved muted conversation identifiers are invalid.',
          );
        }
        return raw;
      }),
    );
  }

  void _validate() {
    if (mutedConversationIds.length > maxMutedConversations) {
      throw const FormatException('Too many muted conversations are saved.');
    }
    for (final conversationId in mutedConversationIds) {
      if (conversationId.isEmpty ||
          conversationId.length > maxConversationIdLength) {
        throw const FormatException(
          'A muted conversation identifier is invalid.',
        );
      }
    }
  }
}
