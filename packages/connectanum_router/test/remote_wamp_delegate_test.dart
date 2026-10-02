@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:connectanum_core/connectanum_core.dart' as core;
import 'package:connectanum_router/src/router/auth/remote_wamp_delegate.dart';
import 'package:connectanum_router/src/router/config/router_settings_builder.dart';
import 'package:connectanum_router/src/router/config/router_settings.dart';
import 'package:test/test.dart';

import '../../connectanum_core/test/authentication/cryptosign/keys.dart';

void _credentialFingerprintContracts() {
  group('credential fingerprint collision regressions', () {
    const secrets = ['remote-fixture-jobs5j', 'remote-fixture-16bqabh'];
    test(
      'different inline tokens never share a delegate after a legacy hash collision',
      () {
        addTearDown(RemoteWampDelegateRegistry.clear);
        final first = _config({'auth_token': secrets[0]});
        final second = _config({'auth_token': secrets[1]});
        expect(first.cacheKey(), isNot(second.cacheKey()));
        expect(
          RemoteWampDelegateRegistry.forConfig(first),
          isNot(same(RemoteWampDelegateRegistry.forConfig(second))),
        );
        for (final config in [first, second]) {
          for (final secret in secrets) {
            expect(config.cacheKey(), isNot(contains(secret)));
          }
        }
      },
    );
    test(
      'colliding file-backed service secrets change the connection fingerprint',
      () async {
        final temp = Directory.systemTemp.createTempSync('remote-collision-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final file = File('${temp.path}/secret')..writeAsStringSync(secrets[0]);
        final config = _config({
          'service_auth_method': 'ticket',
          'service_auth_secret_file': file.path,
        });
        final first = await config.connectionFingerprint();
        final cacheKey = config.cacheKey();
        file.writeAsStringSync(secrets[1]);
        expect(await config.connectionFingerprint(), isNot(first));
        expect(config.cacheKey(), cacheKey);
      },
    );
  });
  // Independent SHA-256 vectors over UTF-16BE, including unpaired surrogates.
  final vectors = <String, String>{
    'secret-A\u0100':
        '8f997a0770b472df1c4d9ad2f112b7aeafba504117df9c2e52c4d9b94611234a',
    'secret-A\u{1f600}':
        '92d4e1ccf42b9d4f82f3d0327013ca69026d481de86a7e64a3cf8c21df03269b',
    'secret-\ud800':
        '04023e603d1e711cdea126e3eb581c708e3bb0d4eb073a52a763b23eca80e50c',
    'secret-\udc00':
        '845a20963500e8975daa922a7cfdcd2624d75beca86ce6cb6dc5c9ed4a84c93f',
    'secret-\ufffd':
        '62d6b9e7f6253c68e61620527339d435ae61df4a7ecd04ddc67453ed13fb9641',
  };
  var index = 0;
  for (final entry in vectors.entries) {
    test(
      'credential fingerprint preserves exact code units vector ${index++}',
      () {
        final key =
            jsonDecode(_config({'auth_token': entry.key}).cacheKey()) as Map;
        expect(key['authToken'], {
          'field': 'auth_token',
          'inlineHash': entry.value,
        });
      },
    );
  }
}

void main() {
  group('remote configuration value contracts', () {
    for (final blank in ['', ' \t\n ']) {
      test(
        'blank routing and serializer values use defaults ${jsonEncode(blank)}',
        () {
          final config = _validParse(
            () => _config({
              'realm': blank,
              'hello_procedure': blank,
              'authenticate_procedure': blank,
              'abort_procedure': blank,
              'service_auth_id': blank,
              'service_auth_role': blank,
              'transport': {
                'type': 'websocket',
                'url': 'wss://localhost',
                'serializer': blank,
              },
            }),
          );
          expect(config.realm, 'connectanum.authenticate');
          expect(config.helloProcedure, 'authenticate.hello');
          expect(config.authenticateProcedure, 'authenticate.authenticate');
          expect(config.abortProcedure, 'authenticate.abort');
          expect(config.transport.serializer, 'json');
          expect(config.authId, isNull);
          expect(config.authRole, isNull);
          expect(config.authExtra, isNull);
          expect(config.callTimeout, const Duration(seconds: 5));
          expect(config.connectTimeout, const Duration(seconds: 5));
        },
      );
    }

    for (final type in ['websocket', 'rawsocket']) {
      for (final secure in [true, false]) {
        for (final certificatePair in [false, true]) {
          test('$type secure=$secure certificatePair=$certificatePair', () {
            final config = _validParse(
              () => _config({
                'transport': {
                  'type': type,
                  if (type == 'websocket')
                    'url': '${secure ? 'wss' : 'ws'}://localhost/ws'
                  else ...{
                    'host': 'localhost',
                    'port': 7000,
                    'ssl': secure,
                  },
                  'tls': {
                    'allow_insecure_transport': !secure,
                    'ca_certificates': 'fixture CA',
                    if (certificatePair) ...{
                      'client_certificate': 'fixture certificate',
                      'client_private_key': 'fixture key',
                    },
                  },
                },
              }),
            );
            expect(config.transport.type, type);
            expect(config.transport.ssl, type == 'rawsocket' && secure);
            expect(config.transport.tls.allowInsecureTransport, !secure);
            expect(config.transport.tls.allowInsecureCertificates, isFalse);
            late final Map<String, Object?> tls;
            try {
              tls = config.transport.tls.cacheKeyMap();
            } on RangeError catch (error) {
              fail('Valid inline credentials must produce a cache key: $error');
            }
            expect(tls['caCertificates'], isA<Map>());
            expect(
              tls['caCertificates'],
              containsPair('inlineHash', matches(r'^[0-9a-f]{64}$')),
            );
            expect(
              tls['clientCertificate'],
              certificatePair ? isNotNull : isNull,
            );
            expect(
              tls['clientPrivateKey'],
              certificatePair ? isNotNull : isNull,
            );
          });
        }
      }
    }

    for (final type in ['websocket', 'rawsocket']) {
      test('top-level insecure opt-in is honored for $type', () {
        final config = _validParse(
          () => _config({
            'transport': {
              'type': type,
              if (type == 'websocket')
                'url': 'ws://localhost'
              else ...{
                'host': 'localhost',
                'port': 7000,
                'ssl': false,
              },
              'allow_insecure_transport': true,
            },
          }),
        );
        expect(config.transport.type, type);
        expect(config.transport.tls.allowInsecureTransport, isTrue);
        expect(config.transport.tls.allowInsecureCertificates, isFalse);
      });
    }

    test('credential file identities never alias in the delegate registry', () {
      addTearDown(RemoteWampDelegateRegistry.clear);
      final first = _validParse(
        () => _config({'auth_token_file': '/fixture/first'}),
      );
      final second = _validParse(
        () => _config({'auth_token_file': '/fixture/second'}),
      );
      expect(first.cacheKey(), isNot(second.cacheKey()));
      final firstDelegate = RemoteWampDelegateRegistry.forConfig(first);
      expect(RemoteWampDelegateRegistry.forConfig(first), same(firstDelegate));
      expect(
        RemoteWampDelegateRegistry.forConfig(second),
        isNot(same(firstDelegate)),
      );
      expect((jsonDecode(first.cacheKey()) as Map)['authToken'], {
        'field': 'auth_token',
        'filePath': '/fixture/first',
      });
    });

    test(
      'unsupported key format is rejected before decoding its value',
      () async {
        final config = _validParse(
          () => _config({
            'service_auth_method': 'cryptosign',
            'service_private_key': 'not-base64!',
            'service_private_key_format': 'unsupported',
          }),
        );
        await expectLater(
          config.buildAuthenticationMethods(),
          throwsArgumentError,
        );
      },
    );

    for (final method in ['ticket', 'wampcra', 'wamp-scram']) {
      test('$method yields one named authentication method', () async {
        final config = _validParse(
          () => _config({
            'service_auth_method': method,
            'service_auth_secret': 'fixture secret',
          }),
        );
        final methods = await config.buildAuthenticationMethods();
        expect(methods, hasLength(1));
        final auth = methods.single;
        if (auth is core.ScramAuthentication) addTearDown(auth.dispose);
        expect(auth.getName(), method);
      });
    }

    for (final type in ['anonymous', 'ticket']) {
      test('non-remote $type definitions do not create RPC delegates', () {
        final settings = RouterSettingsBuilder()
            .addAuthenticator(
              type,
              AuthenticatorDefinition(
                type: type,
                options: {
                  'rpc': {
                    'transport': {
                      'type': 'websocket',
                      'url': 'wss://localhost',
                    },
                  },
                },
              ),
            )
            .addRealmFromBuilder(
              RealmSettingsBuilder('realm1')..addAuthMethod(type),
            )
            .build();
        expect(collectRemoteWampDelegateConfigsForSettings(settings), isEmpty);
      });
    }
    test('anonymous method never warms a configured remote definition', () {
      final settings = RouterSettingsBuilder()
          .addAuthenticator(
            'anonymous',
            AuthenticatorDefinition(
              type: 'remote',
              options: {
                'rpc': {
                  'transport': {'type': 'websocket', 'url': 'wss://localhost'},
                },
              },
            ),
          )
          .addRealmFromBuilder(
            RealmSettingsBuilder('realm1')..addAuthMethod('anonymous'),
          )
          .build();
      expect(collectRemoteWampDelegateConfigsForSettings(settings), isEmpty);
    });
  });

  _credentialFingerprintContracts();
  group('valid remote parser assertion controls', () {
    test('preserves returned identity, null and single evaluation', () {
      var calls = 0;
      final object = Object();
      expect(
        _validParse(() {
          calls++;
          return object;
        }),
        same(object),
      );
      expect(calls, 1);
      expect(_validParse<Object?>(() => null), isNull);
    });
    test('valid fixture rejection is an explicit parser assertion', () {
      expect(
        () => _validParse(() => throw ArgumentError('fixture')),
        throwsA(
          isA<TestFailure>().having(
            (error) => error.message,
            'diagnostic',
            contains('Valid remote configuration must parse'),
          ),
        ),
      );
    });
    for (final error in <Object>[
      StateError('unexpected state'),
      TypeError(),
      const FormatException('unrelated'),
      TimeoutException('timeout'),
      const SocketException('socket'),
      const FileSystemException('file'),
      ProcessException('dart', []),
      UnsupportedError('platform'),
      TestFailure('original assertion'),
      const StackOverflowError(),
      const OutOfMemoryError(),
      Object(),
    ]) {
      test('does not relabel ${error.runtimeType}', () {
        expect(() => _validParse(() => throw error), throwsA(same(error)));
      });
    }
  });

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
        final firstMethods = await config.buildAuthenticationMethods();
        expect(firstMethods, hasLength(1));
        final first = firstMethods.single;
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
        final secondMethods = await config.buildAuthenticationMethods();
        expect(secondMethods, hasLength(1));
        final second = secondMethods.single;
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

// Only the in-memory parser's declared rejection becomes an assertion.
// I/O, key derivation, runtime and resource failures are never wrapped here.
T _validParse<T>(T Function() parse) {
  try {
    return parse();
  } on ArgumentError catch (error) {
    fail('Valid remote configuration must parse: $error');
  }
}

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
