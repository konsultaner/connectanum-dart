import 'package:connectanum_router/connectanum_router.dart';
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

  group('RealmAuthorizer', () {
    test('allows static exact, prefix, and wildcard permissions', () async {
      final realm = _realmWithRole(
        'member',
        permissions: const <PermissionSettings>[
          PermissionSettings(
            uri: 'com.demo.topic',
            allow: <String>['subscribe'],
          ),
          PermissionSettings(
            uri: 'com.demo.',
            matchPolicy: PermissionMatchPolicy.prefix,
            allow: <String>['call'],
          ),
          PermissionSettings(
            uri: 'com..event',
            matchPolicy: PermissionMatchPolicy.wildcard,
            allow: <String>['publish'],
          ),
        ],
      );

      final exactDecision = await RealmAuthorizer.authorize(
        realmSettings: realm,
        request: _request(
          action: AuthorizationAction.subscribe,
          uri: 'com.demo.topic',
        ),
      );
      final prefixDecision = await RealmAuthorizer.authorize(
        realmSettings: realm,
        request: _request(
          action: AuthorizationAction.call,
          uri: 'com.demo.proc.health',
        ),
      );
      final wildcardDecision = await RealmAuthorizer.authorize(
        realmSettings: realm,
        request: _request(
          action: AuthorizationAction.publish,
          uri: 'com.demo.event',
        ),
      );

      expect(exactDecision.allowed, isTrue);
      expect(prefixDecision.allowed, isTrue);
      expect(wildcardDecision.allowed, isTrue);
    });

    test('allows paired teardown actions from create permissions', () async {
      final realm = _realmWithRole(
        'member',
        permissions: const <PermissionSettings>[
          PermissionSettings(
            uri: 'com.demo.',
            matchPolicy: PermissionMatchPolicy.prefix,
            allow: <String>['subscribe', 'register', 'call'],
          ),
        ],
      );

      final unsubscribeDecision = await RealmAuthorizer.authorize(
        realmSettings: realm,
        request: _request(
          action: AuthorizationAction.unsubscribe,
          uri: 'com.demo.topic',
        ),
      );
      final unregisterDecision = await RealmAuthorizer.authorize(
        realmSettings: realm,
        request: _request(
          action: AuthorizationAction.unregister,
          uri: 'com.demo.proc',
        ),
      );
      final cancelDecision = await RealmAuthorizer.authorize(
        realmSettings: realm,
        request: _request(
          action: AuthorizationAction.cancel,
          uri: 'com.demo.proc',
        ),
      );

      expect(unsubscribeDecision.allowed, isTrue);
      expect(unregisterDecision.allowed, isTrue);
      expect(cancelDecision.allowed, isTrue);
    });

    test('static deny beats dynamic allow', () async {
      final realm = _realmWithRole(
        'member',
        permissions: const <PermissionSettings>[
          PermissionSettings(uri: 'com.demo.topic', deny: <String>['publish']),
        ],
      );
      AuthorizationProviderRegistry.registerProvider(
        _CallbackAuthorizationProvider(
          (request) => const AuthorizationDecision.allow(),
        ),
      );

      final decision = await RealmAuthorizer.authorize(
        realmSettings: realm,
        request: _request(
          action: AuthorizationAction.publish,
          uri: 'com.demo.topic',
        ),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reason, equals('wamp.error.not_authorized'));
    });

    test('dynamic deny overrides static allow', () async {
      final realm = _realmWithRole(
        'member',
        permissions: const <PermissionSettings>[
          PermissionSettings(uri: 'com.demo.proc', allow: <String>['call']),
        ],
      );
      AuthorizationProviderRegistry.registerProvider(
        _CallbackAuthorizationProvider(
          (request) =>
              const AuthorizationDecision.deny(message: 'blocked by provider'),
        ),
      );

      final decision = await RealmAuthorizer.authorize(
        realmSettings: realm,
        request: _request(
          action: AuthorizationAction.call,
          uri: 'com.demo.proc',
        ),
      );

      expect(decision.allowed, isFalse);
      expect(decision.message, equals('blocked by provider'));
    });

    test('dynamic allow fills static abstain', () async {
      final realm = _realmWithRole('member');
      AuthorizationProviderRegistry.registerProvider(
        _CallbackAuthorizationProvider(
          (request) => request.uri == 'com.demo.proc'
              ? const AuthorizationDecision.allow()
              : null,
        ),
      );

      final decision = await RealmAuthorizer.authorize(
        realmSettings: realm,
        request: _request(
          action: AuthorizationAction.call,
          uri: 'com.demo.proc',
        ),
      );

      expect(decision.allowed, isTrue);
    });

    test('accepts an explicit provider for configured worker use', () async {
      final realm = _realmWithRole(
        'member',
        permissions: const <PermissionSettings>[
          PermissionSettings(uri: 'com.demo.proc', allow: <String>['call']),
        ],
      );

      final decision = await RealmAuthorizer.authorize(
        realmSettings: realm,
        provider: _CallbackAuthorizationProvider(
          (request) =>
              const AuthorizationDecision.deny(message: 'configured deny'),
        ),
        request: _request(
          action: AuthorizationAction.call,
          uri: 'com.demo.proc',
        ),
      );

      expect(decision.allowed, isFalse);
      expect(decision.message, equals('configured deny'));
    });

    test(
      'preserves legacy allow-all when no permissions are configured',
      () async {
        final realm = _realmWithRole('member');

        final decision = await RealmAuthorizer.authorize(
          realmSettings: realm,
          request: _request(
            action: AuthorizationAction.publish,
            uri: 'com.demo.topic',
          ),
        );

        expect(decision.allowed, isTrue);
      },
    );

    test(
      'defaults to deny when realm permissions exist but no rule or provider allows the action',
      () async {
        final realm = _realmWithRole(
          'member',
          permissions: const <PermissionSettings>[
            PermissionSettings(
              uri: 'com.demo.allowed',
              allow: <String>['call'],
            ),
          ],
        );

        final decision = await RealmAuthorizer.authorize(
          realmSettings: realm,
          request: _request(
            action: AuthorizationAction.publish,
            uri: 'com.demo.topic',
          ),
        );

        expect(decision.allowed, isFalse);
        expect(decision.reason, equals('wamp.error.not_authorized'));
        expect(decision.message, contains('publish'));
      },
    );
  });

  group('RealmAuthorizationProviderCache', () {
    test('resolves configured providers from router settings', () async {
      AuthorizationProviderFactoryRegistry.registerFactory(
        _CallbackAuthorizationProviderFactory(
          'deny-topic',
          (options) => _CallbackAuthorizationProvider(
            (request) => request.uri == options['topic']
                ? const AuthorizationDecision.deny(message: 'configured deny')
                : null,
          ),
        ),
      );

      final realm = _realmWithRole(
        'member',
        authorizationProvider: 'realm-provider',
      );
      final settings = RouterSettings(
        realms: <RealmSettings>[realm],
        listeners: const <ListenerSettings>[],
        authorizationProviders: const <String, AuthorizationProviderDefinition>{
          'realm-provider': AuthorizationProviderDefinition(
            type: 'deny-topic',
            options: <String, Object?>{'topic': 'com.demo.proc'},
          ),
        },
      );

      final cache = RealmAuthorizationProviderCache(settings);
      final provider = await cache.providerFor(realm);
      final decision = await provider!.authorize(
        _request(action: AuthorizationAction.call, uri: 'com.demo.proc'),
      );

      expect(decision?.allowed, isFalse);
      expect(decision?.message, equals('configured deny'));
    });
  });
}

RealmSettings _realmWithRole(
  String roleName, {
  List<PermissionSettings> permissions = const <PermissionSettings>[],
  String? authorizationProvider,
}) {
  return RealmSettings(
    name: 'realm1',
    authorizationProvider: authorizationProvider,
    auth: const RealmAuthSettings(methods: <String>['anonymous']),
    roles: <RoleSettings>[
      RoleSettings(name: roleName, permissions: permissions),
    ],
    limits: const RealmLimitSettings(),
  );
}

AuthorizationRequest _request({
  required AuthorizationAction action,
  required String uri,
}) {
  return AuthorizationRequest(
    realmUri: 'realm1',
    action: action,
    uri: uri,
    sessionId: 1,
    authId: 'user-1',
    authRole: 'member',
  );
}

class _CallbackAuthorizationProvider implements AuthorizationProvider {
  _CallbackAuthorizationProvider(this._callback);

  final AuthorizationDecision? Function(AuthorizationRequest request) _callback;

  @override
  Future<AuthorizationDecision?> authorize(AuthorizationRequest request) async {
    return _callback(request);
  }
}

class _CallbackAuthorizationProviderFactory
    extends AuthorizationProviderFactory {
  _CallbackAuthorizationProviderFactory(this._type, this._create);

  final String _type;
  final AuthorizationProvider Function(Map<String, Object?> options) _create;

  @override
  String get type => _type;

  @override
  Future<AuthorizationProvider> create(Map<String, Object?> options) async {
    return _create(options);
  }
}
