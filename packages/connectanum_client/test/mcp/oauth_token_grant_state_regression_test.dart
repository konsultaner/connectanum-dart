@TestOn('vm')
library;

import 'dart:convert';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

const _secret = 'fixture-credential-do-not-log';
final _issuedAt = DateTime.utc(2020, 1, 1);

Map<String, Object?> _state() => {
  'type': 'mcp_oauth_token_grant',
  'version': 1,
  'issued_at': '2020-01-01T00:00:00.000Z',
  'expires_in': 60,
  'expires_at': '2020-01-01T00:01:00.000Z',
  'authorization_server': {
    'issuer': 'https://auth.example/issuer',
    'authorization_endpoint': 'https://auth.example/authorize',
    'token_endpoint': 'https://auth.example/token',
    'response_types_supported': ['code'],
    'grant_types_supported': ['authorization_code', 'refresh_token'],
    'code_challenge_methods_supported': ['S256'],
    'token_endpoint_auth_methods_supported': [
      'none',
      'client_secret_basic',
      'client_secret_post',
    ],
  },
  'resource': 'https://resource.example/mcp?tenant=one',
  'client_id': 'consumer-client',
  'scopes': ['tools:read', 'prompts:read'],
  'tokens': <String, Object?>{
    'access_token': _secret,
    'token_type': 'Bearer',
    'refresh_token': 'fixture-refresh',
    'extension': {
      'nested': [
        1,
        true,
        null,
        {'label': 'original'},
      ],
    },
  },
};

McpOAuthTokenGrant _restore(Map<String, Object?> state) =>
    McpOAuthTokenGrant.fromJson(state, now: _issuedAt);

void _reject(Map<String, Object?> state) {
  expect(
    () => _restore(state),
    throwsA(
      isA<McpOAuthTokenGrantStateException>().having(
        (error) => error.toString(),
        'redacted diagnostic',
        isNot(contains(_secret)),
      ),
    ),
  );
}

void main() {
  test(
    'independent persisted fixture restores binding, tokens and deadline',
    () {
      final grant = McpOAuthTokenGrant.fromJson(
        _state(),
        now: _issuedAt,
        expectedAuthorizationServerIssuer: Uri.parse(
          'https://auth.example/issuer',
        ),
        expectedResource: Uri.parse(
          'https://resource.example:443/mcp?tenant=one',
        ),
        expectedClientId: 'consumer-client',
      );
      expect(grant.accessToken, _secret);
      expect(grant.refreshToken, 'fixture-refresh');
      expect(grant.clientId, 'consumer-client');
      expect(
        grant.resource.toString(),
        'https://resource.example/mcp?tenant=one',
      );
      expect(grant.scopes, ['tools:read', 'prompts:read']);
      expect(grant.issuedAt, _issuedAt);
      expect(grant.expiresIn, const Duration(seconds: 60));
      expect(grant.expiresAt, DateTime.utc(2020, 1, 1, 0, 1));
      expect(grant.isAccessTokenExpired(now: _issuedAt), isFalse);
      expect(
        grant.isAccessTokenExpired(now: DateTime.utc(2020, 1, 1, 0, 1)),
        isTrue,
      );
      expect(grant.toString(), isNot(contains(_secret)));
      expect(grant.toString(), isNot(contains('fixture-refresh')));
      final reloaded = _restore(
        (jsonDecode(jsonEncode(grant.toJson())) as Map).cast<String, Object?>(),
      );
      expect(reloaded.toJson(), grant.toJson());
    },
  );

  for (final field in [
    'type',
    'version',
    'issued_at',
    'expires_at',
    'resource',
    'client_id',
  ]) {
    for (final value in <Object?>[
      null,
      '',
      false,
      <Object?>[],
      <String, Object?>{},
    ]) {
      test('$field rejects ${value.runtimeType}=$value', () {
        _reject(_state()..[field] = value);
      });
    }
    test('$field must not be absent', () => _reject(_state()..remove(field)));
  }

  for (final field in ['authorization_server', 'tokens']) {
    for (final value in <Object?>[
      null,
      _secret,
      7,
      true,
      <Object?>[],
      <Object, Object?>{7: _secret},
    ]) {
      test('$field rejects non-object/non-string key ${value.runtimeType}', () {
        _reject(_state()..[field] = value);
      });
    }
  }

  for (final field in ['issued_at', 'expires_at']) {
    for (final value in [
      'not-a-date',
      '2020-01-01T00:00:00',
      '2020-01-01T00:00:00+00:00',
      '2020-01-01T01:00:00+01:00',
    ]) {
      test('$field requires a UTC Z timestamp: $value', () {
        _reject(_state()..[field] = value);
      });
    }
  }

  for (final value in [
    '/mcp',
    '//resource.example/mcp',
    'urn:example:mcp',
    'https://',
    'https://[broken',
    'https://resource.example/mcp#',
    'https://resource.example/mcp#fragment',
  ]) {
    test('resource rejects a nonabsolute or fragment URI: $value', () {
      _reject(_state()..['resource'] = value);
    });
  }

  for (final value in <Object?>[-1, 1.5, true, '60', <Object?>[]]) {
    test(
      'expires_in rejects ${value.runtimeType}=$value',
      () => _reject(_state()..['expires_in'] = value),
    );
  }
  test('zero expiry is immediately expired, not an absent deadline', () {
    final grant = _restore(
      _state()
        ..['expires_in'] = 0
        ..['expires_at'] = '2020-01-01T00:00:00.000Z',
    );
    expect(grant.expiresIn, Duration.zero);
    expect(grant.expiresAt, _issuedAt);
    expect(grant.isAccessTokenExpired(now: _issuedAt), isTrue);
    expect(grant.toJson()['expires_in'], 0);
  });
  test('unadvertised expiry remains absent across persistence', () {
    final grant = _restore(
      _state()
        ..remove('expires_in')
        ..remove('expires_at'),
    );
    expect(grant.expiresIn, isNull);
    expect(grant.expiresAt, isNull);
    expect(grant.toJson(), isNot(contains('expires_in')));
    expect(grant.toJson(), isNot(contains('expires_at')));
    expect(grant.isAccessTokenExpired(now: DateTime.utc(2090)), isFalse);
  });

  for (final value in <Object?>[
    null,
    'read',
    1,
    <Object?>[''],
    <Object?>[false],
    <Object?>['tools:read', 1],
    ['read write'],
    ['read\twrite'],
    ['read"write'],
    [r'read\write'],
    ['\u007f'],
    ['\u0080'],
    ['read', 'read'],
  ]) {
    test('scope list rejects malformed or duplicated tokens: $value', () {
      _reject(_state()..['scopes'] = value);
    });
  }
  test('empty scope list remains empty without adding a token scope field', () {
    final grant = _restore(_state()..['scopes'] = <String>[]);
    expect(grant.scopes, isEmpty);
    expect(grant.toJson()['scopes'], isEmpty);
    expect(grant.toJson()['tokens'] as Map, isNot(contains('scope')));
  });

  for (final resource in [
    'http://resource.example/mcp?tenant=one',
    'https://other.example/mcp?tenant=one',
    'https://resource.example:444/mcp?tenant=one',
    'https://resource.example/other?tenant=one',
    'https://resource.example/mcp?tenant=two',
    'https://resource.example/mcp',
    'https://resource.example/mcp?tenant=one#fragment',
    'https://user:password@resource.example/mcp?tenant=one',
  ]) {
    test('restoration rejects a different expected resource: $resource', () {
      expect(
        () => McpOAuthTokenGrant.fromJson(
          _state(),
          now: _issuedAt,
          expectedResource: Uri.parse(resource),
        ),
        throwsA(isA<McpOAuthTokenGrantStateException>()),
      );
    });
  }
  test('resource binding accepts host case and the explicit default port', () {
    final grant = McpOAuthTokenGrant.fromJson(
      _state(),
      now: _issuedAt,
      expectedResource: Uri.parse(
        'https://RESOURCE.example:443/mcp?tenant=one',
      ),
    );
    expect(grant.accessToken, _secret);
    expect(
      grant.resource.toString(),
      'https://resource.example/mcp?tenant=one',
    );
  });

  for (final value in <Object?>[
    null,
    <String, Object?>{},
    <Object?>[],
    <String, Object?>{'nullable': null},
    1.25,
  ]) {
    test('valid JSON extension survives persistence: $value', () {
      final state = _state();
      (state['tokens'] as Map)['extension'] = value;
      final grant = _restore(state);
      expect(grant.additionalParameters, {'extension': value});
      final restored = _restore(
        (jsonDecode(jsonEncode(grant.toJson())) as Map).cast<String, Object?>(),
      );
      expect(restored.additionalParameters, {'extension': value});
      expect(restored.accessToken, _secret);
    });
  }

  for (final key in [
    'expires_in',
    'scope',
    'client_secret',
    'client_assertion',
    'client_assertion_type',
    'registration_access_token',
  ]) {
    test('rejects persisted duplicate/credential parameter $key', () {
      final state = _state();
      (state['tokens'] as Map)[key] = _secret;
      _reject(state);
    });
  }
  for (final value in <Object>[
    Object(),
    <Object, Object?>{false: _secret},
    <Object?>[Object()],
    double.nan,
    double.infinity,
  ]) {
    test('extension rejects non-JSON values: ${value.runtimeType}=$value', () {
      final state = _state();
      (state['tokens'] as Map)['extension'] = value;
      _reject(state);
    });
  }

  test(
    'nested state and serialized documents never alias caller collections',
    () {
      final state = _state();
      final tokens = state['tokens'] as Map;
      final scopes = state['scopes'] as List;
      final extension = tokens['extension'] as Map;
      final nested = extension['nested'] as List;
      final grant = _restore(state);
      final serialized = grant.toJson();
      tokens['access_token'] = 'changed';
      (nested.last as Map)['label'] = 'changed';
      nested.clear();
      extension.clear();
      scopes.clear();
      state.clear();
      expect(grant.accessToken, _secret);
      expect(grant.scopes, ['tools:read', 'prompts:read']);
      expect(grant.additionalParameters, {
        'extension': {
          'nested': [
            1,
            true,
            null,
            {'label': 'original'},
          ],
        },
      });
      expect(serialized, grant.toJson());
      expect(() => grant.scopes.add('admin'), throwsUnsupportedError);
      expect(() => grant.additionalParameters.clear(), throwsUnsupportedError);
      expect(
        () => (grant.additionalParameters['extension'] as Map).clear(),
        throwsUnsupportedError,
      );
      final immutableNested =
          (grant.additionalParameters['extension'] as Map)['nested'] as List;
      expect(() => immutableNested.clear(), throwsUnsupportedError);
      expect(
        () => (immutableNested.last as Map).clear(),
        throwsUnsupportedError,
      );
      expect(() => serialized.clear(), throwsUnsupportedError);
      expect(
        () => (serialized['tokens'] as Map).clear(),
        throwsUnsupportedError,
      );
      expect(
        () => (serialized['scopes'] as List).clear(),
        throwsUnsupportedError,
      );
    },
  );

  for (final method in ['none', 'client_secret_basic', 'client_secret_post']) {
    test(
      '$method client authentication diagnostics contain no credentials',
      () {
        final server = _restore(_state()).authorizationServer;
        final authentication = switch (method) {
          'client_secret_basic' =>
            McpOAuthClientAuthentication.clientSecretBasic(
              clientId: _secret,
              clientSecret: _secret,
              authorizationServer: server,
            ),
          'client_secret_post' => McpOAuthClientAuthentication.clientSecretPost(
            clientId: _secret,
            clientSecret: _secret,
            authorizationServer: server,
          ),
          _ => McpOAuthClientAuthentication.registeredPublic(
            clientId: _secret,
            authorizationServer: server,
          ),
        };
        expect(
          authentication.toString(),
          'McpOAuthClientAuthentication($method)',
        );
        expect(authentication.toString(), isNot(contains(_secret)));
      },
    );
  }
}
