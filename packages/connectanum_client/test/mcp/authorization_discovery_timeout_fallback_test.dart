@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void forEach(void Function(String, List<String>) action) =>
      action('content-type', ['application/json']);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends StreamView<List<int>> implements HttpClientResponse {
  _Response(super.stream);
  @override
  final HttpHeaders headers = _Headers();
  @override
  int get statusCode => 200;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final Future<HttpClientResponse> response;
  final aborts = <Object?>[];
  var sends = 0;
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<HttpClientResponse> close() {
    sends++;
    return response;
  }

  @override
  void abort([Object? error, StackTrace? stackTrace]) => aborts.add(error);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.first);
  final Future<HttpClientRequest> first;
  final opened = <Uri>[];
  final closes = <bool>[];
  @override
  Future<HttpClientRequest> getUrl(Uri uri) {
    opened.add(uri);
    if (opened.length == 1) return first;
    // A fallback would succeed, so retrying cannot masquerade as a timeout.
    return Future.value(
      _Request(
        Future.value(
          _Response(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'issuer': 'https://issuer.example',
                  'authorization_endpoint': 'https://issuer.example/authorize',
                  'token_endpoint': 'https://issuer.example/token',
                  'response_types_supported': ['code'],
                  'code_challenge_methods_supported': ['S256'],
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void close({bool force = false}) => closes.add(force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final stage in ['open', 'headers', 'body']) {
    for (final owned in [false, true]) {
      for (final lateFailure in [false, true]) {
        test('AS timeout is terminal at $stage owned=$owned '
            'lateFailure=$lateFailure', () {
          final uncaught = <Object>[];
          runZonedGuarded(() {
            fakeAsync((async) {
              final opened = Completer<HttpClientRequest>();
              final headers = Completer<HttpClientResponse>();
              final cleanup = Completer<void>();
              var cancellations = 0;
              final body = StreamController<List<int>>(
                onCancel: () {
                  cancellations++;
                  return cleanup.future;
                },
              );
              final response = _Response(body.stream);
              final request = _Request(headers.future);
              final client = _Client(opened.future);
              final failures = <Object>[];
              final results = <Object>[];
              final firstUri = Uri.parse(
                'https://issuer.example/.well-known/oauth-authorization-server',
              );
              final operation = HttpOverrides.runZoned(
                () => discoverMcpAuthorizationServerMetadata(
                  Uri.parse('https://issuer.example'),
                  httpClient: owned ? null : client,
                  timeout: const Duration(seconds: 1),
                ),
                createHttpClient: (_) => client,
              );
              unawaited(
                operation.then<void>(
                  results.add,
                  onError: (Object error) => failures.add(error),
                ),
              );
              if (stage != 'open') opened.complete(request);
              if (stage == 'body') headers.complete(response);
              async.flushMicrotasks();
              expect(client.opened, [firstUri]);
              expect(body.hasListener, stage == 'body');
              // Advance the timeout timer independently of Stopwatch. This
              // makes the early-timer/remaining-budget boundary deterministic.
              async.elapse(const Duration(seconds: 1));
              try {
                expect(results, isEmpty);
                expect(failures, hasLength(1));
                final failure = failures.single;
                expect(
                  failure,
                  isA<McpAuthorizationDiscoveryException>()
                      .having(
                        (e) => e.message,
                        'message',
                        'Authorization Server Metadata discovery timed out.',
                      )
                      .having((e) => e.uri, 'uri', firstUri),
                );
                expect(client.opened, [firstUri]);
                expect(client.closes, owned ? [true] : isEmpty);
                expect(body.hasListener, isFalse);
                expect(cancellations, stage == 'body' ? 1 : 0);
                expect(cleanup.isCompleted, isFalse);
                final lateError = StateError('private late operation');
                if (stage == 'open') {
                  if (lateFailure) {
                    opened.completeError(lateError);
                  } else {
                    opened.complete(request);
                  }
                } else if (stage == 'headers') {
                  if (lateFailure) {
                    headers.completeError(lateError);
                  } else {
                    headers.complete(response);
                  }
                } else if (lateFailure) {
                  cleanup.completeError(lateError);
                } else {
                  cleanup.complete();
                }
                async.flushMicrotasks();
                expect(failures, [same(failure)]);
                expect(results, isEmpty);
                expect(client.opened, [firstUri]);
                expect(request.sends, stage == 'open' ? 0 : 1);
                expect(
                  request.aborts,
                  stage == 'open' && lateFailure ? isEmpty : hasLength(1),
                );
                expect(uncaught, isEmpty);
                expect(async.pendingTimers, isEmpty);
              } finally {
                if (!opened.isCompleted) opened.complete(request);
                if (!headers.isCompleted) headers.complete(response);
                if (!cleanup.isCompleted) cleanup.complete();
                unawaited(body.close());
                async.flushMicrotasks();
              }
            });
          }, (error, _) => uncaught.add(error));
          expect(uncaught, isEmpty);
        });
      }
    }
  }
}
