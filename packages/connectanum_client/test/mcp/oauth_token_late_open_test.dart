@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

class _DelayedClient implements HttpClient {
  final opened = Completer<HttpClientRequest>();
  final requested = <Uri>[];
  final closes = <bool>[];

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    requested.add(url);
    return opened.future;
  }

  @override
  void close({bool force = false}) => closes.add(force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LateRequest implements HttpClientRequest {
  final aborts = <Object?>[];
  var closeCalls = 0;
  var headerReads = 0;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      aborts.add(exception);

  @override
  HttpHeaders get headers {
    headerReads++;
    throw StateError('A timed-out request must not receive credentials.');
  }

  @override
  Future<HttpClientResponse> close() {
    closeCalls++;
    throw StateError('A timed-out request must not be sent.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

McpOAuthTokenGrant _grant() => McpOAuthTokenGrant.fromJson({
  'type': 'mcp_oauth_token_grant',
  'version': 1,
  'issued_at': '2020-01-01T00:00:00.000Z',
  'authorization_server': {
    'issuer': 'https://issuer.example',
    'authorization_endpoint': 'https://issuer.example/authorize',
    'token_endpoint': 'https://issuer.example/token',
    'revocation_endpoint': 'https://issuer.example/revoke',
    'response_types_supported': ['code'],
    'grant_types_supported': ['authorization_code', 'refresh_token'],
    'code_challenge_methods_supported': ['S256'],
    'token_endpoint_auth_methods_supported': ['none'],
    'revocation_endpoint_auth_methods_supported': ['none'],
  },
  'resource': 'https://resource.example/mcp',
  'client_id': 'consumer',
  'scopes': ['read'],
  'tokens': {
    'access_token': 'fixture-access',
    'token_type': 'Bearer',
    'refresh_token': 'fixture-refresh',
  },
}, now: DateTime.utc(2020));

void main() {
  _testOpenedRequests();
  _testRetryIsolation();
  for (final kind in ['exchange', 'refresh', 'revoke']) {
    for (final ownsClient in [false, true]) {
      for (final failOpen in [false, true]) {
        test(
          'late OAuth open $kind owned=$ownsClient failure=$failOpen',
          () {
            fakeAsync((async) {
              final revoke = kind == 'revoke';
              final grant = _grant();
              final authentication =
                  McpOAuthClientAuthentication.registeredPublic(
                    clientId: grant.clientId,
                    authorizationServer: grant.authorizationServer,
                  );
              final endpoint = Uri.parse(
                'https://issuer.example/${revoke ? 'revoke' : 'token'}',
              );
              final label = revoke
                  ? 'OAuth revocation endpoint'
                  : 'OAuth token endpoint';
              final client = _DelayedClient();
              final request = _LateRequest();
              final errors = <Object>[];
              final hooks = <HttpClientRequest>[];
              var successes = 0;
              HttpOverrides.runZoned(() {
                final codeRequest = createMcpAuthorizationRequest(
                  authorizationServer: grant.authorizationServer,
                  resource: grant.resource,
                  clientId: grant.clientId,
                  redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
                  scopes: grant.scopes,
                  pkce: McpPkcePair.fromVerifier('a' * 43),
                );
                final code = parseMcpAuthorizationCallback(
                  codeRequest.redirectUri.replace(
                    queryParameters: {
                      'code': 'fixture-code',
                      'state': codeRequest.state,
                    },
                  ),
                  request: codeRequest,
                );
                final Future<void> operation = kind == 'exchange'
                    ? exchangeMcpAuthorizationCode(
                        code,
                        clientAuthentication: authentication,
                        httpClient: ownsClient ? null : client,
                        timeout: const Duration(seconds: 1),
                        onRequestOpened: hooks.add,
                      ).then<void>((_) {})
                    : revoke
                    ? revokeMcpOAuthToken(
                        grant,
                        clientAuthentication: authentication,
                        httpClient: ownsClient ? null : client,
                        timeout: const Duration(seconds: 1),
                        onRequestOpened: hooks.add,
                      )
                    : refreshMcpOAuthToken(
                        grant,
                        clientAuthentication: authentication,
                        httpClient: ownsClient ? null : client,
                        timeout: const Duration(seconds: 1),
                        onRequestOpened: hooks.add,
                      ).then<void>((_) {});
                unawaited(
                  operation.then(
                    (_) => successes++,
                    onError: (Object error) => errors.add(error),
                  ),
                );
              }, createHttpClient: (_) => client);
              async.flushMicrotasks();
              expect(client.requested, [endpoint]);
              expect(errors, isEmpty);
              expect(client.closes, isEmpty);
              async.elapse(const Duration(seconds: 1));
              async.flushMicrotasks();
              expect(errors, hasLength(1));
              final failure = errors.single;
              expect(
                failure,
                isA<McpOAuthTokenException>()
                    .having(
                      (e) => e.message,
                      'deadline',
                      '$label request timed out.',
                    )
                    .having((e) => e.endpoint, 'endpoint', endpoint),
              );
              expect(successes, 0);
              expect(client.closes, ownsClient ? [true] : isEmpty);
              if (failOpen) {
                client.opened.completeError(
                  const SocketException('late failure'),
                );
              } else {
                client.opened.complete(request);
              }
              async.flushMicrotasks();
              expect(errors, [same(failure)]);
              expect(successes, 0);
              expect(hooks, isEmpty);
              expect(client.closes, ownsClient ? [true] : isEmpty);
              expect(request.closeCalls, 0);
              expect(request.headerReads, 0);
              expect(request.aborts, failOpen ? isEmpty : hasLength(1));
              if (!failOpen) {
                expect(
                  request.aborts.single,
                  isA<TimeoutException>().having(
                    (error) => error.message,
                    'abort reason',
                    '$label request timed out.',
                  ),
                );
              }
              expect(async.pendingTimers, isEmpty);
            });
          },
        );
      }
    }
  }
}

class _QueuedClient extends _DelayedClient {
  final openings = <Completer<HttpClientRequest>>[];

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    requested.add(url);
    final opening = Completer<HttpClientRequest>();
    openings.add(opening);
    return opening.future;
  }
}

void _testRetryIsolation() {
  for (final kind in ['exchange', 'refresh', 'revoke']) {
    test('late $kind response cannot affect a retry using the same client', () {
      fakeAsync((async) {
        final client = _QueuedClient();
        final staleRequest = _LateRequest();
        final retryRequest = _OpenedRequest();
        final firstErrors = <Object>[];
        final retryErrors = <Object>[];
        final firstSuccesses = <Object?>[];
        final retrySuccesses = <Object?>[];
        final firstHooks = <HttpClientRequest>[];
        final retryHooks = <HttpClientRequest>[];
        unawaited(
          _operation(kind, client, firstHooks.add).then(
            firstSuccesses.add,
            onError: (Object error) => firstErrors.add(error),
          ),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(firstErrors, hasLength(1));
        expect(firstErrors.single, isA<McpOAuthTokenException>());
        expect(firstSuccesses, isEmpty);
        expect(firstHooks, isEmpty);
        unawaited(
          _operation(kind, client, retryHooks.add).then(
            retrySuccesses.add,
            onError: (Object error) => retryErrors.add(error),
          ),
        );
        async.flushMicrotasks();
        expect(client.openings, hasLength(2));
        client.openings.last.complete(retryRequest);
        async.flushMicrotasks();
        expect(retryHooks, [same(retryRequest)]);
        expect(retryRequest.closeCalls, 1);
        expect(retryRequest.aborts, isEmpty);
        // Resolve the stale opening while the retry is awaiting its response.
        client.openings.first.complete(staleRequest);
        async.flushMicrotasks();
        expect(staleRequest.aborts, hasLength(1));
        expect(staleRequest.aborts.single, isA<TimeoutException>());
        expect(staleRequest.headerReads, 0);
        expect(staleRequest.closeCalls, 0);
        expect(retryRequest.aborts, isEmpty);
        expect(retryErrors, isEmpty);
        expect(retrySuccesses, isEmpty);
        retryRequest.response.complete(
          _Response(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'access_token': 'retry-access',
                  'token_type': 'Bearer',
                  'refresh_token': 'retry-refresh',
                  'scope': 'read',
                }),
              ),
            ),
          ),
        );
        async.flushMicrotasks();
        expect(retryErrors, isEmpty);
        expect(retrySuccesses, hasLength(1));
        if (kind == 'revoke') {
          expect(retrySuccesses.single, isNull);
        } else {
          expect(
            retrySuccesses.single,
            isA<McpOAuthTokenGrant>()
                .having(
                  (grant) => grant.accessToken,
                  'retry access',
                  'retry-access',
                )
                .having(
                  (grant) => grant.refreshToken,
                  'retry refresh',
                  'retry-refresh',
                ),
          );
        }
        expect(firstErrors, hasLength(1));
        expect(firstSuccesses, isEmpty);
        expect(firstHooks, isEmpty);
        expect(retryRequest.aborts, isEmpty);
        expect(client.closes, isEmpty);
        expect(async.pendingTimers, isEmpty);
      });
    });
  }
}

class _RecordingHeaders implements HttpHeaders {
  @override
  ContentType? contentType;
  final values = <String, Object>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends StreamView<List<int>> implements HttpClientResponse {
  _Response(super.stream);

  @override
  int get statusCode => 200;

  @override
  final HttpHeaders headers = _RecordingHeaders()
    ..contentType = ContentType.json;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OpenedRequest extends _LateRequest {
  final response = Completer<HttpClientResponse>();
  final recordedHeaders = _RecordingHeaders();
  final bytes = <int>[];

  bool _followRedirects = true;
  int _contentLength = -1;

  @override
  bool get followRedirects => _followRedirects;

  @override
  set followRedirects(bool value) => _followRedirects = value;

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) => _contentLength = value;

  @override
  HttpHeaders get headers {
    headerReads++;
    return recordedHeaders;
  }

  @override
  void add(List<int> data) => bytes.addAll(data);

  @override
  Future<HttpClientResponse> close() {
    closeCalls++;
    return response.future;
  }
}

Future<Object?> _operation(
  String kind,
  HttpClient? client,
  void Function(HttpClientRequest) onRequestOpened,
) {
  final grant = _grant();
  final authentication = McpOAuthClientAuthentication.registeredPublic(
    clientId: grant.clientId,
    authorizationServer: grant.authorizationServer,
  );
  if (kind == 'revoke') {
    return revokeMcpOAuthToken(
      grant,
      clientAuthentication: authentication,
      httpClient: client,
      timeout: const Duration(seconds: 1),
      onRequestOpened: onRequestOpened,
    ).then<Object?>((_) => null);
  }
  if (kind == 'refresh') {
    return refreshMcpOAuthToken(
      grant,
      clientAuthentication: authentication,
      httpClient: client,
      timeout: const Duration(seconds: 1),
      onRequestOpened: onRequestOpened,
    );
  }
  final request = createMcpAuthorizationRequest(
    authorizationServer: grant.authorizationServer,
    resource: grant.resource,
    clientId: grant.clientId,
    redirectUri: Uri.parse('http://127.0.0.1:34891/callback'),
    scopes: grant.scopes,
    pkce: McpPkcePair.fromVerifier('a' * 43),
  );
  final code = parseMcpAuthorizationCallback(
    request.redirectUri.replace(
      queryParameters: {
        'code': 'fixture-code',
        'state': request.state,
      },
    ),
    request: request,
  );
  return exchangeMcpAuthorizationCode(
    code,
    clientAuthentication: authentication,
    httpClient: client,
    timeout: const Duration(seconds: 1),
    onRequestOpened: onRequestOpened,
  );
}

void _testOpenedRequests() {
  for (final kind in ['exchange', 'refresh', 'revoke']) {
    for (final ownsClient in [false, true]) {
      for (final stage in [
        'success',
        'open-error',
        'owner-error',
        'close',
        'body',
      ]) {
        test('on-time OAuth $kind owned=$ownsClient stage=$stage', () {
          fakeAsync((async) {
            final client = _DelayedClient();
            final request = _OpenedRequest();
            final body = StreamController<List<int>>();
            final successes = <Object?>[];
            final errors = <Object>[];
            final hooks = <HttpClientRequest>[];
            final ownerError = McpOAuthTokenException(
              'Request owner rejected.',
            );
            HttpOverrides.runZoned(() {
              unawaited(
                _operation(kind, ownsClient ? null : client, (request) {
                  hooks.add(request);
                  if (stage == 'owner-error') {
                    throw ownerError;
                  }
                }).then(
                  successes.add,
                  onError: (Object error) => errors.add(error),
                ),
              );
            }, createHttpClient: (_) => client);
            async.flushMicrotasks();
            expect(client.closes, isEmpty);
            expect(successes, isEmpty);
            expect(errors, isEmpty);
            if (stage == 'open-error') {
              client.opened.completeError(
                const SocketException('fixture-private-error'),
              );
            } else {
              client.opened.complete(request);
            }
            async.flushMicrotasks();
            expect(
              request.aborts,
              stage == 'owner-error' ? [same(ownerError)] : isEmpty,
            );
            expect(hooks, stage == 'open-error' ? isEmpty : [same(request)]);
            if (stage != 'open-error' && stage != 'owner-error') {
              expect(request.closeCalls, 1);
              expect(request.followRedirects, isFalse);
              expect(request.contentLength, request.bytes.length);
              final form = Uri.splitQueryString(utf8.decode(request.bytes));
              expect(form['client_id'], 'consumer');
              expect(
                request.recordedHeaders.contentType?.mimeType,
                'application/x-www-form-urlencoded',
              );
              expect(
                request.recordedHeaders.values[HttpHeaders.acceptHeader],
                'application/json',
              );
              if (kind == 'revoke') {
                expect(form['token'], 'fixture-refresh');
                expect(form['token_type_hint'], 'refresh_token');
              } else {
                expect(
                  form['grant_type'],
                  kind == 'refresh' ? 'refresh_token' : 'authorization_code',
                );
              }
              if (stage != 'close') {
                request.response.complete(_Response(body.stream));
                async.flushMicrotasks();
              }
              if (stage == 'success') {
                body.add(
                  utf8.encode(
                    jsonEncode({
                      'access_token': 'new-access',
                      'token_type': 'Bearer',
                      'refresh_token': 'new-refresh',
                      'scope': 'read',
                    }),
                  ),
                );
                unawaited(body.close());
              } else {
                // This observes the operation deadline, not a runner timeout.
                async.elapse(const Duration(seconds: 1));
              }
              async.flushMicrotasks();
            }
            if (stage == 'success') {
              expect(errors, isEmpty);
              expect(successes, hasLength(1));
              if (kind == 'revoke') {
                expect(successes.single, isNull);
              } else {
                expect(
                  successes.single,
                  isA<McpOAuthTokenGrant>()
                      .having(
                        (grant) => grant.accessToken,
                        'access',
                        'new-access',
                      )
                      .having(
                        (grant) => grant.refreshToken,
                        'refresh',
                        'new-refresh',
                      )
                      .having((grant) => grant.scopes, 'scopes', ['read']),
                );
              }
              expect(request.aborts, isEmpty);
            } else if (stage == 'owner-error') {
              expect(successes, isEmpty);
              expect(errors, [same(ownerError)]);
              expect(request.closeCalls, 0);
              expect(request.headerReads, 0);
              expect(request.bytes, isEmpty);
            } else {
              expect(successes, isEmpty);
              expect(errors, hasLength(1));
              final label = kind == 'revoke'
                  ? 'OAuth revocation endpoint'
                  : 'OAuth token endpoint';
              expect(
                errors.single,
                isA<McpOAuthTokenException>()
                    .having(
                      (error) => error.message,
                      'operation failure',
                      '$label request ${stage == 'open-error' ? 'failed' : 'timed out'}.',
                    )
                    .having(
                      (error) => error.endpoint,
                      'endpoint',
                      Uri.parse(
                        'https://issuer.example/${kind == 'revoke' ? 'revoke' : 'token'}',
                      ),
                    ),
              );
              expect(request.aborts, stage == 'open-error' ? isEmpty : [null]);
            }
            expect(client.closes, ownsClient ? [true] : isEmpty);
            if (stage != 'success') {
              unawaited(body.close());
            }
            if (stage == 'close') {
              request.response.complete(_Response(const Stream.empty()));
            }
            async.flushMicrotasks();
            expect(async.pendingTimers, isEmpty);
          });
        });
      }
    }
  }
}
