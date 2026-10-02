@TestOn('vm')
library;

import 'package:connectanum_bench/src/remote_auth_bench_harness.dart';
import 'package:connectanum_router/connectanum_router.dart';
import 'package:test/test.dart';

void main() {
  group('RemoteAuthBenchHarness.supports', () {
    test('returns false when no remote authenticators are configured', () {
      expect(
        RemoteAuthBenchHarness.supports(
          const RouterSettings(realms: <RealmSettings>[], listeners: []),
        ),
        isFalse,
      );
    });

    test('returns true for rawsocket remote-auth bench settings', () {
      final settings = _buildRemoteAuthSettings();

      expect(RemoteAuthBenchHarness.supports(settings), isTrue);
    });

    final settings = _buildRemoteAuthSettings();
    final options = settings.authenticators['remote-ticket']!.options;
    final rpc = Map<String, Object?>.from(options['rpc']! as Map);
    final transport = Map<String, Object?>.from(rpc['transport']! as Map);
    final invalidOptions = <String, Map<String, Object?>>{
      'absent rpc': {},
      for (final value in [null, true, 'rpc', <Object?>[]])
        'non-map rpc $value': {...options, 'rpc': value},
      'non-string rpc key': {
        ...options,
        'rpc': <Object?, Object?>{...rpc, 7: 'invalid'},
      },
      'absent transport': {
        ...options,
        'rpc': {...rpc}..remove('transport'),
      },
      for (final value in [null, true, 'transport', <Object?>[]])
        'non-map transport $value': {
          ...options,
          'rpc': {...rpc, 'transport': value},
        },
      'non-string transport key': {
        ...options,
        'rpc': {
          ...rpc,
          'transport': <Object?, Object?>{...transport, 7: 'invalid'},
        },
      },
      for (final value in [null, true, 7, <Object?>[], 'websocket'])
        'unsupported transport type $value': {
          ...options,
          'rpc': {
            ...rpc,
            'transport': {...transport, 'type': value},
          },
        },
      for (final key in ['host', 'port'])
        for (final value in [null, true])
          'invalid transport $key $value': {
            ...options,
            'rpc': {
              ...rpc,
              'transport': {...transport, key: value},
            },
          },
      for (final key in [
        'realm',
        'service_auth_id',
        'service_auth_secret_file',
      ])
        for (final value in [null, true])
          'invalid rpc $key $value': {
            ...options,
            'rpc': {...rpc, key: value},
          },
      for (final value in [null, true])
        'invalid token file $value': {...options, 'auth_token_file': value},
    };
    for (final entry in invalidOptions.entries) {
      test('rejects ${entry.key} without throwing', () {
        final invalid = AuthenticatorDefinition(
          type: 'remote',
          options: entry.value,
        );
        expect(
          RemoteAuthBenchHarness.supports(
            settings.copyWith(
              authenticators: {
                'remote-ticket': invalid,
              },
            ),
          ),
          isFalse,
        );
        expect(
          RemoteAuthBenchHarness.supports(
            settings.copyWith(
              authenticators: {
                'invalid-first': invalid,
                ...settings.authenticators,
              },
            ),
          ),
          isTrue,
          reason: 'an invalid candidate must not hide a later usable service',
        );
      });
    }
    test('requires a matching ticket realm and remote authenticator', () {
      expect(
        RemoteAuthBenchHarness.supports(settings.copyWith(realms: [])),
        isFalse,
      );
      expect(
        RemoteAuthBenchHarness.supports(
          settings.copyWith(
            authenticators: {
              'different-name': settings.authenticators['remote-ticket']!,
            },
          ),
        ),
        isFalse,
      );
      expect(
        RemoteAuthBenchHarness.supports(
          settings.copyWith(
            authenticators: {
              'remote-ticket': AuthenticatorDefinition(
                type: 'ticket',
                options: options,
              ),
            },
          ),
        ),
        isFalse,
      );
      final realm =
          (RealmSettingsBuilder('not-ticket')..addAuthMethod(
                'wampcra',
                options: {'authenticator': 'remote-ticket'},
              ))
              .build();
      expect(
        RemoteAuthBenchHarness.supports(settings.copyWith(realms: [realm])),
        isFalse,
      );
    });
  });
}

RouterSettings _buildRemoteAuthSettings() {
  final listener = ListenerSettingsBuilder('websocket', '127.0.0.1:0')
    ..setPath('/ws')
    ..addAuthMethod('ticket')
    ..addProtocol(ListenerProtocol.websocket)
    ..setWebSocketOptions(
      const WebSocketListenerSettings(subprotocols: <String>['wamp.2.json']),
    );

  final builder = RouterSettingsBuilder()
    ..addRealmFromBuilder(
      RealmSettingsBuilder('bench.remote_auth')
        ..setLimits(const RealmLimitSettings())
        ..addAuthMethod(
          'ticket',
          options: const <String, Object?>{'authenticator': 'remote-ticket'},
        )
        ..addRoleFromBuilder(
          RoleSettingsBuilder(RemoteAuthBenchHarness.defaultAuthRole)
            ..addPermissionFromBuilder(
              PermissionSettingsBuilder('bench.')
                ..setMatchPolicy(PermissionMatchPolicy.prefix)
                ..allowOperations(const <String>['call']),
            ),
        ),
    )
    ..addListenerFromBuilder(listener)
    ..addAuthenticator(
      'remote-ticket',
      const AuthenticatorDefinition(
        type: 'remote',
        options: <String, Object?>{
          'auth_token_file': 'native/bench/remote_auth_token.txt',
          'rpc': <String, Object?>{
            'realm': 'connectanum.authenticate',
            'service_auth_id': 'auth-service',
            'service_auth_secret_file':
                'native/bench/remote_auth_service_ticket.txt',
            'transport': <String, Object?>{
              'type': 'rawsocket',
              'host': '127.0.0.1',
              'port': 8082,
              'ssl': true,
              'serializer': 'json',
              'tls': <String, Object?>{
                'ca_certificates_file':
                    'packages/connectanum_router/test/certs/remote_auth_ca_cert.pem',
                'client_certificate_file':
                    'packages/connectanum_router/test/certs/remote_auth_client_cert.pem',
                'client_private_key_file':
                    'packages/connectanum_router/test/certs/remote_auth_client_key.pem',
              },
            },
          },
        },
      ),
    );
  return builder.build();
}
