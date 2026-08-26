import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:wamp_app_protocol/wamp_app_protocol.dart';
import 'package:wamp_app_server/wamp_app_server.dart';

void main() {
  late Directory temporary;
  late McpConsentStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('wamp-app-mcp-consent-');
    store = McpConsentStore('${temporary.path}/consent.json');
    await store.initialize();
  });

  tearDown(() => temporary.delete(recursive: true));

  test('defaults every account to denied without persisting a grant', () async {
    final consent = await store.get('Alice');

    expect(consent.profileReadAllowed, isFalse);
    expect(consent.revision, 0);
    expect(consent.updatedAt, isNull);
    expect(await store.file.readAsString(), isNot(contains('alice')));
  });

  test('persists account-scoped consent and survives reopening', () async {
    final updatedAt = DateTime.utc(2026, 8, 25, 12);
    final granted = await store.update(
      'Alice',
      WampAppMcpConsentUpdate(expectedRevision: 0, profileReadAllowed: true),
      now: updatedAt,
    );

    expect(granted.profileReadAllowed, isTrue);
    expect(granted.revision, 1);
    expect(granted.updatedAt, updatedAt);
    expect((await store.get('bob')).profileReadAllowed, isFalse);

    final reopened = McpConsentStore(store.file.path);
    final persisted = await reopened.get('alice');
    expect(persisted.profileReadAllowed, isTrue);
    expect(persisted.revision, 1);
    expect(persisted.updatedAt, updatedAt);
  });

  test(
    'serializes competing device updates with stale revision rejection',
    () async {
      final outcomes = await Future.wait<Object>([
        store
            .update(
              'alice',
              WampAppMcpConsentUpdate(
                expectedRevision: 0,
                profileReadAllowed: true,
              ),
            )
            .then<Object>((value) => value)
            .catchError((Object error) => error),
        store
            .update(
              'alice',
              WampAppMcpConsentUpdate(
                expectedRevision: 0,
                profileReadAllowed: false,
              ),
            )
            .then<Object>((value) => value)
            .catchError((Object error) => error),
      ]);

      expect(outcomes.whereType<WampAppMcpConsent>(), hasLength(1));
      expect(outcomes.whereType<McpConsentConflict>(), hasLength(1));
      expect((await store.get('alice')).revision, 1);
    },
  );

  test('revocation increments revision and takes effect immediately', () async {
    await store.update(
      'alice',
      WampAppMcpConsentUpdate(expectedRevision: 0, profileReadAllowed: true),
    );
    final revoked = await store.update(
      'alice',
      WampAppMcpConsentUpdate(expectedRevision: 1, profileReadAllowed: false),
    );

    expect(revoked.profileReadAllowed, isFalse);
    expect(revoked.revision, 2);
    expect((await store.get('alice')).profileReadAllowed, isFalse);
  });

  test('rejects malformed persisted consent without widening access', () async {
    final decoded =
        jsonDecode(await store.file.readAsString()) as Map<String, dynamic>;
    decoded['consents'] = {
      'alice': {'profile_read_allowed': true, 'revision': 1},
    };
    await store.file.writeAsString(jsonEncode(decoded));

    await expectLater(store.get('alice'), throwsFormatException);
  });
}
