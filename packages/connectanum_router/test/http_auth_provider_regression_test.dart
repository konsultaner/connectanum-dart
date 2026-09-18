import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_router/src/router/auth/http_auth_provider.dart';
import 'package:connectanum_router/src/router/config/authenticator.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const _secret = 'http-auth-regression-secret';
const _future = 4102444800;

void main() {
  test('registry exposes an immutable snapshot and supports replacement', () {
    HttpAuthProviderRegistry.clear();
    addTearDown(HttpAuthProviderRegistry.clear);
    registerDefaultHttpAuthProviders();
    final snapshot = HttpAuthProviderRegistry.factories;
    expect(snapshot.keys, unorderedEquals(['jwt', 'oidc', 'oauth']));
    expect(() => snapshot.clear(), throwsUnsupportedError);
    registerDefaultHttpAuthProviders();
    expect(HttpAuthProviderRegistry.factoryFor('jwt'), same(snapshot['jwt']));
    const replacement = _ReplacementJwtFactory();
    HttpAuthProviderRegistry.registerFactory(replacement);
    registerDefaultHttpAuthProviders();
    expect(HttpAuthProviderRegistry.factoryFor('jwt'), same(replacement));
    HttpAuthProviderRegistry.unregisterFactory('jwt');
    expect(HttpAuthProviderRegistry.factoryFor('jwt'), isNull);
    expect(snapshot['jwt'], isNotNull);
    registerDefaultHttpAuthProviders();
    expect(
      HttpAuthProviderRegistry.factoryFor('jwt'),
      isA<JwtHttpAuthProviderFactory>(),
    );
  });

  for (final factory in const <HttpAuthProviderFactory>[
    JwtHttpAuthProviderFactory(),
    OidcHttpAuthProviderFactory(),
  ]) {
    group(factory.type, () {
      for (final signature in ['%', 'a', '***']) {
        test('rejects malformed signature $signature and recovers', () async {
          final provider = await factory.create({'hmac_secret': _secret});
          final valid = _jwt({'sub': 'member'});
          final segments = valid.split('.');
          final result = await provider.authenticate(
            _request('${segments[0]}.${segments[1]}.$signature'),
          );
          _expectFailure(result, 'invalid_token');
          expect(
            (await provider.authenticate(_request(valid))).success,
            isTrue,
          );
        });
      }

      for (final claim in ['exp', 'nbf']) {
        for (final invalid in <Object?>[
          null,
          true,
          'not-a-date',
          '$_future',
          <Object?>[],
          <String, Object?>{},
          8640000000001,
          -8640000000001,
          1e100,
        ]) {
          test('rejects malformed $claim=${jsonEncode(invalid)}', () async {
            final provider = await factory.create({'hmac_secret': _secret});
            final result = await provider.authenticate(
              _request(_jwt({'sub': 'member', claim: invalid})),
            );
            _expectFailure(result, 'invalid_token');
            expect(
              (await provider.authenticate(
                _request(_jwt({'sub': 'member'})),
              )).success,
              isTrue,
            );
          });
        }
      }

      test(
        'preserves fractional JWT expiry and permits absent dates',
        () async {
          final provider = await factory.create({'hmac_secret': _secret});
          final dated = await provider.authenticate(
            _request(
              _jwt({'sub': 'member', 'exp': _future + 0.125, 'nbf': 0.5}),
            ),
          );
          expect(dated.success, isTrue);
          expect(
            dated.authenticated!.expiresAt,
            DateTime.fromMillisecondsSinceEpoch(
              _future * 1000 + 125,
              isUtc: true,
            ),
          );
          final undated = await provider.authenticate(
            _request(_jwt({'sub': 'member'})),
          );
          expect(undated.success, isTrue);
          expect(undated.authenticated!.expiresAt, isNull);
        },
      );

      test(
        'accepts DateTime limits and rejects non-finite NumericDate',
        () async {
          final provider = await factory.create({'hmac_secret': _secret});
          final result = await provider.authenticate(
            _request(
              _jwt({
                'sub': 'member',
                'exp': 8640000000000,
                'nbf': -8640000000000,
              }),
            ),
          );
          expect(result.success, isTrue);
          expect(
            result.authenticated!.expiresAt!.microsecondsSinceEpoch,
            8640000000000000000,
          );
          for (final value in ['1e999', '-1e999']) {
            _expectFailure(
              await provider.authenticate(
                _request(
                  _signedJson(
                    '{"alg":"HS256"}',
                    '{"sub":"member","exp":$value}',
                  ),
                ),
              ),
              'invalid_token',
            );
          }
        },
      );

      test('rejects expired and not-yet-valid tokens', () async {
        final provider = await factory.create({'hmac_secret': _secret});
        _expectFailure(
          await provider.authenticate(
            _request(_jwt({'sub': 'member', 'exp': 0})),
          ),
          'expired_token',
        );
        _expectFailure(
          await provider.authenticate(
            _request(_jwt({'sub': 'member', 'nbf': _future})),
          ),
          'inactive_token',
        );
      });

      test('clock skew does not overflow valid numeric date limits', () async {
        final provider = await factory.create({
          'hmac_secret': _secret,
          'leeway_seconds': 60,
        });
        for (final claims in [
          {'sub': 'member', 'exp': 8640000000000},
          {'sub': 'member', 'nbf': -8640000000000},
        ]) {
          final result = await provider.authenticate(_request(_jwt(claims)));
          expect(result.success, isTrue);
          expect(result.authenticated!.authId, 'member');
        }
      });

      test(
        'maps explicit claims and aliases without losing metadata',
        () async {
          final provider = await factory.create({
            'provider_name': 'alias-provider',
            'shared_secret': _secret,
            'subject_claim': 'account',
            'role_claim': 'primary',
            'role_list_claim': 'groups',
            'scope_role_map': {'write': 'scope-role'},
            'default_auth_role': 'fallback-role',
          });
          final claims = <String, Object?>{
            'account': 'alias-user',
            'sub': 'other-user',
            'primary': 'member',
            'groups': ['member', ' reader ', '', null],
            'scope': ['write'],
          };
          final result = await provider.authenticate(_request(_jwt(claims)));
          expect(result.success, isTrue);
          final authenticated = result.authenticated!;
          expect(authenticated.authId, 'alias-user');
          expect(authenticated.authRole, 'member');
          expect(authenticated.authProvider, 'alias-provider');
          expect(authenticated.authMethod, factory.type);
          expect(authenticated.roles, {
            'member': <String, Object?>{},
            'reader': <String, Object?>{},
          });
          expect(authenticated.details, {
            'authprovider': 'alias-provider',
            'authextra': claims,
          });
        },
      );

      for (final identity in ['username', 'client_id']) {
        test('uses $identity fallback and default role', () async {
          final provider = await factory.create({
            'secret': _secret,
            'default_auth_role': 'guest',
            'scope_role_map': {'other': 'admin'},
            'roles_claim': 'groups',
          });
          final result = await provider.authenticate(
            _request(
              _jwt({
                identity: 'fallback-user',
                'scope': ['unmapped'],
                'groups': ' guest ',
              }),
            ),
          );
          expect(result.success, isTrue);
          expect(result.authenticated!.authId, 'fallback-user');
          expect(result.authenticated!.authProvider, factory.type);
          expect(result.authenticated!.authRole, 'guest');
          expect(result.authenticated!.roles.keys, ['guest']);
        });
      }

      test(
        'canonical claim options win and iterable scopes map roles',
        () async {
          final provider = await factory.create({
            'hmac_secret': _secret,
            'auth_id_claim': 'id',
            'subject_claim': 'legacy_id',
            'auth_role_claim': 'primary',
            'role_claim': 'legacy_role',
            'scope_role_map': {'write': 'writer'},
          });
          final result = await provider.authenticate(
            _request(
              _jwt({
                'id': 'canonical',
                'legacy_id': 'legacy',
                'primary': 'member',
                'legacy_role': 'admin',
                'iss': 'unconfigured',
              }),
            ),
          );
          expect(result.success, isTrue);
          expect(result.authenticated!.authId, 'canonical');
          expect(result.authenticated!.authRole, 'member');
          final scoped = await provider.authenticate(
            _request(
              _jwt({
                'sub': 'member',
                'scope': ['unmapped', 'write'],
              }),
            ),
          );
          expect(scoped.success, isTrue);
          expect(scoped.authenticated!.authRole, 'writer');
          expect(scoped.authenticated!.roles, {'writer': <String, Object?>{}});
        },
      );

      test(
        'rejects short signatures rather than accepting a matching prefix',
        () async {
          final provider = await factory.create({'hmac_secret': _secret});
          final parts = _jwt({'sub': 'member'}).split('.');
          final signature = base64Url.decode(base64Url.normalize(parts[2]));
          parts[2] = base64Url
              .encode(signature.sublist(0, 16))
              .replaceAll('=', '');
          _expectFailure(
            await provider.authenticate(_request(parts.join('.'))),
            'invalid_token',
          );
        },
      );

      test('requires a configured secret and a usable identity', () async {
        final missing = await factory.create({'name': 'missing-secret'});
        await expectLater(
          missing.authenticate(_request('token')),
          throwsStateError,
        );
        final provider = await factory.create({'hmac_secret': _secret});
        _expectFailure(
          await provider.authenticate(_request(_jwt({}))),
          'invalid_token',
        );
      });

      for (final token in [
        '',
        'one.two',
        'a.b.c.d',
        'W10.e30.AA',
        'e30.W10.AA',
        '***.e30.AA',
      ]) {
        test('rejects malformed JWT envelope $token', () async {
          final provider = await factory.create({'hmac_secret': _secret});
          _expectFailure(
            await provider.authenticate(_request(token)),
            'invalid_token',
          );
        });
      }

      test('rejects an extra segment on an otherwise valid token', () async {
        final provider = await factory.create({'hmac_secret': _secret});
        final valid = _jwt({'sub': 'member'});
        _expectFailure(
          await provider.authenticate(_request('$valid.extra')),
          'invalid_token',
        );
        expect((await provider.authenticate(_request(valid))).success, isTrue);
      });

      test('empty primary identity uses the next usable claim', () async {
        final provider = await factory.create({'hmac_secret': _secret});
        final result = await provider.authenticate(
          _request(_jwt({'sub': '  ', 'username': 'fallback'})),
        );
        expect(result.success, isTrue);
        expect(result.authenticated!.authId, 'fallback');
      });

      test(
        'negative skew cannot invalidate an otherwise valid token',
        () async {
          final provider = await factory.create({
            'hmac_secret': _secret,
            'leeway_seconds': -3600,
          });
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final result = await provider.authenticate(
            _request(
              _jwt({'sub': 'member', 'exp': now + 600, 'nbf': now - 600}),
            ),
          );
          expect(result.success, isTrue);
        },
      );

      for (final algorithm in <String?>[null, 'none', 'RS256']) {
        test('rejects mismatching header algorithm $algorithm', () async {
          final provider = await factory.create({'hmac_secret': _secret});
          _expectFailure(
            await provider.authenticate(
              _request(
                _jwt(
                  {'sub': 'member'},
                  header: {'alg': ?algorithm},
                ),
              ),
            ),
            'invalid_token',
          );
        });
      }

      for (final audience in <Object?>[
        null,
        '',
        [],
        ['wrong'],
        'wrong',
      ]) {
        test('enforces issuer and audience $audience', () async {
          final provider = await factory.create({
            'hmac_secret': _secret,
            'issuer': 'issuer',
            'audience': ['api'],
          });
          _expectFailure(
            await provider.authenticate(
              _request(_jwt({'sub': 'member', 'iss': 'other', 'aud': 'api'})),
            ),
            'invalid_token',
          );
          _expectFailure(
            await provider.authenticate(
              _request(
                _jwt({'sub': 'member', 'iss': 'issuer', 'aud': audience}),
              ),
            ),
            'invalid_token',
          );
          expect(
            (await provider.authenticate(
              _request(
                _jwt({
                  'sub': 'member',
                  'iss': 'issuer',
                  'aud': ['other', 'api'],
                }),
              ),
            )).success,
            isTrue,
          );
        });
      }

      for (final leeway in <Object?>['60', 60.0, -60, 'invalid']) {
        test('honors configured clock skew $leeway', () async {
          final provider = await factory.create({
            'hmac_secret': _secret,
            'leeway_seconds': leeway,
          });
          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          final result = await provider.authenticate(
            _request(_jwt({'sub': 'member', 'exp': now - 30})),
          );
          if (leeway == '60' || leeway == 60.0) {
            expect(result.success, isTrue);
          } else {
            _expectFailure(result, 'expired_token');
          }
        });
      }
    });
  }

  group('OAuth introspection time claims', () {
    for (final active in <Object?>[false, null, 0, 1, 'true']) {
      test(
        'rejects active=$active with an otherwise usable identity',
        () async {
          final peer = await _IntrospectionPeer.start({
            'active': active,
            'sub': 'member',
            'exp': _future,
          });
          final provider = await peer.provider();
          final result = await provider.authenticate(_request('opaque'));
          _expectFailure(result, 'invalid_token');
          expect(
            result.failure!.message,
            'OAuth introspection reported an inactive token',
          );
          peer.response = {'active': true, 'sub': 'member', 'exp': _future};
          expect(
            (await provider.authenticate(_request('opaque'))).success,
            isTrue,
          );
        },
      );
    }

    for (final allow in <Object?>[
      null,
      true,
      false,
      ' TRUE ',
      'false',
      'invalid',
    ]) {
      test('self-signed TLS requires an explicit opt-in ($allow)', () async {
        final peer = await _IntrospectionPeer.start({
          'active': true,
          'sub': 'member',
        }, secure: true);
        final provider = await peer.provider({'allow_insecure_tls': allow});
        final result = await provider.authenticate(_request('opaque'));
        if (allow == true || allow == ' TRUE ') {
          expect(result.success, isTrue);
          expect(peer.requests, hasLength(1));
        } else {
          _expectFailure(result, 'auth_unavailable');
          expect(peer.requests, isEmpty);
        }
      });
    }

    test(
      'accepts integral numeric dates but rejects non-finite dates',
      () async {
        final peer = await _IntrospectionPeer.start({
          'active': true,
          'sub': 'member',
          'exp': 8640000000000.0,
          'nbf': -8640000000000.0,
        });
        final provider = await peer.provider();
        final result = await provider.authenticate(_request('opaque'));
        expect(result.success, isTrue);
        expect(
          result.authenticated!.expiresAt!.microsecondsSinceEpoch,
          8640000000000000000,
        );
        peer.rawResponse = '{"active":true,"sub":"member","exp":1e999}';
        _expectFailure(
          await provider.authenticate(_request('opaque')),
          'invalid_token_response',
        );
      },
    );

    test(
      'closes the client when synchronous setup exhausts the deadline',
      () async {
        final client = _SlowOpeningClient();
        final provider = await const OAuthIntrospectionHttpAuthProviderFactory()
            .create({
              'url': 'http://127.0.0.1/introspect',
              'timeout_ms': 1,
            });
        final result = await HttpOverrides.runZoned(
          () => provider.authenticate(_request('opaque')),
          createHttpClient: (_) => client,
        );
        _expectFailure(result, 'auth_timeout');
        expect(client.opened, isTrue);
        expect(client.forceClosed, isTrue);
      },
    );

    for (final slowClose in [false, true]) {
      test(
        'observes late errors after setup exhausts deadline (close=$slowClose)',
        () async {
          final client = _SlowOpeningClient(
            fail: true,
            slowClose: slowClose,
            setupDelay: const Duration(milliseconds: 50),
          );
          final provider =
              await const OAuthIntrospectionHttpAuthProviderFactory().create({
                'url': 'http://127.0.0.1/introspect',
                'timeout_ms': 10,
              });
          final errors = <Object>[];
          final done = Completer<void>();
          HttpAuthResult? result;
          runZonedGuarded(() async {
            try {
              result = await HttpOverrides.runZoned(
                () => provider.authenticate(_request('opaque')),
                createHttpClient: (_) => client,
              );
              await Future<void>.delayed(const Duration(milliseconds: 20));
            } finally {
              done.complete();
            }
          }, (error, _) => errors.add(error));
          await done.future;
          expect(
            errors,
            isEmpty,
            reason: 'The started request must be observed',
          );
          _expectFailure(result!, 'auth_timeout');
          expect(client.forceClosed, isTrue);
          expect(client.closing, slowClose);
        },
      );
    }

    for (final (credentials, expected) in <(Map<String, Object?>, String?)>[
      ({}, null),
      ({'bearer_token': '  '}, null),
      ({'client_id': 'service', 'bearer_token': 'fallback'}, 'Bearer fallback'),
      (
        {'client_secret': 'secret', 'bearer_token': 'fallback'},
        'Bearer fallback',
      ),
      (
        {
          'client_id': 'service',
          'client_secret': 'secret',
          'bearer_token': 'ignored',
        },
        'Basic ${base64Encode(utf8.encode('service:secret'))}',
      ),
    ]) {
      test('uses only complete endpoint credentials $credentials', () async {
        final peer = await _IntrospectionPeer.start({
          'active': true,
          'sub': 'member',
          'iss': 'unconstrained-issuer',
        });
        final provider = await peer.provider(credentials);
        expect(
          (await provider.authenticate(_request('opaque'))).success,
          isTrue,
        );
        expect(peer.requests.single['authorization'], expected);
        expect(peer.requests.single['body'], {
          'token': 'opaque',
          'token_type_hint': 'access_token',
        });
      });
    }

    for (final fixedLength in [false, true]) {
      test(
        'enforces the inclusive byte limit (length header=$fixedLength)',
        () async {
          final peer = await _IntrospectionPeer.start({
            'active': true,
            'sub': 'm\u00e9',
          });
          peer.fixedLength = fixedLength;
          final size = utf8.encode(jsonEncode(peer.response)).length;
          final exact = await peer.provider({'max_response_bytes': size});
          final accepted = await exact.authenticate(_request('opaque'));
          expect(accepted.success, isTrue);
          expect(accepted.authenticated!.authId, 'm\u00e9');
          final smaller = await peer.provider({'max_response_bytes': size - 1});
          _expectFailure(
            await smaller.authenticate(_request('opaque')),
            'invalid_token_response',
          );
        },
      );
    }

    test(
      'rejects invalid UTF-8 instead of authenticating replacement text',
      () async {
        final peer = await _IntrospectionPeer.start({
          'active': true,
          'sub': 'member',
        });
        peer.rawBytes = [
          ...utf8.encode('{"active":true,"sub":"'),
          0xc3,
          0x28,
          ...utf8.encode('"}'),
        ];
        final provider = await peer.provider();
        _expectFailure(
          await provider.authenticate(_request('opaque')),
          'invalid_token_response',
        );
        peer.rawBytes = null;
        expect(
          (await provider.authenticate(_request('opaque'))).success,
          isTrue,
        );
      },
    );

    test(
      'rejects oversized declared bodies without subscribing to them',
      () async {
        final response = _BytesResponse(contentLength: 4097);
        final client = _ResponseClient(response);
        final provider = await const OAuthIntrospectionHttpAuthProviderFactory()
            .create({
              'url': 'http://127.0.0.1/introspect',
              'max_response_bytes': 4096,
            });
        final result = await HttpOverrides.runZoned(
          () => provider.authenticate(_request('opaque')),
          createHttpClient: (_) => client,
        );
        _expectFailure(result, 'invalid_token_response');
        expect(response.listened, isFalse);
        expect(client.forceClosed, isTrue);
      },
    );

    for (final claim in ['exp', 'nbf']) {
      for (final invalid in <Object?>[
        null,
        true,
        'not-a-date',
        '$_future',
        <Object?>[],
        <String, Object?>{},
        _future + 0.5,
        8640000000001,
        1e100,
      ]) {
        test('rejects malformed $claim=${jsonEncode(invalid)}', () async {
          final peer = await _IntrospectionPeer.start({
            'active': true,
            'sub': 'member',
            claim: invalid,
          });
          final provider = await peer.provider();
          _expectFailure(
            await provider.authenticate(_request('opaque')),
            'invalid_token_response',
          );
          peer.response = {'active': true, 'sub': 'recovered'};
          final recovered = await provider.authenticate(_request('opaque'));
          expect(recovered.success, isTrue);
          expect(recovered.authenticated!.authId, 'recovered');
          expect(recovered.authenticated!.expiresAt, isNull);
        });
      }
    }

    test('rejects future nbf even when active is true', () async {
      final peer = await _IntrospectionPeer.start({
        'active': true,
        'sub': 'member',
        'nbf': _future,
      });
      final provider = await peer.provider();
      _expectFailure(
        await provider.authenticate(_request('opaque')),
        'inactive_token',
      );
      peer.response = {
        'active': true,
        'sub': 'member',
        'nbf': 0,
        'exp': _future,
      };
      final recovered = await provider.authenticate(_request('opaque'));
      expect(recovered.success, isTrue);
      expect(
        recovered.authenticated!.expiresAt,
        DateTime.fromMillisecondsSinceEpoch(_future * 1000, isUtc: true),
      );
    });

    test(
      'rejects expired, wrong issuer, wrong audience and absent identity',
      () async {
        final peer = await _IntrospectionPeer.start({
          'active': true,
          'sub': 'member',
          'exp': 0,
        });
        final provider = await peer.provider({
          'issuer': 'issuer',
          'audience': 'api',
        });
        _expectFailure(
          await provider.authenticate(_request('opaque')),
          'expired_token',
        );
        for (final claims in [
          {'sub': 'member', 'iss': 'wrong', 'aud': 'api'},
          {'sub': 'member', 'iss': 'issuer', 'aud': 'wrong'},
          {'iss': 'issuer', 'aud': 'api'},
        ]) {
          peer.response = {'active': true, ...claims};
          _expectFailure(
            await provider.authenticate(_request('opaque')),
            'invalid_token',
          );
        }
        peer.response = {
          'active': true,
          'sub': 'member',
          'iss': 'issuer',
          'aud': 'api',
        };
        expect(
          (await provider.authenticate(_request('opaque'))).success,
          isTrue,
        );
      },
    );

    test(
      'sends encoded bearer request with resource and explicit hint',
      () async {
        final peer = await _IntrospectionPeer.start({
          'active': true,
          'sub': 'member',
          'aud': 'api',
        });
        final provider = await peer.provider({
          'introspection_url': null,
          'url': 'http://127.0.0.1:${peer.server.port}/introspect',
          'provider_name': 'introspection-alias',
          'bearer_token': 'service-credential',
          'resource': 'urn:example:api',
          'audience': 'api',
          'token_type_hint': 'refresh_token',
          'timeout_ms': '5000',
          'maxResponseBytes': 4096.0,
        });
        final result = await provider.authenticate(
          _request('opaque + &= token'),
        );
        expect(result.success, isTrue);
        expect(result.authenticated!.authProvider, 'introspection-alias');
        expect(peer.requests.single, {
          'method': 'POST',
          'path': '/introspect',
          'authorization': 'Bearer service-credential',
          'accept': 'application/json',
          'body': {
            'token': 'opaque + &= token',
            'token_type_hint': 'refresh_token',
            'resource': 'urn:example:api',
            'audience': 'api',
          },
        });
      },
    );

    for (final body in <Object?>[null, [], 'private-body', 42]) {
      test(
        'rejects non-object response $body and redacts HTTP failures',
        () async {
          final peer = await _IntrospectionPeer.start(body);
          final provider = await peer.provider();
          _expectFailure(
            await provider.authenticate(_request('private-token')),
            'invalid_token_response',
          );
          peer.statusCode = HttpStatus.unauthorized;
          final result = await provider.authenticate(_request('private-token'));
          _expectFailure(result, 'introspection_failed');
          expect(
            result.failure!.message,
            'Introspection endpoint returned HTTP 401',
          );
        },
      );
    }

    for (final options in <Map<String, Object?>>[
      {},
      {'url': 'http://127.0.0.1', 'timeout_ms': 0},
      {'url': 'http://127.0.0.1', 'max_response_bytes': -1},
      {'url': 'http://127.0.0.1', 'max_response_bytes': 0},
    ]) {
      test('rejects invalid configuration $options', () async {
        final provider = await const OAuthIntrospectionHttpAuthProviderFactory()
            .create(options);
        await expectLater(
          provider.authenticate(_request('opaque')),
          throwsStateError,
        );
      });
    }

    for (final insecureTls in <Object?>[
      true,
      false,
      ' TRUE ',
      'false',
      'invalid',
    ]) {
      test(
        'maps endpoint failure to unavailable with TLS option $insecureTls',
        () async {
          final peer = await _IntrospectionPeer.start({});
          final provider = await peer.provider({
            'allow_insecure_tls': insecureTls,
          });
          await peer.server.close(force: true);
          _expectFailure(
            await provider.authenticate(_request('opaque')),
            'auth_unavailable',
          );
        },
      );
    }
  });
}

void _expectFailure(HttpAuthResult result, String reason) {
  expect(
    result.success,
    isFalse,
    reason: 'Invalid credentials must fail closed',
  );
  expect(result.authenticated, isNull);
  expect(result.failure!.reason, reason);
}

HttpAuthBearerRequest _request(String token) => HttpAuthBearerRequest(
  token: token,
  realmUri: 'test.realm',
  method: 'GET',
  path: '/protected',
  headers: const {},
  transport: const TransportMetadata(
    connectionId: 1,
    peerAddress: '127.0.0.1',
    isEncrypted: true,
  ),
  sessionProfileName: 'http-auth-regression',
);

String _jwt(
  Map<String, Object?> claims, {
  Map<String, Object?> header = const {'alg': 'HS256'},
}) {
  return _signedJson(jsonEncode(header), jsonEncode(claims));
}

String _signedJson(String header, String claims) {
  String encode(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  final unsigned = '${encode(header)}.${encode(claims)}';
  final signature = Hmac(
    sha256,
    utf8.encode(_secret),
  ).convert(utf8.encode(unsigned));
  return '$unsigned.${base64Url.encode(signature.bytes).replaceAll('=', '')}';
}

class _IntrospectionPeer {
  _IntrospectionPeer(this.server, this.response, this.secure);

  final HttpServer server;
  final bool secure;
  Object? response;
  String? rawResponse;
  List<int>? rawBytes;
  bool fixedLength = false;
  int statusCode = HttpStatus.ok;
  final requests = <Map<String, Object?>>[];

  static Future<_IntrospectionPeer> start(
    Object? response, {
    bool secure = false,
  }) async {
    final HttpServer server;
    if (secure) {
      String certificate(String name) {
        final local = File('test/certs/$name');
        return local.existsSync()
            ? local.path
            : 'packages/connectanum_router/test/certs/$name';
      }

      final context = SecurityContext()
        ..useCertificateChain(certificate('remote_auth_server_cert.pem'))
        ..usePrivateKey(certificate('remote_auth_server_key.pem'));
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
    } else {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    }
    addTearDown(() => server.close(force: true));
    final peer = _IntrospectionPeer(server, response, secure);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      peer.requests.add({
        'method': request.method,
        'path': request.uri.path,
        'authorization': request.headers.value(HttpHeaders.authorizationHeader),
        'accept': request.headers.value(HttpHeaders.acceptHeader),
        'body': Uri.splitQueryString(body),
      });
      request.response.statusCode = peer.statusCode;
      request.response.headers.contentType = ContentType.json;
      final bytes =
          peer.rawBytes ??
          utf8.encode(peer.rawResponse ?? jsonEncode(peer.response));
      if (peer.fixedLength) request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    }, onError: (Object error) => expect(error, isA<HandshakeException>()));
    return peer;
  }

  Future<HttpAuthProvider> provider([
    Map<String, Object?> options = const {},
  ]) => const OAuthIntrospectionHttpAuthProviderFactory().create({
    'introspection_url':
        '${secure ? 'https' : 'http'}://127.0.0.1:${server.port}/introspect',
    ...options,
  });
}

class _SlowOpeningClient implements HttpClient {
  _SlowOpeningClient({
    this.fail = false,
    this.slowClose = false,
    this.setupDelay = const Duration(milliseconds: 10),
  });

  final bool fail;
  final bool slowClose;
  final Duration setupDelay;
  bool opened = false;
  bool closing = false;
  bool forceClosed = false;

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    opened = true;
    if (slowClose) {
      return Future.value(
        _ImmediateRequest(() {
          closing = true;
          sleep(setupDelay);
          return Future<HttpClientResponse>.error(
            const HttpException('fixture close failure'),
          );
        }),
      );
    }
    sleep(setupDelay);
    if (fail) {
      return Future<HttpClientRequest>.error(
        const SocketException('fixture connection failure'),
      );
    }
    return Future.value(_ImmediateRequest(() async => _BytesResponse()));
  }

  @override
  void close({bool force = false}) => forceClosed = force;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReplacementJwtFactory extends JwtHttpAuthProviderFactory {
  const _ReplacementJwtFactory();
}

class _ResponseClient implements HttpClient {
  _ResponseClient(this.response);
  final HttpClientResponse response;
  bool forceClosed = false;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async =>
      _ImmediateRequest(() async => response);
  @override
  void close({bool force = false}) => forceClosed = force;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImmediateRequest implements HttpClientRequest {
  _ImmediateRequest(this.respond);
  final Future<HttpClientResponse> Function() respond;
  @override
  final HttpHeaders headers = _RequestHeaders();
  @override
  void write(Object? object) {}
  @override
  Future<HttpClientResponse> close() => respond();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RequestHeaders implements HttpHeaders {
  @override
  set contentType(ContentType? value) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BytesResponse extends Stream<List<int>> implements HttpClientResponse {
  _BytesResponse({this.contentLength = -1});
  @override
  final int contentLength;
  bool listened = false;
  @override
  int get statusCode => HttpStatus.ok;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listened = true;
    return Stream.value(utf8.encode('{"active":true,"sub":"member"}')).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
