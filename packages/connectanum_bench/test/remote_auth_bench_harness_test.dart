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
