import 'dart:convert';
import 'dart:io';

import 'package:connectanum_router/src/router/auth/http_auth_provider.dart';
import 'package:connectanum_router/src/router/config/authenticator.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

const _secret = 'claim-matching-fixture';

void main() {
  for (final profile in ['jwt', 'oidc', 'oauth']) {
    group('$profile exact claim matching', () {
      for (final leeway in profile == 'oauth' ? [0] : [0, 2]) {
        test(
          'expiry is exclusive and not-before inclusive (leeway=$leeway)',
          () async {
            final boundary = DateTime.utc(2030);
            var now = boundary;
            final harness = await _ClaimHarness.create(profile, {
              'leeway_seconds': leeway,
            }, clock: () => now);
            final seconds = boundary.millisecondsSinceEpoch ~/ 1000;
            final expiry = {'sub': 'member', 'exp': seconds};
            now = boundary
                .add(Duration(seconds: leeway))
                .subtract(const Duration(microseconds: 1));
            final accepted = await harness.authenticate(expiry);
            expect(accepted.success, isTrue);
            expect(accepted.authenticated!.expiresAt, boundary);
            now = boundary.add(Duration(seconds: leeway));
            final expired = await harness.authenticate(expiry);
            expect(
              expired.success,
              isFalse,
              reason: 'Expiry is not an inclusive boundary',
            );
            expect(expired.authenticated, isNull);
            expect(expired.failure!.reason, 'expired_token');
            now = now.add(const Duration(microseconds: 1));
            expect(
              (await harness.authenticate(expiry)).failure!.reason,
              'expired_token',
            );

            final activation = {'sub': 'member', 'nbf': seconds};
            now = boundary
                .subtract(Duration(seconds: leeway))
                .subtract(const Duration(microseconds: 1));
            final premature = await harness.authenticate(activation);
            expect(premature.success, isFalse);
            expect(premature.authenticated, isNull);
            expect(premature.failure!.reason, 'inactive_token');
            now = boundary.subtract(Duration(seconds: leeway));
            expect((await harness.authenticate(activation)).success, isTrue);
          },
        );
      }

      for (final (label, expected, actual) in <(String, String, Object?)>[
        ('absent', 'api', null),
        ('number', '42', 42),
        ('boolean', 'true', true),
        ('empty array', '[]', []),
        ('object', '{app: api}', {'app': 'api'}),
        (
          'nested array',
          '[api]',
          [
            ['api'],
          ],
        ),
        ('numeric entry', '42', [42]),
        ('mixed before match', 'api', [null, 'api']),
        ('mixed after match', 'api', ['api', 42]),
        ('object after match', 'api', ['api', <String, Object?>{}]),
        ('leading space', 'api', ' api'),
        ('trailing space', 'api', 'api '),
        ('control padding', 'api', '\tapi\n'),
        ('unicode padding', 'api', '\u00a0api\u00a0'),
        ('padded list member', 'api', [' api ']),
        ('different case', 'api', 'API'),
        ('unicode normalization', 'caf\u00e9', 'cafe\u0301'),
      ]) {
        test('rejects audience $label and recovers', () async {
          final harness = await _ClaimHarness.create(profile, {
            'audience': expected,
          });
          final rejected = await harness.authenticate({
            'sub': 'member',
            if (actual != null) 'aud': actual,
          });
          _expectMismatch(rejected, 'audience', profile);
          final recovered = await harness.authenticate({
            'sub': 'member',
            'aud': expected,
          });
          expect(recovered.success, isTrue);
          expect(recovered.authenticated!.authId, 'member');
        });
      }

      for (final (label, expected, actual) in <(String, String, Object?)>[
        ('absent', 'issuer', null),
        ('number', '42', 42),
        ('boolean', 'true', true),
        ('array', '[issuer]', ['issuer']),
        ('object', '{issuer: value}', {'issuer': 'value'}),
        ('leading space', 'issuer', ' issuer'),
        ('trailing space', 'issuer', 'issuer '),
        ('control padding', 'issuer', '\tissuer\n'),
        ('unicode padding', 'issuer', '\u00a0issuer\u00a0'),
        ('different case', 'issuer', 'ISSUER'),
        ('unicode normalization', 'caf\u00e9', 'cafe\u0301'),
      ]) {
        test('rejects issuer $label and recovers', () async {
          final harness = await _ClaimHarness.create(profile, {
            'issuer': expected,
          });
          final rejected = await harness.authenticate({
            'sub': 'member',
            if (actual != null) 'iss': actual,
          });
          _expectMismatch(rejected, 'issuer', profile);
          expect(
            (await harness.authenticate({
              'sub': 'member',
              'iss': expected,
            })).success,
            isTrue,
          );
        });
      }

      test(
        'accepts exact scalar/list and Unicode claims without changing them',
        () async {
          final harness = await _ClaimHarness.create(profile, {
            'issuer': 'https://issuer.example/caf\u00e9',
            'audience': ['service-a', 'service-\u{1f30d}'],
          });
          for (final audience in <Object>[
            'service-\u{1f30d}',
            ['other', 'service-\u{1f30d}'],
            ['service-a', 'other'],
            ['other', 'service-a', 'service-\u{1f30d}'],
          ]) {
            final claims = {
              'sub': 'member',
              'iss': 'https://issuer.example/caf\u00e9',
              'aud': audience,
            };
            final before = jsonEncode(claims);
            final result = await harness.authenticate(claims);
            expect(result.success, isTrue);
            expect(result.authenticated!.authId, 'member');
            expect(result.authenticated!.details['authextra'], {
              if (profile == 'oauth') 'active': true,
              ...claims,
            });
            expect(jsonEncode(claims), before);
          }
        },
      );

      test(
        'preserves configuration normalization and optional restrictions',
        () async {
          final configured = await _ClaimHarness.create(profile, {
            'issuer': ' issuer ',
            'audience': [' api ', 42],
          });
          for (final audience in ['api', '42']) {
            expect(
              (await configured.authenticate({
                'sub': 'member',
                'iss': 'issuer',
                'aud': audience,
              })).success,
              isTrue,
            );
          }
          final unrestricted = await _ClaimHarness.create(profile, {});
          for (final claims in [
            {'sub': 'member'},
            {
              'sub': 'member',
              'iss': 'other',
              'aud': ['other'],
            },
          ]) {
            expect((await unrestricted.authenticate(claims)).success, isTrue);
          }
        },
      );
    });
  }
}

void _expectMismatch(HttpAuthResult result, String claim, String profile) {
  expect(
    result.success,
    isFalse,
    reason: 'A mismatching claim must fail closed',
  );
  expect(result.authenticated, isNull);
  expect(result.failure!.reason, 'invalid_token');
  expect(
    result.failure!.message,
    '${profile == 'oauth' ? 'OAuth token' : 'JWT'} $claim did not match provider configuration',
  );
}

class _ClaimHarness {
  _ClaimHarness(this.provider, this.oauth);

  final HttpAuthProvider provider;
  final bool oauth;
  Map<String, Object?> claims = {};

  static Future<_ClaimHarness> create(
    String profile,
    Map<String, Object?> options, {
    DateTime Function()? clock,
  }) async {
    if (profile != 'oauth') {
      final HttpAuthProviderFactory factory = profile == 'jwt'
          ? JwtHttpAuthProviderFactory(clock: clock)
          : OidcHttpAuthProviderFactory(clock: clock);
      return _ClaimHarness(
        await factory.create({'hmac_secret': _secret, ...options}),
        false,
      );
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final provider =
        await OAuthIntrospectionHttpAuthProviderFactory(clock: clock).create({
          'introspection_url': 'http://127.0.0.1:${server.port}/introspect',
          ...options,
        });
    final harness = _ClaimHarness(provider, true);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(harness.claims));
      await request.response.close();
    });
    return harness;
  }

  Future<HttpAuthResult> authenticate(Map<String, Object?> input) async {
    claims = {if (oauth) 'active': true, ...input};
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final unsigned = '${encode({'alg': 'HS256'})}.${encode(claims)}';
    final signature = Hmac(
      sha256,
      utf8.encode(_secret),
    ).convert(utf8.encode(unsigned));
    final token = oauth
        ? 'opaque-fixture-token'
        : '$unsigned.${base64Url.encode(signature.bytes).replaceAll('=', '')}';
    final result = await provider
        .authenticate(
          HttpAuthBearerRequest(
            token: token,
            realmUri: 'test.realm',
            method: 'GET',
            path: '/protected',
            headers: const {},
            sessionProfileName: 'claim-matching-regression',
            transport: const TransportMetadata(
              connectionId: 1,
              peerAddress: '127.0.0.1',
              isEncrypted: true,
            ),
          ),
        )
        .then<Object>((value) => value, onError: (Object error) => error);
    expect(
      result,
      isA<HttpAuthResult>(),
      reason:
          'With valid configuration, untrusted claims must return a result, not throw',
    );
    return result as HttpAuthResult;
  }
}
