@TestOn('vm')
library;

import 'dart:io';

import 'package:connectanum_router/src/router/auth/remote_authenticator.dart';
import 'package:connectanum_router/src/router/auth/remote_wamp_delegate.dart';
import 'package:connectanum_router/src/router/config/authenticator.dart';
import 'package:connectanum_router/src/router/config/router_settings_builder.dart';
import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:test/test.dart';

void main() {
  group('collectRemoteWampDelegateConfigsForSettings', () {
    test('collects and deduplicates remote rpc delegates across realms', () {
      final settings = RouterSettingsBuilder()
          .addAuthenticator(
            'remote-ticket',
            AuthenticatorDefinition(
              type: 'remote',
              options: <String, Object?>{
                'rpc': <String, Object?>{
                  'transport': <String, Object?>{
                    'type': 'websocket',
                    'url': 'wss://127.0.0.1:8080/ws',
                    'tls': <String, Object?>{
                      'ca_certificates_file': _fixturePath(
                        'remote_auth_ca_cert.pem',
                      ),
                      'client_certificate_file': _fixturePath(
                        'remote_auth_client_cert.pem',
                      ),
                      'client_private_key_file': _fixturePath(
                        'remote_auth_client_key.pem',
                      ),
                    },
                  },
                },
              },
            ),
          )
          .addRealmFromBuilder(
            RealmSettingsBuilder('realm1')..addAuthMethod(
              'ticket',
              options: const <String, Object?>{
                'authenticator': 'remote-ticket',
              },
            ),
          )
          .addRealmFromBuilder(
            RealmSettingsBuilder('realm2')
              ..addAuthMethod(
                'ticket',
                options: const <String, Object?>{
                  'authenticator': 'remote-ticket',
                },
              )
              ..addAuthMethod('anonymous'),
          )
          .addRealmFromBuilder(
            RealmSettingsBuilder('realm3')..addAuthMethod(
              'ticket',
              options: const <String, Object?>{
                'delegates': <String>['in-process'],
              },
            ),
          )
          .build();

      final configs = collectRemoteWampDelegateConfigsForSettings(
        settings,
      ).toList(growable: false);

      expect(configs, hasLength(1));
      expect(configs.single.transport.url, 'wss://127.0.0.1:8080/ws');
    });
  });

  group('RemoteWampDelegateConfig', () {
    test('rejects insecure websocket transport without explicit opt-in', () {
      expect(
        () => RemoteWampDelegateConfig.parse({
          'rpc': <String, Object?>{
            'transport': <String, Object?>{
              'type': 'websocket',
              'url': 'ws://127.0.0.1:8080/ws',
            },
          },
        }, _realm()),
        throwsArgumentError,
      );
    });

    test('allows insecure websocket transport when explicitly configured', () {
      final config = RemoteWampDelegateConfig.parse({
        'rpc': <String, Object?>{
          'transport': <String, Object?>{
            'type': 'websocket',
            'url': 'ws://127.0.0.1:8080/ws',
            'tls': const <String, Object?>{'allow_insecure_transport': true},
          },
        },
      }, _realm());

      expect(config.transport.url, 'ws://127.0.0.1:8080/ws');
      expect(config.transport.tls.allowInsecureTransport, isTrue);
    });

    test('parses internal transport without socket coordinates', () {
      final config = RemoteWampDelegateConfig.parse({
        'rpc': <String, Object?>{
          'realm': 'connectanum.authenticate',
          'transport': <String, Object?>{'type': 'internal'},
        },
      }, _realm());

      expect(config.realm, 'connectanum.authenticate');
      expect(config.transport.type, 'internal');
      expect(config.transport.host, isNull);
      expect(config.transport.port, isNull);
      expect(config.transport.url, isNull);
    });

    test('rejects insecure rawsocket transport without explicit opt-in', () {
      expect(
        () => RemoteWampDelegateConfig.parse({
          'rpc': <String, Object?>{
            'transport': <String, Object?>{
              'type': 'rawsocket',
              'host': '127.0.0.1',
              'port': 7000,
            },
          },
        }, _realm()),
        throwsArgumentError,
      );
    });

    test('requires client certificate and key together', () {
      expect(
        () => RemoteWampDelegateConfig.parse({
          'rpc': <String, Object?>{
            'transport': <String, Object?>{
              'type': 'websocket',
              'url': 'wss://127.0.0.1:8080/ws',
              'tls': <String, Object?>{
                'client_certificate_file': _fixturePath(
                  'remote_auth_client_cert.pem',
                ),
              },
            },
          },
        }, _realm()),
        throwsArgumentError,
      );
    });

    test('rotates auth token separately from connection fingerprint', () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'connectanum_remote_delegate_test_',
      );
      addTearDown(() async {
        if (tempDirectory.existsSync()) {
          await tempDirectory.delete(recursive: true);
        }
      });

      final authTokenFile = File('${tempDirectory.path}/auth_token.txt')
        ..writeAsStringSync('shared-token');
      final serviceSecretFile = File('${tempDirectory.path}/service_secret.txt')
        ..writeAsStringSync('service-ticket-v1');

      final config = RemoteWampDelegateConfig.parse({
        'auth_token_file': authTokenFile.path,
        'rpc': <String, Object?>{
          'service_auth_method': 'ticket',
          'service_auth_secret_file': serviceSecretFile.path,
          'transport': <String, Object?>{
            'type': 'websocket',
            'url': 'wss://127.0.0.1:8080/ws',
            'tls': <String, Object?>{
              'ca_certificates_file': _fixturePath('remote_auth_ca_cert.pem'),
              'client_certificate_file': _fixturePath(
                'remote_auth_client_cert.pem',
              ),
              'client_private_key_file': _fixturePath(
                'remote_auth_client_key.pem',
              ),
            },
          },
        },
      }, _realm());

      final fingerprintBefore = await config.connectionFingerprint();
      expect(await config.resolveAuthToken(), 'shared-token');
      expect(await config.buildAuthenticationMethods(), hasLength(1));
      expect(await config.transport.tls.buildSecurityContext(), isNotNull);

      await authTokenFile.writeAsString('rotated-token');
      expect(await config.resolveAuthToken(), 'rotated-token');
      expect(await config.connectionFingerprint(), fingerprintBefore);

      await serviceSecretFile.writeAsString('service-ticket-v2');
      expect(
        await config.connectionFingerprint(),
        isNot(equals(fingerprintBefore)),
      );
    });
  });

  group('RemoteWampProcedureDelegate', () {
    test('forwards negotiated transport metadata in hello payloads', () async {
      Map<String, Object?>? capturedPayload;
      final delegate = RemoteWampProcedureDelegate(
        call: (procedure, {argumentsKeywords}) async {
          expect(procedure, 'authenticate.hello');
          capturedPayload = argumentsKeywords;
          return const RemoteWampProcedureCallResult(
            argumentsKeywords: <String, Object?>{
              'status': 'success',
              'authId': 'user-1',
              'authRole': 'member',
            },
          );
        },
      );
      final realm = _realm();

      final response = await delegate.onHello(
        RemoteHelloRequest(
          realmSettings: realm,
          context: AuthenticatorContext(
            realm: realm,
            sessionId: 123,
            transport: const TransportMetadata(
              connectionId: 456,
              peerAddress: '127.0.0.1:54321',
              isEncrypted: true,
              protocol: 'websocket',
              websocketProtocol: 'wamp.2.cbor',
              websocketSerializer: 'cbor',
            ),
            helloDetails: const <String, Object?>{
              'authid': 'user-1',
              'authmethods': <String>['ticket'],
            },
          ),
          options: const <String, Object?>{},
          transactionId: 'txn-1',
        ),
      );

      expect(response.status, RemoteHelloStatus.success);
      final hello = capturedPayload?['hello'] as Map<String, Object?>?;
      final transport = hello?['transport'] as Map<String, Object?>?;
      expect(transport, containsPair('connectionId', 456));
      expect(transport, containsPair('peerAddress', '127.0.0.1:54321'));
      expect(transport, containsPair('isEncrypted', true));
      expect(transport, containsPair('protocol', 'websocket'));
      expect(transport, containsPair('websocketProtocol', 'wamp.2.cbor'));
      expect(transport, containsPair('websocketSerializer', 'cbor'));
    });
  });
}

RealmSettings _realm() => RealmSettingsBuilder('realm1').build();

String _fixturePath(String fileName) {
  final candidates = <String>[
    'packages/connectanum_router/test/certs/$fileName',
    'test/certs/$fileName',
    fileName,
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }
  throw StateError('Missing router test certificate $fileName');
}
