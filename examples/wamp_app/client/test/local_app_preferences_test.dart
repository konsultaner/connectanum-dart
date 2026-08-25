import 'package:flutter_test/flutter_test.dart';
import 'package:wamp_app/src/domain/local_app_preferences.dart';

void main() {
  test('missing preferences migrate to system appearance with no mutes', () {
    final preferences = LocalAppPreferences.fromJson(null);

    expect(preferences.theme, WampAppThemePreference.system);
    expect(preferences.mutedConversationIds, isEmpty);
  });

  test('preferences round-trip with stable sorted conversation ids', () {
    final preferences = LocalAppPreferences(
      theme: WampAppThemePreference.dark,
      mutedConversationIds: const ['group-z', 'direct-a'],
    );

    final encoded = preferences.toJson();
    final decoded = LocalAppPreferences.fromJson(encoded);

    expect(encoded, {
      'theme': 'dark',
      'muted_conversation_ids': ['direct-a', 'group-z'],
    });
    expect(decoded.theme, WampAppThemePreference.dark);
    expect(decoded.mutedConversationIds, {'direct-a', 'group-z'});
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
}
