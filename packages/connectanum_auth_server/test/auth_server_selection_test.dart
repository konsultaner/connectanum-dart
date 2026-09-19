import 'package:connectanum_auth_server/connectanum_auth_server.dart';
import 'package:connectanum_router/auth.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    AuthenticatorRegistry.clear();
    AuthSecurityTracker.reset();
  });
  tearDown(() {
    AuthenticatorRegistry.clear();
    AuthSecurityTracker.reset();
  });

  for (final entry in [
    (['second', 'first'], ['first'], 'second'),
    (['unknown', 'second'], ['first'], 'second'),
    (<String>[], ['second', 'first'], 'second'),
    (['unknown'], ['unknown', 'first'], 'first'),
    (<String>[], <String>[], 'anonymous'),
    (['unknown'], ['unknown'], 'anonymous'),
  ]) {
    test(
      'authenticator preference is client then realm then anonymous: $entry',
      () async {
        final factories = [
          'first',
          'second',
          'anonymous',
        ].map(_Factory.new).toList();
        for (final factory in factories) {
          AuthenticatorRegistry.registerFactory(factory);
        }
        final realm = RealmSettingsBuilder('realm');
        for (final method in entry.$2) {
          realm.addAuthMethod(method);
        }
        final settings = (RouterSettingsBuilder()..addRealmFromBuilder(realm))
            .build();
        final server = AuthServer(settings: settings);
        addTearDown(server.close);
        final response = await server.onHello(_hello(settings, entry.$1));
        expect(response.status, RemoteHelloStatus.success);
        expect(response.success?.authId, entry.$3);
        expect(
          factories
              .where((factory) => factory.options.isNotEmpty)
              .map((factory) => factory.method),
          [entry.$3],
        );
      },
    );
  }

  test(
    'no available authenticator rejects without retaining capacity',
    () async {
      final settings =
          (RouterSettingsBuilder()..addRealmFromBuilder(
                RealmSettingsBuilder('realm')..addAuthMethod('unknown'),
              ))
              .build();
      final server = AuthServer(settings: settings);
      addTearDown(server.close);
      AuthenticatorRegistry.clear();
      final response = await server.onHello(_hello(settings, ['unknown']));
      expect(response.status, RemoteHelloStatus.failure);
      await Future<void>.delayed(Duration.zero);
      expect(server.pendingAuthenticationCounts, isEmpty);
    },
  );

  for (final alias in ['authenticator', 'use']) {
    test(
      '$alias resolves definition and definition options override realm values',
      () async {
        final factory = _Factory('implementation');
        AuthenticatorRegistry.registerFactory(factory);
        final realm = RealmSettingsBuilder('realm')
          ..addAuthMethod(
            'advertised',
            options: {
              alias: 'configured',
              'shared': 'realm',
              'realmOnly': 1,
            },
          );
        final settings =
            (RouterSettingsBuilder()
                  ..addRealmFromBuilder(realm)
                  ..addAuthenticator(
                    'configured',
                    const AuthenticatorDefinition(
                      type: 'implementation',
                      options: {'shared': 'definition', 'definitionOnly': true},
                    ),
                  ))
                .build();
        final server = AuthServer(settings: settings);
        addTearDown(server.close);
        final response = await server.onHello(_hello(settings, ['advertised']));
        expect(response.status, RemoteHelloStatus.success);
        expect(response.success?.authId, 'implementation');
        expect(factory.options, hasLength(1));
        expect(factory.options.single, {
          'authenticator': 'configured',
          'shared': 'definition',
          'realmOnly': 1,
          'definitionOnly': true,
        });
        factory.options.single['shared'] = 'modified by provider';
        expect(
          settings.authenticators['configured']!.options['shared'],
          'definition',
        );
        expect(
          settings.realms.single.auth.optionsFor('advertised')!['shared'],
          'realm',
        );
      },
    );
  }
}

RemoteHelloRequest _hello(RouterSettings settings, List<String> methods) =>
    RemoteHelloRequest(
      realmSettings: settings.realms.single,
      context: AuthenticatorContext(
        realm: settings.realms.single,
        sessionId: 1,
        transport: const TransportMetadata(connectionId: 1),
        helloDetails: {'authid': 'user', 'authmethods': methods},
      ),
      options: const {},
      transactionId: 'transaction',
    );

class _Factory extends AuthenticatorFactory {
  _Factory(this.method);
  @override
  final String method;
  final options = <Map<String, Object?>>[];
  @override
  Future<Authenticator> create(
    RealmSettings realm,
    Map<String, Object?> options,
  ) async {
    this.options.add(options);
    return _Authenticator(method);
  }
}

class _Authenticator extends Authenticator {
  _Authenticator(this.method);
  @override
  final String method;
  @override
  Future<AuthResult> onHello(AuthenticatorContext context) async =>
      AuthResult.success(AuthSuccess(authId: method, authRole: 'member'));
  @override
  Future<AuthResult> onAuthenticate(
    AuthenticatorContext context,
    AuthenticateMessage message,
  ) => throw StateError('Unexpected AUTHENTICATE');
}
