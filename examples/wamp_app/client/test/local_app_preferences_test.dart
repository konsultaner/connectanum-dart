import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/domain/local_app_preferences.dart';

void main() {
  test('missing preferences migrate to empty account preferences', () {
    final preferences = LocalAppPreferences.fromJson(null);

    expect(preferences.theme, WampAppThemePreference.system);
    expect(preferences.mutedConversationIds, isEmpty);
    expect(preferences.disappearingMessageDurations, isEmpty);
    expect(preferences.conversationAppearances, isEmpty);
    expect(
      preferences.conversationAppearanceFor('direct-a'),
      WampAppConversationAppearance.standard,
    );
  });

  test('preferences round-trip with stable sorted conversation ids', () {
    final preferences = LocalAppPreferences(
      theme: WampAppThemePreference.dark,
      mutedConversationIds: const ['group-z', 'direct-a'],
      disappearingMessageDurations: const {
        'group-z': Duration(days: 7),
        'direct-a': Duration(hours: 1),
      },
      conversationAppearances: const {
        'group-z': WampAppConversationAppearance.sunset,
        'direct-a': WampAppConversationAppearance.ocean,
      },
    );

    final encoded = preferences.toJson();
    final decoded = LocalAppPreferences.fromJson(encoded);

    expect(encoded, {
      'theme': 'dark',
      'muted_conversation_ids': ['direct-a', 'group-z'],
      'disappearing_message_seconds': {'direct-a': 3600, 'group-z': 604800},
      'conversation_appearances': {'direct-a': 'ocean', 'group-z': 'sunset'},
    });
    expect(decoded.theme, WampAppThemePreference.dark);
    expect(decoded.mutedConversationIds, {'direct-a', 'group-z'});
    expect(
      decoded.disappearingMessagesFor('direct-a'),
      const Duration(hours: 1),
    );
    expect(decoded.disappearingMessagesFor('group-z'), const Duration(days: 7));
    expect(
      decoded.conversationAppearanceFor('direct-a'),
      WampAppConversationAppearance.ocean,
    );
    expect(
      decoded.conversationAppearanceFor('group-z'),
      WampAppConversationAppearance.sunset,
    );
  });

  test('saved preferences without disappearing messages migrate cleanly', () {
    final preferences = LocalAppPreferences.fromJson({
      'theme': 'dark',
      'muted_conversation_ids': ['direct-a'],
    });

    expect(preferences.theme, WampAppThemePreference.dark);
    expect(preferences.isMuted('direct-a'), isTrue);
    expect(preferences.disappearingMessageDurations, isEmpty);
    expect(preferences.conversationAppearances, isEmpty);
    expect(
      preferences.conversationAppearanceFor('direct-a'),
      WampAppConversationAppearance.standard,
    );
  });

  test('immutable updates isolate direct and group chat appearance', () {
    final directOcean = LocalAppPreferences.defaults.withConversationAppearance(
      'direct-a',
      WampAppConversationAppearance.ocean,
    );
    final groupSunset = directOcean.withConversationAppearance(
      'group-b',
      WampAppConversationAppearance.sunset,
    );
    final directStandard = groupSunset.withConversationAppearance(
      'direct-a',
      WampAppConversationAppearance.standard,
    );

    expect(LocalAppPreferences.defaults.conversationAppearances, isEmpty);
    expect(
      directOcean.conversationAppearanceFor('direct-a'),
      WampAppConversationAppearance.ocean,
    );
    expect(
      directOcean.conversationAppearanceFor('group-b'),
      WampAppConversationAppearance.standard,
    );
    expect(
      groupSunset.conversationAppearanceFor('group-b'),
      WampAppConversationAppearance.sunset,
    );
    expect(
      directStandard.conversationAppearanceFor('direct-a'),
      WampAppConversationAppearance.standard,
    );
    expect(
      directStandard.conversationAppearanceFor('group-b'),
      WampAppConversationAppearance.sunset,
    );
    expect(directStandard.conversationAppearances, {
      'group-b': WampAppConversationAppearance.sunset,
    });
    expect(
      () => directOcean.conversationAppearances['unexpected'] =
          WampAppConversationAppearance.sunset,
      throwsUnsupportedError,
    );
  });

  test('immutable updates isolate direct and group mute state', () {
    final directMuted = LocalAppPreferences.defaults.withConversationMuted(
      'direct-a',
      true,
    );
    final groupMuted = directMuted.withConversationMuted('group-b', true);
    final directUnmuted = groupMuted.withConversationMuted('direct-a', false);

    expect(LocalAppPreferences.defaults.mutedConversationIds, isEmpty);
    expect(directMuted.isMuted('direct-a'), isTrue);
    expect(directMuted.isMuted('group-b'), isFalse);
    expect(groupMuted.isMuted('direct-a'), isTrue);
    expect(groupMuted.isMuted('group-b'), isTrue);
    expect(directUnmuted.isMuted('direct-a'), isFalse);
    expect(directUnmuted.isMuted('group-b'), isTrue);
    expect(
      () => directMuted.mutedConversationIds.add('unexpected'),
      throwsUnsupportedError,
    );
  });

  test('immutable updates isolate direct and group disappearing messages', () {
    final directExpiry = LocalAppPreferences.defaults
        .withConversationDisappearingMessages(
          'direct-a',
          const Duration(hours: 1),
        );
    final groupExpiry = directExpiry.withConversationDisappearingMessages(
      'group-b',
      const Duration(days: 7),
    );
    final directKept = groupExpiry.withConversationDisappearingMessages(
      'direct-a',
      null,
    );

    expect(LocalAppPreferences.defaults.disappearingMessageDurations, isEmpty);
    expect(
      directExpiry.disappearingMessagesFor('direct-a'),
      const Duration(hours: 1),
    );
    expect(directExpiry.disappearingMessagesFor('group-b'), isNull);
    expect(
      groupExpiry.disappearingMessagesFor('group-b'),
      const Duration(days: 7),
    );
    expect(directKept.disappearingMessagesFor('direct-a'), isNull);
    expect(
      directKept.disappearingMessagesFor('group-b'),
      const Duration(days: 7),
    );
    expect(
      () => directExpiry.disappearingMessageDurations['unexpected'] =
          const Duration(days: 1),
      throwsUnsupportedError,
    );
  });

  test('malformed saved preferences fail closed', () {
    final invalidValues = <Object?>[
      'dark',
      <String, dynamic>{},
      {'theme': 'sepia', 'muted_conversation_ids': <String>[]},
      {'theme': 'dark', 'muted_conversation_ids': 'direct-a'},
      {
        'theme': 'dark',
        'muted_conversation_ids': ['duplicate', 'duplicate'],
      },
      {
        'theme': 'dark',
        'muted_conversation_ids': [1],
      },
      {
        'theme': 'dark',
        'muted_conversation_ids': <String>[],
        'disappearing_message_seconds': 'direct-a',
      },
      {
        'theme': 'dark',
        'muted_conversation_ids': <String>[],
        'disappearing_message_seconds': {'direct-a': 0},
      },
      {
        'theme': 'dark',
        'muted_conversation_ids': <String>[],
        'disappearing_message_seconds': {'direct-a': 60},
      },
      {
        'theme': 'dark',
        'muted_conversation_ids': <String>[],
        'disappearing_message_seconds': {'direct-a': '3600'},
      },
      {
        'theme': 'dark',
        'muted_conversation_ids': <String>[],
        'conversation_appearances': 'ocean',
      },
      {
        'theme': 'dark',
        'muted_conversation_ids': <String>[],
        'conversation_appearances': {'direct-a': 1},
      },
      {
        'theme': 'dark',
        'muted_conversation_ids': <String>[],
        'conversation_appearances': {'direct-a': 'sepia'},
      },
    ];

    for (final value in invalidValues) {
      expect(
        () => LocalAppPreferences.fromJson(value),
        throwsFormatException,
        reason: '$value should be rejected',
      );
    }
  });

  test('mute identifiers and count remain bounded', () {
    expect(
      () => LocalAppPreferences(
        mutedConversationIds: [
          List<String>.filled(
            LocalAppPreferences.maxConversationIdLength + 1,
            'x',
          ).join(),
        ],
      ),
      throwsFormatException,
    );
    expect(
      () => LocalAppPreferences(
        mutedConversationIds: List<String>.generate(
          LocalAppPreferences.maxMutedConversations + 1,
          (index) => 'conversation-$index',
        ),
      ),
      throwsFormatException,
    );
  });

  test('disappearing-message identifiers and count remain bounded', () {
    expect(
      () => LocalAppPreferences(
        disappearingMessageDurations: {
          List<String>.filled(
            LocalAppPreferences.maxConversationIdLength + 1,
            'x',
          ).join(): const Duration(
            hours: 1,
          ),
        },
      ),
      throwsFormatException,
    );
    expect(
      () => LocalAppPreferences(
        disappearingMessageDurations: {
          for (
            var index = 0;
            index <= LocalAppPreferences.maxDisappearingMessageConversations;
            index += 1
          )
            'conversation-$index': const Duration(days: 1),
        },
      ),
      throwsFormatException,
    );
    expect(
      () => LocalAppPreferences(
        disappearingMessageDurations: const {'direct-a': Duration(minutes: 5)},
      ),
      throwsFormatException,
    );
  });

  test('chat-appearance identifiers and count remain bounded', () {
    expect(
      () => LocalAppPreferences(
        conversationAppearances: {
          List<String>.filled(
            LocalAppPreferences.maxConversationIdLength + 1,
            'x',
          ).join(): WampAppConversationAppearance.ocean,
        },
      ),
      throwsFormatException,
    );
    expect(
      () => LocalAppPreferences(
        conversationAppearances: {
          for (
            var index = 0;
            index <= LocalAppPreferences.maxConversationAppearances;
            index += 1
          )
            'conversation-$index': WampAppConversationAppearance.sunset,
        },
      ),
      throwsFormatException,
    );
  });
}
