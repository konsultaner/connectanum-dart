@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';

import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_router/src/router/auth/remote_wamp_delegate.dart';
import 'package:connectanum_router/src/router/config/router_settings_builder.dart';
import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:test/test.dart';

import '../../connectanum_core/test/authentication/cryptosign/keys.dart';

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
    for (final outer in [null, false, true]) {
      for (final inner in [null, false, true]) {
        test(
          'TLS certificate opt-in outer=$outer inner=$inner is explicit',
          () {
            final config = _config({
              'transport': {
                'type': 'websocket',
                'url': 'wss://localhost',
                'allow_insecure_certificates': outer,
                'tls': {'allow_insecure_certificates': inner},
              },
            });
            expect(
              config.transport.tls.allowInsecureCertificates,
              outer == true || inner == true,
            );
            expect(config.transport.tls.allowInsecureTransport, isFalse);
            expect(config.transport.ssl, isFalse);
          },
        );
      }
    }

    test(
      'rawsocket retains explicit TLS while insecure opt-in stays separate',
      () {
        for (final ssl in [false, true]) {
          final config = _config({
            'transport': {
              'type': 'rawsocket',
              'host': 'localhost',
              'port': 7000,
              'ssl': ssl,
              'allow_insecure_transport': true,
            },
          });
          expect(config.transport.ssl, ssl);
        }
        expect(
          _config({
            'transport': {
              'type': 'rawsocket',
              'host': 'localhost',
              'port': 7000,
              'ssl': true,
            },
          }).transport.ssl,
          isTrue,
        );
      },
    );

    test(
      'inline token identities have separate registry entries without plaintext cache keys',
      () {
        final first = _config({'auth_token': 'fixture-token-one'});
        final second = _config({'auth_token': 'fixture-token-two'});
        expect(first.cacheKey(), isNot(second.cacheKey()));
        expect(first.cacheKey(), isNot(contains('fixture-token-one')));
        expect(second.cacheKey(), isNot(contains('fixture-token-two')));
        final firstDelegate = RemoteWampDelegateRegistry.forConfig(first);
        expect(
          RemoteWampDelegateRegistry.forConfig(first),
          same(firstDelegate),
        );
        expect(
          RemoteWampDelegateRegistry.forConfig(second),
          isNot(same(firstDelegate)),
        );
        RemoteWampDelegateRegistry.clear();
      },
    );

    test(
      'CA-only TLS configuration still builds a custom trust context',
      () async {
        final config = _config({
          'transport': {
            'type': 'websocket',
            'url': 'wss://localhost',
            'tls': {
              'ca_certificates_file': _fixturePath('remote_auth_ca_cert.pem'),
            },
          },
        });
        expect(await config.transport.tls.buildSecurityContext(), isNotNull);
      },
    );

    test('trims explicit routing, identity and transport configuration', () {
      final config = _config({
        'realm': ' auth.realm ',
        'hello_procedure': ' auth.hello ',
        'authenticate_procedure': ' auth.proof ',
        'abort_procedure': ' auth.abort ',
        'service_auth_id': ' edge ',
        'service_auth_role': ' service ',
        'service_auth_extra': {'node': 17},
        'connect_timeout_ms': 1250.9,
        'call_timeout_ms': 250,
      });
      expect(config.realm, 'auth.realm');
      expect(config.helloProcedure, 'auth.hello');
      expect(config.authenticateProcedure, 'auth.proof');
      expect(config.abortProcedure, 'auth.abort');
      expect(config.authId, 'edge');
      expect(config.authRole, 'service');
      expect(config.authExtra, {'node': 17});
      expect(config.connectTimeout, const Duration(milliseconds: 1250));
      expect(config.callTimeout, const Duration(milliseconds: 250));
    });

    for (final value in [null, 0, -1]) {
      test('uses bounded default timeouts for $value', () {
        final config = _config({
          'connect_timeout_ms': value,
          'call_timeout_ms': value,
        });
        expect(config.connectTimeout, const Duration(seconds: 5));
        expect(config.callTimeout, const Duration(seconds: 5));
      });
    }

    for (final options in <Map<String, Object?>>[
      {'call_timeout_ms': '100'},
      {'connect_timeout_ms': true},
      {'service_auth_extra': []},
      {'service_auth_method': 'unsupported'},
      {'service_auth_method': 'ticket'},
      {'service_auth_method': 'cryptosign'},
      {'auth_token': 7},
      {'auth_token_file': true},
      {'auth_token': 'inline', 'auth_token_file': 'file'},
    ]) {
      test('rejects invalid RPC options $options', () {
        expect(() => _config(options), throwsArgumentError);
      });
    }

    for (final transport in <Map<String, Object?>>[
      {},
      {'type': ' '},
      {'type': 'udp'},
      {'type': 'rawsocket', 'port': 7000, 'ssl': true},
      {'type': 'rawsocket', 'host': 'localhost', 'port': '7000', 'ssl': true},
      {'type': 'websocket'},
      {'type': 'websocket', 'url': 'wss://localhost', 'tls': []},
      {
        'type': 'websocket',
        'url': 'wss://localhost',
        'tls': {'client_private_key': 'unpaired'},
      },
    ]) {
      test('rejects invalid transport $transport', () {
        expect(() => _config({'transport': transport}), throwsArgumentError);
      });
    }

    test('requires RPC and transport maps', () {
      expect(
        () => RemoteWampDelegateConfig.parse({}, _realm()),
        throwsArgumentError,
      );
      expect(() => _config({'transport': []}), throwsArgumentError);
    });

    test(
      'retains headers and builds client-only TLS context with system roots',
      () async {
        final config = _config({
          'transport': {
            'type': 'websocket',
            'url': 'wss://localhost',
            'headers': {'X-Edge': 'fixture'},
            'tls': {
              'client_certificate_file': _fixturePath(
                'remote_auth_client_cert.pem',
              ),
              'client_private_key_file': _fixturePath(
                'remote_auth_client_key.pem',
              ),
            },
          },
        });
        expect(config.transport.headers, {'X-Edge': 'fixture'});
        expect(await config.transport.tls.buildSecurityContext(), isNotNull);
        expect(config.transport.cacheKeyMap()['headers'], {
          'X-Edge': 'fixture',
        });
        expect((await config.transport.fingerprintMap())['headers'], {
          'X-Edge': 'fixture',
        });
      },
    );

    test(
      'token fallback and empty values preserve anonymous service defaults',
      () async {
        final config = RemoteWampDelegateConfig.parse({
          'auth_token': ' fallback ',
          'rpc': {
            'auth_token': ' ',
            'auth_token_file': null,
            'service_auth_id': ' ',
            'service_auth_role': '',
            'service_auth_method': 'anonymous',
            'transport': {'type': 'websocket', 'url': 'wss://localhost'},
          },
        }, _realm());
        expect(await config.resolveAuthToken(), 'fallback');
        expect(await config.buildAuthenticationMethods(), isEmpty);
        expect(config.authId, isNull);
        expect(config.authRole, isNull);
        expect(await config.transport.tls.buildSecurityContext(), isNull);
        expect(await _config({}).resolveAuthToken(), isNull);
      },
    );

    for (final method in ['ticket', 'wampcra', 'wamp-scram']) {
      test('builds $method using a freshly resolved secret', () async {
        final temp = Directory.systemTemp.createTempSync('remote-secret-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final file = File('${temp.path}/secret')..writeAsStringSync(' first\n');
        final config = _config({
          'service_auth_method': method,
          'service_auth_secret_file': file.path,
        });
        final first = (await config.buildAuthenticationMethods()).single;
        expect(first.getName(), method);
        expect(switch (first) {
          core.TicketAuthentication value => value.password,
          core.CraAuthentication value => value.secret,
          core.ScramAuthentication value => value.secret,
          _ => null,
        }, 'first');
        final fingerprint = await config.connectionFingerprint();
        final cacheKey = config.cacheKey();
        file.writeAsStringSync('second');
        final second = (await config.buildAuthenticationMethods()).single;
        expect(switch (second) {
          core.TicketAuthentication value => value.password,
          core.CraAuthentication value => value.secret,
          core.ScramAuthentication value => value.secret,
          _ => null,
        }, 'second');
        if (first is core.ScramAuthentication) await first.dispose();
        if (second is core.ScramAuthentication) await second.dispose();
        expect(await config.connectionFingerprint(), isNot(fingerprint));
        expect(config.cacheKey(), cacheKey);
        file.writeAsStringSync(' \n');
        await expectLater(
          config.buildAuthenticationMethods(),
          throwsStateError,
        );
        file.deleteSync();
        await expectLater(
          config.buildAuthenticationMethods(),
          throwsStateError,
        );
      });
    }

    final seed = <int>[
      21,
      231,
      131,
      235,
      144,
      223,
      174,
      67,
      207,
      102,
      183,
      246,
      209,
      212,
      255,
      255,
      231,
      43,
      210,
      219,
      99,
      206,
      211,
      62,
      171,
      220,
      16,
      225,
      62,
      227,
      254,
      221,
    ];
    final keys = {
      'base64': base64Encode(seed),
      'hex': seed.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      'openssh': MockKeys.ed25519Key.value,
      'putty': MockKeys.ed25519OpensshPpk.value,
      'pkcs8': MockKeys.ed25519OpensshPkcs8.value,
    };
    for (final entry in keys.entries) {
      test(
        'builds cryptosign ${entry.key} without changing key material',
        () async {
          final config = _config({
            'service_auth_method': 'cryptosign',
            'service_private_key': entry.value,
            'service_private_key_format': entry.key,
          });
          final auth =
              (await config.buildAuthenticationMethods()).single
                  as core.CryptosignAuthentication;
          expect(auth.getName(), 'cryptosign');
          expect(auth.privateKey.sublist(0, 32), seed);
        },
      );
    }
    test(
      'rejects unsupported cryptosign key format before connecting',
      () async {
        final config = _config({
          'service_auth_method': 'cryptosign',
          'service_private_key': keys['base64'],
          'service_private_key_format': 'unsupported',
        });
        await expectLater(
          config.buildAuthenticationMethods(),
          throwsArgumentError,
        );
      },
    );

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
}

RealmSettings _realm() => RealmSettingsBuilder('realm1').build();

RemoteWampDelegateConfig _config(Map<String, Object?> rpc) =>
    RemoteWampDelegateConfig.parse({
      'rpc': {
        'transport': {'type': 'websocket', 'url': 'wss://localhost'},
        ...rpc,
      },
    }, _realm());

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
