@TestOn('vm')
library;

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

final _issuedAt = DateTime.utc(2020);

Map<String, Object?> _state() => {
  'type': 'mcp_oauth_token_grant',
  'version': 1,
  'issued_at': '2020-01-01T00:00:00.000Z',
  'authorization_server': <String, Object?>{
    'issuer': 'https://auth.example',
    'authorization_endpoint': 'https://auth.example/authorize',
    'token_endpoint': 'https://auth.example/token',
    'response_types_supported': ['code'],
    'grant_types_supported': ['authorization_code', 'refresh_token'],
    'code_challenge_methods_supported': ['S256'],
    'token_endpoint_auth_methods_supported': ['none'],
  },
  'resource': 'https://resource.example/mcp',
  'client_id': 'consumer',
  'scopes': <String>['read'],
  'tokens': <String, Object?>{
    'access_token': 'fixture-access',
    'token_type': 'Bearer',
    'refresh_token': 'fixture-refresh',
  },
};

McpOAuthTokenGrant _restore(Map<String, Object?> state) {
  McpOAuthTokenGrant? grant;
  expect(
    () => grant = McpOAuthTokenGrant.fromJson(state, now: _issuedAt),
    returnsNormally,
    reason: 'Valid independently declared state must restore.',
  );
  return grant!;
}

Map<String, Object?> _serialize(McpOAuthTokenGrant grant) {
  Map<String, Object?>? state;
  expect(() => state = grant.toJson(), returnsNormally);
  return state!;
}

void _reject(Map<String, Object?> state, String message) {
  expect(
    () => McpOAuthTokenGrant.fromJson(state, now: _issuedAt),
    throwsA(
      isA<McpOAuthTokenGrantStateException>().having(
        (error) => error.message,
        'validation diagnostic',
        message,
      ),
    ),
  );
}

void main() {
  for (final seconds in [0, 1, 60]) {
    test(
      'expiry $seconds preserves absolute deadline and persisted fields',
      () {
        final deadline = _issuedAt.add(Duration(seconds: seconds));
        final grant = _restore(
          _state()
            ..['expires_in'] = seconds
            ..['expires_at'] = deadline.toIso8601String(),
        );
        expect(grant.issuedAt, _issuedAt);
        expect(grant.expiresIn, Duration(seconds: seconds));
        expect(grant.expiresAt, deadline);
        expect(grant.isAccessTokenExpired(now: deadline), isTrue);
        expect(
          grant.isAccessTokenExpired(
            now: deadline.subtract(const Duration(microseconds: 1)),
          ),
          isFalse,
        );
        final state = _serialize(grant);
        expect(state['expires_in'], seconds);
        expect(state['expires_at'], deadline.toIso8601String());
        expect(_serialize(_restore(state)), state);
      },
    );
  }

  test('unadvertised expiry remains absent, not zero or a null field', () {
    final grant = _restore(_state());
    expect(grant.expiresIn, isNull);
    expect(grant.expiresAt, isNull);
    final state = _serialize(grant);
    expect(state.containsKey('expires_in'), isFalse);
    expect(state.containsKey('expires_at'), isFalse);
    expect(grant.isAccessTokenExpired(now: DateTime.utc(2100)), isFalse);
  });

  for (final field in ['authorization_server', 'tokens']) {
    for (final key in <Object?>[1, null, false]) {
      test('$field rejects a direct ${key.runtimeType} key specifically', () {
        final state = _state();
        state[field] = <Object?, Object?>{
          ...state[field] as Map<String, Object?>,
          key: 'fixture-value',
        };
        _reject(
          state,
          'Persisted OAuth token grant field "$field" has a non-string key.',
        );
      });
      test('$field rejects a nested ${key.runtimeType} key specifically', () {
        final state = _state();
        (state[field] as Map<String, Object?>)['extension'] = {
          'container': [
            {key: 'fixture-value'},
          ],
        };
        _reject(
          state,
          'Persisted OAuth token grant contains a non-string object key.',
        );
      });
    }
    test(
      '$field preserves deeply nested valid JSON values without aliasing',
      () {
        final leaf = <String, Object?>{'label': 'original'};
        final values = <Object?>[null, true, false, 0, 1.5, 'text', leaf];
        final state = _state();
        (state[field] as Map<String, Object?>)['extension'] = {
          'nested': values,
        };
        final grant = _restore(state);
        leaf['label'] = 'changed';
        values.clear();
        final serialized = _serialize(grant);
        expect((serialized[field] as Map)['extension'], {
          'nested': [
            null,
            true,
            false,
            0,
            1.5,
            'text',
            {'label': 'original'},
          ],
        });
        expect(_serialize(_restore(serialized)), serialized);
        final nested =
            ((serialized[field] as Map)['extension'] as Map)['nested'] as List;
        expect(nested.clear, throwsUnsupportedError);
        expect(
          () => (nested.last as Map)['label'] = 'changed',
          throwsUnsupportedError,
        );
      },
    );
  }

  for (final scope in <Object?>[
    '',
    'has space',
    'quote"',
    'back\\slash',
    42,
    null,
  ]) {
    test(
      'scope ${scope.runtimeType}=$scope rejects at the persisted boundary',
      () {
        _reject(
          _state()..['scopes'] = ['read', scope],
          'Persisted OAuth token grant field "scopes" must contain OAuth scope tokens.',
        );
      },
    );
  }

  for (final scopes in <List<String>>[
    [],
    ['read'],
    ['write', 'read'],
  ]) {
    test('valid scope sequence $scopes survives a complete round trip', () {
      final grant = _restore(_state()..['scopes'] = scopes);
      expect(grant.scopes, scopes);
      final state = _serialize(grant);
      expect(state['scopes'], scopes);
      expect((state['tokens'] as Map).containsKey('scope'), isFalse);
      expect(_restore(state).scopes, scopes);
    });
  }
}
