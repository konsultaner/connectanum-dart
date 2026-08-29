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

enum WampAppConversationAppearance {
  standard('standard'),
  ocean('ocean'),
  sunset('sunset');

  const WampAppConversationAppearance(this.wireName);

  final String wireName;

  static WampAppConversationAppearance parse(Object? value) {
    if (value is! String) {
      throw const FormatException(
        'A saved conversation appearance is invalid.',
      );
    }
    return values
            .where((candidate) => candidate.wireName == value)
            .firstOrNull ??
        (throw const FormatException(
          'A saved conversation appearance is invalid.',
        ));
  }
}

final class LocalAppPreferences {
  factory LocalAppPreferences({
    WampAppThemePreference theme = WampAppThemePreference.system,
    Iterable<String> mutedConversationIds = const [],
    Map<String, Duration> disappearingMessageDurations = const {},
    Map<String, WampAppConversationAppearance> conversationAppearances =
        const {},
  }) {
    final rawIds = mutedConversationIds.toList(growable: false);
    final uniqueIds = rawIds.toSet();
    if (uniqueIds.length != rawIds.length) {
      throw const FormatException(
        'Muted conversation identifiers must be unique.',
      );
    }
    final appearances = Map<String, WampAppConversationAppearance>.of(
      conversationAppearances,
    );
    if (appearances.length > maxConversationAppearances) {
      throw const FormatException(
        'Too many conversation appearances are saved.',
      );
    }
    for (final conversationId in appearances.keys) {
      _validateConversationId(conversationId, 'appearance');
    }
    appearances.removeWhere(
      (_, appearance) => appearance == WampAppConversationAppearance.standard,
    );
    return LocalAppPreferences._(
      theme,
      uniqueIds,
      Map<String, Duration>.of(disappearingMessageDurations),
      appearances,
    );
  }

  LocalAppPreferences._(
    this.theme,
    Set<String> mutedConversationIds,
    Map<String, Duration> disappearingMessageDurations,
    Map<String, WampAppConversationAppearance> conversationAppearances,
  ) : mutedConversationIds = Set<String>.unmodifiable(mutedConversationIds),
      disappearingMessageDurations = Map<String, Duration>.unmodifiable(
        disappearingMessageDurations,
      ),
      conversationAppearances =
          Map<String, WampAppConversationAppearance>.unmodifiable(
            conversationAppearances,
          ) {
    _validate();
  }

  static const maxMutedConversations = 500;
  static const maxDisappearingMessageConversations = 500;
  static const maxConversationAppearances = 500;
  static const maxConversationIdLength = 200;
  static const supportedDisappearingMessageDurations = <Duration>[
    Duration(hours: 1),
    Duration(days: 1),
    Duration(days: 7),
  ];
  static final defaults = LocalAppPreferences();

  final WampAppThemePreference theme;
  final Set<String> mutedConversationIds;
  final Map<String, Duration> disappearingMessageDurations;
  final Map<String, WampAppConversationAppearance> conversationAppearances;

  bool isMuted(String conversationId) =>
      mutedConversationIds.contains(conversationId);

  Duration? disappearingMessagesFor(String conversationId) =>
      disappearingMessageDurations[conversationId];

  WampAppConversationAppearance conversationAppearanceFor(
    String conversationId,
  ) =>
      conversationAppearances[conversationId] ??
      WampAppConversationAppearance.standard;

  LocalAppPreferences withTheme(WampAppThemePreference value) =>
      LocalAppPreferences(
        theme: value,
        mutedConversationIds: mutedConversationIds,
        disappearingMessageDurations: disappearingMessageDurations,
        conversationAppearances: conversationAppearances,
      );

  LocalAppPreferences withConversationMuted(String conversationId, bool muted) {
    final updated = mutedConversationIds.toSet();
    if (muted) {
      updated.add(conversationId);
    } else {
      updated.remove(conversationId);
    }
    return LocalAppPreferences(
      theme: theme,
      mutedConversationIds: updated,
      disappearingMessageDurations: disappearingMessageDurations,
      conversationAppearances: conversationAppearances,
    );
  }

  LocalAppPreferences withConversationDisappearingMessages(
    String conversationId,
    Duration? duration,
  ) {
    _validateConversationId(conversationId, 'disappearing-message');
    final updated = Map<String, Duration>.of(disappearingMessageDurations);
    if (duration == null) {
      updated.remove(conversationId);
    } else {
      updated[conversationId] = duration;
    }
    return LocalAppPreferences(
      theme: theme,
      mutedConversationIds: mutedConversationIds,
      disappearingMessageDurations: updated,
      conversationAppearances: conversationAppearances,
    );
  }

  LocalAppPreferences withConversationAppearance(
    String conversationId,
    WampAppConversationAppearance appearance,
  ) {
    _validateConversationId(conversationId, 'appearance');
    final updated = Map<String, WampAppConversationAppearance>.of(
      conversationAppearances,
    );
    if (appearance == WampAppConversationAppearance.standard) {
      updated.remove(conversationId);
    } else {
      updated[conversationId] = appearance;
    }
    return LocalAppPreferences(
      theme: theme,
      mutedConversationIds: mutedConversationIds,
      disappearingMessageDurations: disappearingMessageDurations,
      conversationAppearances: updated,
    );
  }

  Map<String, dynamic> toJson() {
    final muted = mutedConversationIds.toList(growable: false)..sort();
    final disappearingIds = disappearingMessageDurations.keys.toList(
      growable: false,
    )..sort();
    final appearanceIds = conversationAppearances.keys.toList(growable: false)
      ..sort();
    return {
      'theme': theme.wireName,
      'muted_conversation_ids': muted,
      'disappearing_message_seconds': <String, int>{
        for (final conversationId in disappearingIds)
          conversationId:
              disappearingMessageDurations[conversationId]!.inSeconds,
      },
      'conversation_appearances': <String, String>{
        for (final conversationId in appearanceIds)
          conversationId: conversationAppearances[conversationId]!.wireName,
      },
    };
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
    final rawDisappearing = value['disappearing_message_seconds'];
    if (rawDisappearing != null && rawDisappearing is! Map) {
      throw const FormatException(
        'Saved disappearing-message preferences are invalid.',
      );
    }
    final rawAppearances = value['conversation_appearances'];
    if (rawAppearances != null && rawAppearances is! Map) {
      throw const FormatException(
        'Saved conversation appearances are invalid.',
      );
    }
    final disappearing = <String, Duration>{};
    if (rawDisappearing case final Map values) {
      for (final entry in values.entries) {
        if (entry.key is! String || entry.value is! int) {
          throw const FormatException(
            'Saved disappearing-message preferences are invalid.',
          );
        }
        disappearing[entry.key as String] = Duration(
          seconds: entry.value as int,
        );
      }
    }
    final appearances = <String, WampAppConversationAppearance>{};
    if (rawAppearances case final Map values) {
      for (final entry in values.entries) {
        if (entry.key is! String) {
          throw const FormatException(
            'Saved conversation appearances are invalid.',
          );
        }
        appearances[entry.key as String] = WampAppConversationAppearance.parse(
          entry.value,
        );
      }
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
      disappearingMessageDurations: disappearing,
      conversationAppearances: appearances,
    );
  }

  void _validate() {
    if (mutedConversationIds.length > maxMutedConversations) {
      throw const FormatException('Too many muted conversations are saved.');
    }
    for (final conversationId in mutedConversationIds) {
      _validateConversationId(conversationId, 'muted');
    }
    if (disappearingMessageDurations.length >
        maxDisappearingMessageConversations) {
      throw const FormatException(
        'Too many disappearing-message conversations are saved.',
      );
    }
    for (final entry in disappearingMessageDurations.entries) {
      _validateConversationId(entry.key, 'disappearing-message');
      if (!supportedDisappearingMessageDurations.contains(entry.value)) {
        throw const FormatException(
          'A disappearing-message duration is invalid.',
        );
      }
    }
    if (conversationAppearances.length > maxConversationAppearances) {
      throw const FormatException(
        'Too many conversation appearances are saved.',
      );
    }
    for (final entry in conversationAppearances.entries) {
      _validateConversationId(entry.key, 'appearance');
      if (entry.value == WampAppConversationAppearance.standard) {
        throw const FormatException(
          'Standard conversation appearances must not be saved.',
        );
      }
    }
  }

  static void _validateConversationId(String conversationId, String kind) {
    if (conversationId.isEmpty ||
        conversationId.length > maxConversationIdLength) {
      throw FormatException('A $kind conversation identifier is invalid.');
    }
  }
}
