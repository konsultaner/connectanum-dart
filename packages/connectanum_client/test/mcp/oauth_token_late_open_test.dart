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
  _testResponseBodyCancellation();
  _testWholeBodyDeadline();
  _testSlowBodyCleanup();
  _testSynchronousDeadlineCleanup();
  _testSynchronousStageDeadlines();
  _testUnexpectedOwnerErrors();
  _testSetupDeadline();
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

void _testSlowBodyCleanup() {
  for (final oversized in [false, true]) {
    for (final kind in ['exchange', 'refresh', 'revoke']) {
      for (final ownsClient in [false, true]) {
        for (final cleanupFails in [false, true]) {
          test(
            'slow body cleanup $kind owned=$ownsClient failure=$cleanupFails oversized=$oversized '
            'does not extend deadline or replace its error',
            () {
              final uncaught = <Object>[];
              runZonedGuarded(() {
                fakeAsync((async) {
                  final cleanup = Completer<void>();
                  var cancellations = 0;
                  final body = StreamController<List<int>>(
                    onCancel: () {
                      cancellations++;
                      return cleanup.future;
                    },
                  );
                  final client = _DelayedClient();
                  final request = _OpenedRequest();
                  client.opened.complete(request);
                  request.response.complete(_Response(body.stream));
                  final errors = <Object>[];
                  final successes = <Object?>[];
                  unawaited(
                    HttpOverrides.runZoned(
                      () =>
                          _operation(kind, ownsClient ? null : client, (_) {}),
                      createHttpClient: (_) => client,
                    ).then<void>(
                      successes.add,
                      onError: (Object error) => errors.add(error),
                    ),
                  );
                  async.flushMicrotasks();
                  if (oversized) {
                    body.add(List<int>.filled(65537, 0x20));
                  } else {
                    async.elapse(const Duration(seconds: 1));
                  }
                  async.flushMicrotasks();
                  try {
                    expect(cleanup.isCompleted, isFalse);
                    expect(cancellations, 1);
                    expect(body.hasListener, isFalse);
                    expect(errors, hasLength(1));
                    final failure = errors.single;
                    expect(
                      failure,
                      isA<McpOAuthTokenException>().having(
                        (error) => error.message,
                        'message',
                        contains(oversized ? 'exceeds' : 'timed out'),
                      ),
                    );
                    expect(successes, isEmpty);
                    expect(client.closes, ownsClient ? [true] : isEmpty);
                    if (cleanupFails) {
                      cleanup.completeError(
                        StateError('private-cleanup-error'),
                      );
                    } else {
                      cleanup.complete();
                    }
                    async.flushMicrotasks();
                    expect(errors, [same(failure)]);
                    expect(request.aborts, hasLength(1));
                    expect(uncaught, isEmpty);
                    expect(async.pendingTimers, isEmpty);
                  } finally {
                    if (!cleanup.isCompleted) cleanup.complete();
                    unawaited(body.close());
                    async.flushMicrotasks();
                  }
                });
              }, (error, _) => uncaught.add(error));
              expect(uncaught, isEmpty);
            },
          );
        }
      }
    }
  }
}

void _testWholeBodyDeadline() {
  for (final kind in ['exchange', 'refresh', 'revoke']) {
    for (final ownsClient in [false, true]) {
      test(
        'whole body deadline $kind owned=$ownsClient is not reset by chunks',
        () {
          fakeAsync((async) {
            var cancellations = 0;
            final body = StreamController<List<int>>(
              onCancel: () => cancellations++,
            );
            final client = _DelayedClient();
            final request = _OpenedRequest();
            client.opened.complete(request);
            request.response.complete(_Response(body.stream));
            final errors = <Object>[];
            final successes = <Object?>[];
            unawaited(
              HttpOverrides.runZoned(
                () => _operation(kind, ownsClient ? null : client, (_) {}),
                createHttpClient: (_) => client,
              ).then<void>(
                successes.add,
                onError: (Object error) => errors.add(error),
              ),
            );
            async.flushMicrotasks();
            async.elapse(const Duration(milliseconds: 600));
            body.add([0x20]);
            async.flushMicrotasks();
            expect(errors, isEmpty);
            async.elapse(const Duration(milliseconds: 400));
            async.flushMicrotasks();
            try {
              expect(errors, hasLength(1));
              expect(
                errors.single,
                isA<McpOAuthTokenException>().having(
                  (error) => error.message,
                  'message',
                  contains('timed out'),
                ),
              );
              expect(successes, isEmpty);
              expect(cancellations, 1);
              expect(body.hasListener, isFalse);
            } finally {
              unawaited(body.close());
              async.flushMicrotasks();
            }
          });
        },
      );
    }
  }
}

void _testResponseBodyCancellation() {
  for (final kind in ['exchange', 'refresh', 'revoke']) {
    for (final ownsClient in [false, true]) {
      test(
        'response body deadline $kind owned=$ownsClient cancels subscription',
        () {
          fakeAsync((async) {
            var cancellations = 0;
            final body = StreamController<List<int>>(
              onCancel: () => cancellations++,
            );
            final client = _DelayedClient();
            final request = _OpenedRequest();
            client.opened.complete(request);
            request.response.complete(_Response(body.stream));
            final errors = <Object>[];
            final successes = <Object?>[];
            unawaited(
              HttpOverrides.runZoned(
                () => _operation(kind, ownsClient ? null : client, (_) {}),
                createHttpClient: (_) => client,
              ).then<void>(
                successes.add,
                onError: (Object error) => errors.add(error),
              ),
            );
            async.flushMicrotasks();
            expect(body.hasListener, isTrue);
            async.elapse(const Duration(seconds: 1));
            async.flushMicrotasks();
            try {
              expect(errors, hasLength(1));
              expect(
                errors.single,
                isA<McpOAuthTokenException>().having(
                  (error) => error.message,
                  'message',
                  contains('timed out'),
                ),
              );
              expect(successes, isEmpty);
              expect(request.aborts, hasLength(1));
              expect(client.closes, ownsClient ? [true] : isEmpty);
              // SDK abort() is a no-op after the response future has completed.
              expect(cancellations, 1);
              expect(body.hasListener, isFalse);
            } finally {
              unawaited(body.close());
              async.flushMicrotasks();
            }
          });
        },
      );
    }
  }
}

void _testUnexpectedOwnerErrors() {
  for (final kind in ['exchange', 'refresh', 'revoke']) {
    for (final ownsClient in [false, true]) {
      test(
        'unexpected owner error $kind owned=$ownsClient aborts once',
        () async {
          final client = _DelayedClient();
          final request = _OpenedRequest();
          final failure = StateError('fixture-private-owner-error');
          client.opened.complete(request);
          final hooks = <HttpClientRequest>[];
          await expectLater(
            HttpOverrides.runZoned(
              () => _operation(kind, ownsClient ? null : client, (opened) {
                hooks.add(opened);
                throw failure;
              }),
              createHttpClient: (_) => client,
            ),
            throwsA(
              isA<McpOAuthTokenException>()
                  .having(
                    (error) => error.message,
                    'sanitized message',
                    'OAuth ${kind == 'revoke' ? 'revocation' : 'token'} endpoint request failed.',
                  )
                  .having(
                    (error) => error.endpoint,
                    'endpoint',
                    client.requested.single,
                  ),
            ),
          );
          expect(hooks, [same(request)]);
          expect(request.aborts, [same(failure)]);
          expect(request.closeCalls, 0);
          expect(request.headerReads, 0);
          expect(request.bytes, isEmpty);
          expect(client.closes, ownsClient ? [true] : isEmpty);
        },
      );
    }
  }
}

void _testSynchronousDeadlineCleanup() {
  for (final kind in ['exchange', 'refresh', 'revoke']) {
    test('synchronous deadline expiration aborts opened $kind request', () async {
      final client = _DelayedClient();
      final request = _OpenedRequest();
      client.opened.complete(request);
      var observedOpen = false;
      await expectLater(
        _operation(kind, client, (_) {
          observedOpen = true;
          // Expire the real DateTime deadline, not only FakeAsync's timer queue.
          sleep(const Duration(milliseconds: 1100));
        }),
        throwsA(
          isA<McpOAuthTokenException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      expect(observedOpen, isTrue);
      expect(
        client.closes,
        isEmpty,
        reason: 'The shared client remains owned by its caller',
      );
      expect(
        request.aborts,
        hasLength(1),
        reason: 'An expired opened request must be released',
      );
      expect(
        request.closeCalls,
        0,
        reason: 'Expired setup must not send a request',
      );
      expect(request.headerReads, 0);
      expect(request.bytes, isEmpty);
    });
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

class _SlowSetupRequest extends _OpenedRequest {
  @override
  void add(List<int> data) {
    super.add(data);
    sleep(const Duration(milliseconds: 1100));
  }
}

void _testSetupDeadline() {
  for (final kind in ['exchange', 'refresh', 'revoke']) {
    for (final ownsClient in [false, true]) {
      test(
        'synchronous setup deadline $kind owned=$ownsClient prevents close',
        () async {
          final client = _DelayedClient();
          final request = _SlowSetupRequest();
          client.opened.complete(request);
          await expectLater(
            HttpOverrides.runZoned(
              () => _operation(kind, ownsClient ? null : client, (_) {}),
              createHttpClient: (_) => client,
            ),
            throwsA(
              isA<McpOAuthTokenException>().having(
                (error) => error.message,
                'message',
                contains('timed out'),
              ),
            ),
          );
          expect(request.bytes, isNotEmpty);
          expect(request.closeCalls, 0);
          expect(request.aborts, hasLength(1));
          expect(client.closes, ownsClient ? [true] : isEmpty);
        },
      );
    }
  }
}

class _SlowCloseRequest extends _OpenedRequest {
  _SlowCloseRequest(this.fail);

  final bool fail;

  @override
  Future<HttpClientResponse> close() {
    closeCalls++;
    sleep(const Duration(milliseconds: 1100));
    return fail
        ? Future<HttpClientResponse>.error(StateError('late close fixture'))
        : Future<HttpClientResponse>.value(
            _Response(Stream.value(_validBody())),
          );
  }
}

class _SlowListenResponse extends _Response {
  _SlowListenResponse(bool fail)
    : super(
        fail
            ? Stream<List<int>>.error(StateError('late body fixture'))
            : Stream<List<int>>.value(_validBody()),
      );

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    sleep(const Duration(milliseconds: 1100));
    return super.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

List<int> _validBody() => utf8.encode(
  jsonEncode({
    'access_token': 'fresh-access',
    'token_type': 'Bearer',
    'refresh_token': 'fresh-refresh',
    'scope': 'read',
  }),
);

void _testSynchronousStageDeadlines() {
  for (final kind in ['exchange', 'refresh', 'revoke']) {
    for (final stage in ['close', 'body']) {
      for (final ownsClient in [false, true]) {
        for (final failPending in [false, true]) {
          test('synchronous stage deadline $kind $stage owned=$ownsClient '
              'lateFailure=$failPending is observed and cleaned up', () async {
            final client = _DelayedClient();
            final request = stage == 'close'
                ? _SlowCloseRequest(failPending)
                : _OpenedRequest();
            client.opened.complete(request);
            if (stage == 'body') {
              request.response.complete(_SlowListenResponse(failPending));
            }
            final successes = <Object?>[];
            final errors = <Object>[];
            final uncaught = <Object>[];
            await runZonedGuarded(() async {
              await HttpOverrides.runZoned(
                () => _operation(kind, ownsClient ? null : client, (_) {}),
                createHttpClient: (_) => client,
              ).then<void>(
                successes.add,
                onError: (Object error) {
                  errors.add(error);
                },
              );
              await Future<void>.delayed(Duration.zero);
            }, (error, _) => uncaught.add(error));
            expect(successes, isEmpty);
            expect(errors, hasLength(1));
            expect(
              errors.single,
              isA<McpOAuthTokenException>().having(
                (error) => error.message,
                'message',
                contains('timed out'),
              ),
            );
            expect(request.aborts, hasLength(1));
            expect(client.closes, ownsClient ? [true] : isEmpty);
            expect(
              uncaught,
              isEmpty,
              reason: 'An expired stage must still observe its pending future',
            );
          });
        }
      }
    }
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
