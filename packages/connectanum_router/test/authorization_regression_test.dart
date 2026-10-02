import 'dart:async';

import 'package:connectanum_router/connectanum_router.dart' hide Error;
import 'package:test/test.dart';

void main() {
  setUp(() {
    AuthorizationProviderRegistry.clear();
    AuthorizationProviderFactoryRegistry.clear();
  });
  tearDown(() {
    AuthorizationProviderRegistry.clear();
    AuthorizationProviderFactoryRegistry.clear();
  });

  const actions = {
    AuthorizationAction.subscribe: 'subscribe',
    AuthorizationAction.unsubscribe: 'subscribe',
    AuthorizationAction.publish: 'publish',
    AuthorizationAction.call: 'call',
    AuthorizationAction.cancel: 'call',
    AuthorizationAction.register: 'register',
    AuthorizationAction.unregister: 'register',
  };
  const topics = {
    AuthorizationAction.subscribe,
    AuthorizationAction.unsubscribe,
    AuthorizationAction.publish,
  };

  for (final entry in actions.entries) {
    final action = entry.key;
    for (final rule in <(PermissionMatchPolicy, String, String, bool)>[
      (PermissionMatchPolicy.exact, 'com.app', 'com.app', true),
      (PermissionMatchPolicy.exact, 'com.app', 'com.application', false),
      (PermissionMatchPolicy.exact, 'com.app', 'com.app.child', false),
      (PermissionMatchPolicy.prefix, '', 'com.app', true),
      (PermissionMatchPolicy.prefix, 'com.app', 'com.app', true),
      (PermissionMatchPolicy.prefix, 'com.app', 'com.app.child', true),
      (PermissionMatchPolicy.prefix, 'com.app.', 'com.app.child', true),
      (PermissionMatchPolicy.prefix, 'com.app.', 'com.app', false),
      (
        PermissionMatchPolicy.prefix,
        'com.app',
        'com.application',
        topics.contains(action),
      ),
      (PermissionMatchPolicy.prefix, 'com.app', 'com.ap', false),
      (PermissionMatchPolicy.prefix, 'com.app', 'other.app', false),
      (PermissionMatchPolicy.wildcard, 'com..event', 'com.app.event', true),
      (PermissionMatchPolicy.wildcard, 'com..event', 'com.app.other', false),
      (
        PermissionMatchPolicy.wildcard,
        'com..event',
        'com.app.child.event',
        false,
      ),
      (PermissionMatchPolicy.wildcard, 'com..event', 'com.event', false),
      (PermissionMatchPolicy.wildcard, '..', 'a.b.c', true),
    ]) {
      test(
        '${action.name} ${rule.$1.name} ${rule.$2} matches ${rule.$3}: ${rule.$4}',
        () async {
          final outcome =
              await RealmAuthorizer.authorize(
                realmSettings: realm([
                  PermissionSettings(
                    uri: rule.$2,
                    matchPolicy: rule.$1,
                    allow: [entry.value.toUpperCase()],
                  ),
                ]),
                request: request(action: action, uri: rule.$3),
              ).then<Object>(
                (decision) => decision,
                onError: (Object error, StackTrace stack) {
                  if (error is TimeoutException) {
                    Error.throwWithStackTrace(error, stack);
                  }
                  return error;
                },
              );
          // Valid rules must yield a decision, including non-matching URIs.
          expect(outcome, isA<AuthorizationDecision>());
          final decision = outcome as AuthorizationDecision;
          expect(decision.allowed, rule.$4);
          expect(decision.reason, rule.$4 ? '' : 'wamp.error.not_authorized');
        },
      );
    }

    test('${action.name} explicit deny wins over paired permission', () async {
      var providerCalls = 0;
      final decision = await RealmAuthorizer.authorize(
        realmSettings: realm([
          PermissionSettings(
            uri: 'com.app',
            allow: [entry.value],
            deny: [action.name.toUpperCase()],
          ),
        ]),
        request: request(action: action),
        provider: CallbackProvider((_) {
          providerCalls++;
          return const AuthorizationDecision.allow();
        }),
      );
      expect(decision.allowed, isFalse);
      expect(providerCalls, 0);
      expect(decision.message, 'Role member may not ${action.name} com.app');
    });
  }

  for (final roleName in <String?>[null, '', 'missing', 'Member']) {
    test(
      'unknown role $roleName cannot borrow another role permissions',
      () async {
        final decision = await RealmAuthorizer.authorize(
          realmSettings: realm([
            const PermissionSettings(uri: 'com.app', allow: ['call']),
          ]),
          request: request(role: roleName),
        );
        expect(decision.allowed, isFalse);
        expect(
          decision.message,
          'Not authorized to call com.app in realm realm1',
        );
      },
    );
  }

  final priorityPairs = <(PermissionSettings, PermissionSettings, String)>[
    (
      const PermissionSettings(uri: 'com.app', allow: ['call']),
      const PermissionSettings(
        uri: 'com.app',
        matchPolicy: PermissionMatchPolicy.prefix,
        deny: ['call'],
      ),
      'com.app',
    ),
    (
      const PermissionSettings(uri: 'com.app', allow: ['call']),
      const PermissionSettings(
        uri: 'com.',
        matchPolicy: PermissionMatchPolicy.prefix,
        deny: ['call'],
      ),
      'com.app',
    ),
    (
      const PermissionSettings(
        uri: 'com.app',
        matchPolicy: PermissionMatchPolicy.prefix,
        allow: ['call'],
      ),
      const PermissionSettings(
        uri: 'com.',
        matchPolicy: PermissionMatchPolicy.wildcard,
        deny: ['call'],
      ),
      'com.app',
    ),
    (
      const PermissionSettings(
        uri: 'com.app',
        matchPolicy: PermissionMatchPolicy.prefix,
        allow: ['call'],
      ),
      const PermissionSettings(
        uri: 'com',
        matchPolicy: PermissionMatchPolicy.prefix,
        deny: ['call'],
      ),
      'com.app.child',
    ),
    (
      const PermissionSettings(
        uri: 'com..event',
        matchPolicy: PermissionMatchPolicy.wildcard,
        allow: ['call'],
      ),
      const PermissionSettings(
        uri: '..event',
        matchPolicy: PermissionMatchPolicy.wildcard,
        deny: ['call'],
      ),
      'com.app.event',
    ),
  ];
  for (var index = 0; index < priorityPairs.length; index++) {
    final pair = priorityPairs[index];
    for (final reverse in [false, true]) {
      test(
        'permission priority $index is independent of list order $reverse',
        () async {
          final rules = reverse ? [pair.$2, pair.$1] : [pair.$1, pair.$2];
          expect(
            (await RealmAuthorizer.authorize(
              realmSettings: realm(rules),
              request: request(uri: pair.$3),
            )).allowed,
            isTrue,
          );
        },
      );
    }
  }

  test('equal-specificity rules preserve declaration order', () async {
    const allow = PermissionSettings(uri: 'com.app', allow: ['call']);
    const deny = PermissionSettings(uri: 'com.app', deny: ['call']);
    for (final allowed in [true, false]) {
      expect(
        (await RealmAuthorizer.authorize(
          realmSettings: realm(allowed ? [allow, deny] : [deny, allow]),
          request: request(),
        )).allowed,
        allowed,
      );
    }
  });

  test(
    'blank auth role cannot acquire permissions from a blank role definition',
    () async {
      final settings = RealmSettings(
        name: 'realm1',
        auth: const RealmAuthSettings(methods: ['anonymous']),
        roles: const [
          RoleSettings(
            name: '',
            permissions: [
              PermissionSettings(uri: 'com.app', allow: ['call']),
            ],
          ),
        ],
        limits: const RealmLimitSettings(),
      );
      expect(
        (await RealmAuthorizer.authorize(
          realmSettings: settings,
          request: request(role: ''),
        )).allowed,
        isFalse,
      );
    },
  );

  test(
    'large equal-specificity policy preserves the first matching decision',
    () async {
      for (final allowed in [true, false]) {
        final permissions = [
          for (var index = 0; index < 128; index++)
            PermissionSettings(
              uri: 'com.app',
              allow: (index == 0) == allowed ? ['call'] : [],
              deny: (index == 0) == allowed ? [] : ['call'],
            ),
        ];
        expect(
          (await RealmAuthorizer.authorize(
            realmSettings: realm(permissions),
            request: request(),
          )).allowed,
          allowed,
        );
      }
    },
  );

  test('priority sorting preserves ties amid lower-priority rules', () async {
    for (final first in [1, 12, 31, 64, 96]) {
      final permissions = [
        for (var index = 0; index < 160; index++)
          if (index == first || index == first + 30)
            PermissionSettings(
              uri: 'com.app',
              allow: index == first ? [] : ['call'],
              deny: index == first ? ['call'] : [],
            )
          else
            const PermissionSettings(
              uri: 'com',
              matchPolicy: PermissionMatchPolicy.prefix,
              allow: ['call'],
            ),
      ];
      expect(
        (await RealmAuthorizer.authorize(
          realmSettings: realm(permissions),
          request: request(),
        )).allowed,
        isFalse,
        reason: 'first exact rule at $first',
      );
    }
  });

  test(
    'matching unrelated operations fall through to a less specific rule',
    () async {
      expect(
        (await RealmAuthorizer.authorize(
          realmSettings: realm(const [
            PermissionSettings(
              uri: 'com.app',
              allow: ['publish'],
              deny: ['register'],
            ),
            PermissionSettings(
              uri: 'com.',
              matchPolicy: PermissionMatchPolicy.prefix,
              allow: ['call'],
            ),
          ]),
          request: request(),
        )).allowed,
        isTrue,
      );
    },
  );

  test(
    'provider receives the original security context and error fails closed',
    () async {
      final input = request();
      final failure = StateError('provider unavailable');
      await expectLater(
        RealmAuthorizer.authorize(
          realmSettings: realm([]),
          request: input,
          provider: CallbackProvider((actual) {
            expect(identical(actual, input), isTrue);
            throw failure;
          }),
        ),
        throwsA(same(failure)),
      );
      expect(input.isInternal, isFalse);
      expect(input.options, isEmpty);
    },
  );

  for (final staticAllowed in [false, true]) {
    test(
      'abstaining provider preserves static decision $staticAllowed',
      () async {
        expect(
          (await RealmAuthorizer.authorize(
            realmSettings: realm([
              PermissionSettings(
                uri: 'com.app',
                allow: [staticAllowed ? 'call' : 'subscribe'],
              ),
            ]),
            request: request(),
            provider: CallbackProvider((_) => null),
          )).allowed,
          staticAllowed,
        );
      },
    );
  }

  test('registry snapshots are read-only and unregister is scoped', () {
    final first = CallbackFactory(
      'first',
      (_) => CallbackProvider((_) => null),
    );
    final second = CallbackFactory(
      'second',
      (_) => CallbackProvider((_) => null),
    );
    AuthorizationProviderFactoryRegistry.registerFactories([first, second]);
    final snapshot = AuthorizationProviderFactoryRegistry.factories;
    expect(() => snapshot.clear(), throwsUnsupportedError);
    AuthorizationProviderFactoryRegistry.unregisterFactory('first');
    expect(AuthorizationProviderFactoryRegistry.factoryFor('first'), isNull);
    expect(
      AuthorizationProviderFactoryRegistry.factoryFor('second'),
      same(second),
    );
    expect(snapshot.keys, containsAll(['first', 'second']));
  });

  test(
    'cache handles absent names and rejects unknown definitions/factories',
    () async {
      final cache = RealmAuthorizationProviderCache(
        RouterSettings(
          realms: [],
          listeners: [],
          authorizationProviders: const {
            'configured': AuthorizationProviderDefinition(type: 'missing'),
          },
        ),
      );
      for (final name in <String?>[null, '', '  ']) {
        expect(await cache.providerFor(realm([], provider: name)), isNull);
      }
      await expectLater(
        cache.providerFor(realm([], provider: 'unknown')),
        throwsStateError,
      );
      await expectLater(
        cache.providerFor(realm([], provider: 'configured')),
        throwsStateError,
      );
    },
  );

  test(
    'concurrent cached provider resolution initializes once per name',
    () async {
      var calls = 0;
      final ready = Completer<AuthorizationProvider>();
      final provider = CallbackProvider((_) => null);
      AuthorizationProviderFactoryRegistry.registerFactory(
        CallbackFactory('test', (options) {
          calls++;
          expect(options, {'name': 'main', 'audience': 'realm1'});
          return ready.future;
        }),
      );
      final cache = RealmAuthorizationProviderCache(
        RouterSettings(
          realms: [],
          listeners: [],
          authorizationProviders: const {
            'main': AuthorizationProviderDefinition(
              type: 'test',
              options: {'audience': 'realm1'},
            ),
          },
        ),
      );
      final pending = List.generate(
        8,
        (_) => cache.providerFor(realm([], provider: ' main ')),
      );
      ready.complete(provider);
      expect(await Future.wait(pending), everyElement(same(provider)));
      expect(
        await cache.providerFor(realm([], provider: 'main')),
        same(provider),
      );
      expect(calls, 1);
    },
  );
}

RealmSettings realm(List<PermissionSettings> permissions, {String? provider}) =>
    RealmSettings(
      name: 'realm1',
      auth: const RealmAuthSettings(methods: ['anonymous']),
      roles: [
        RoleSettings(name: 'other', permissions: []),
        RoleSettings(name: 'member', permissions: permissions),
      ],
      limits: const RealmLimitSettings(),
      authorizationProvider: provider,
    );

AuthorizationRequest request({
  AuthorizationAction action = AuthorizationAction.call,
  String uri = 'com.app',
  String? role = 'member',
}) => AuthorizationRequest(
  realmUri: 'realm1',
  action: action,
  uri: uri,
  sessionId: 1,
  authRole: role,
);

class CallbackProvider implements AuthorizationProvider {
  CallbackProvider(this.callback);
  final FutureOr<AuthorizationDecision?> Function(AuthorizationRequest)
  callback;
  @override
  FutureOr<AuthorizationDecision?> authorize(AuthorizationRequest request) =>
      callback(request);
}

class CallbackFactory extends AuthorizationProviderFactory {
  CallbackFactory(this.type, this.callback);
  @override
  final String type;
  final FutureOr<AuthorizationProvider> Function(Map<String, Object?>) callback;
  @override
  FutureOr<AuthorizationProvider> create(Map<String, Object?> options) =>
      callback(options);
}
