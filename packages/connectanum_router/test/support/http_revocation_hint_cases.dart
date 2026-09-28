part of '../router_runtime_test.dart';

void _httpRevocationHintCases() {
  group('HTTP revocation advisory hints', () {
    for (final kind in ['access_token', 'refresh_token']) {
      for (final hint in <String?>[
        null,
        'access_token',
        'refresh_token',
        'unknown_token_kind',
      ]) {
        for (final source
            in hint == null ? ['body'] : ['body', 'query', 'header']) {
          test(
            '$kind hint=$hint source=$source revokes actual credential',
            () async {
              final runtime = _HandleRuntime();
              final router = Router(
                RouterConfig(
                  endpoints: [
                    Endpoint(
                      host: '127.0.0.1',
                      port: 0,
                      tlsMode: TlsMode.native,
                      maxRawSocketSizeExponent: 16,
                      sniCertificates: [_cert('localhost')],
                    ),
                  ],
                ),
                settings: _buildRouterSettingsWithHttpAuthBridge(),
              );
              final events = <Map<String, Object?>>[];
              final binding = router.start(
                runtime,
                onEvent: (event) {
                  if (event is Map<String, Object?>) events.add(event);
                },
              );
              addTearDown(binding.dispose);
              await Future<void>.delayed(Duration.zero);
              final listener = binding.listeners.single.listenerId;
              final callee = await binding.createInternalSession(
                realmUri: 'realm1',
                authId: 'revocation-service',
                authRole: 'internal',
                roles: const {'callee': <String, Object?>{}},
              );
              addTearDown(callee.close);
              var calls = 0;
              final registration = await callee.register(
                'com.example.api.secure',
              );
              registration.onInvoke((invocation) {
                calls++;
                HttpInvocationContext.maybeFromInvocation(
                  invocation,
                )!.sendText(body: 'authorized', status: HttpStatus.ok);
              });
              final grant = await _issueTicketHttpTokens(
                runtime: runtime,
                listenerId: listener,
                startConnectionId: 60,
              );
              final unrelated = await _issueTicketHttpTokens(
                runtime: runtime,
                listenerId: listener,
                startConnectionId: 70,
              );
              expect(unrelated.accessToken, isNot(grant.accessToken));
              expect(unrelated.refreshToken, isNot(grant.refreshToken));
              var nextConnection = 100;
              Future<NativeHttpResponse> request({
                Map<String, Object?> body = const {},
                String target = '/auth',
                Map<String, String> headers = const {},
                String? bearer,
              }) async {
                final id = nextConnection++;
                _enqueueSyntheticHttpRequest(
                  runtime: runtime,
                  listenerId: listener,
                  connectionId: id,
                  handle: id,
                  method: bearer == null ? 'POST' : 'GET',
                  target: bearer == null ? target : '/api/secure',
                  query: bearer == null ? Uri.parse(target).query : null,
                  headers: {
                    'content-type': 'application/json',
                    ...headers,
                    if (bearer != null) 'authorization': 'Bearer $bearer',
                  },
                  body: body,
                  realm: bearer == null ? 'router.http' : 'realm1',
                  procedure: bearer == null
                      ? 'router.http.auth'
                      : 'com.example.api.secure',
                );
                await _waitUntil(
                  () =>
                      (runtime.httpResponses[id]?.isNotEmpty ?? false) ||
                      events.any(
                        (event) =>
                            event['type'] == 'http_request_handler_error' &&
                            event['connectionId'] == id,
                      ),
                );
                final responses = runtime.httpResponses[id] ?? [];
                expect(
                  responses,
                  hasLength(1),
                  reason: 'Revocation must produce a terminal HTTP response',
                );
                return responses.single;
              }

              if (hint == null) {
                for (final token in <String?>[null, 'nonexistent-token']) {
                  final empty = await request(
                    body: {
                      'grant_type': 'revoke',
                      if (token != null) 'token': token,
                    },
                  );
                  expect(empty.status, HttpStatus.ok);
                  expect(_jsonResponseBody(empty), {'status': 'revoked'});
                }
              }
              // Establish cached sessions for both grants before revocation.
              expect(
                (await request(bearer: grant.accessToken)).status,
                HttpStatus.ok,
              );
              expect(
                (await request(bearer: unrelated.accessToken)).status,
                HttpStatus.ok,
              );
              expect(calls, 2);
              final token = kind == 'refresh_token'
                  ? grant.refreshToken
                  : grant.accessToken;
              for (var attempt = 0; attempt < 2; attempt++) {
                final response = await request(
                  body: {
                    'grant_type': 'revoke',
                    'token': token,
                    if (hint != null && source == 'body')
                      'token_type_hint': hint,
                  },
                  target: source == 'query'
                      ? Uri(
                          path: '/auth',
                          queryParameters: {'token_type_hint': hint!},
                        ).toString()
                      : '/auth',
                  headers: {
                    if (source == 'header')
                      'x-connectanum-token-type-hint': hint!,
                  },
                );
                expect(response.status, HttpStatus.ok);
                expect(_jsonResponseBody(response), {'status': 'revoked'});
              }
              final denied = await request(bearer: grant.accessToken);
              expect(denied.status, HttpStatus.unauthorized);
              expect(_jsonResponseBody(denied)['reason'], 'invalid_token');
              expect(
                calls,
                2,
                reason: 'Revoked credentials must not invoke the callee',
              );
              expect(
                (await request(bearer: unrelated.accessToken)).status,
                HttpStatus.ok,
              );
              expect(calls, 3, reason: 'An unrelated grant must remain usable');

              final refreshed = await request(
                body: {
                  'grant_type': 'refresh_token',
                  'refresh_token': grant.refreshToken,
                },
              );
              if (kind == 'refresh_token') {
                expect(refreshed.status, HttpStatus.unauthorized);
                expect(
                  _jsonResponseBody(refreshed)['reason'],
                  'invalid_refresh_token',
                );
              } else {
                expect(refreshed.status, HttpStatus.ok);
                final restored =
                    _jsonResponseBody(refreshed)['access_token'] as String;
                expect(restored, isNot(grant.accessToken));
                expect((await request(bearer: restored)).status, HttpStatus.ok);
                expect(
                  (await request(bearer: grant.accessToken)).status,
                  HttpStatus.unauthorized,
                );
              }
              final unrelatedRefresh = await request(
                body: {
                  'grant_type': 'refresh_token',
                  'refresh_token': unrelated.refreshToken,
                },
              );
              expect(unrelatedRefresh.status, HttpStatus.ok);
              final otherAccess =
                  _jsonResponseBody(unrelatedRefresh)['access_token'] as String;
              expect(
                (await request(bearer: otherAccess)).status,
                HttpStatus.ok,
              );
            },
          );
        }
      }
    }
  });
}
