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
  final HttpClientResponse response;
  final aborts = <Object?>[];
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  void abort([Object? error, StackTrace? stackTrace]) => aborts.add(error);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.request, {this.fallback});
  final _Request request;
  final _Request? fallback;
  final closes = <bool>[];
  var opens = 0;
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async =>
      opens++ == 0 ? request : fallback ?? request;
  @override
  void close({bool force = false}) => closes.add(force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  _testAuthorizationServerBodyDeadline();
  _testFallbackDuringCleanup();
  for (final owned in [false, true]) {
    for (final oversized in [false, true]) {
      for (final cleanupFails in [false, true]) {
        test(
          'discovery body owned=$owned oversized=$oversized '
          'cleanupFails=$cleanupFails detaches without waiting for cleanup',
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
                final request = _Request(_Response(body.stream));
                final client = _Client(request);
                final errors = <Object>[];
                final successes = <Object>[];
                final operation = HttpOverrides.runZoned(
                  () => discoverMcpProtectedResourceMetadata(
                    Uri.parse('https://resource.example/mcp'),
                    httpClient: owned ? null : client,
                    timeout: const Duration(seconds: 1),
                    maxMetadataBytes: 16,
                  ),
                  createHttpClient: (_) => client,
                );
                unawaited(
                  operation.then<void>(
                    successes.add,
                    onError: (Object error) => errors.add(error),
                  ),
                );
                async.flushMicrotasks();
                expect(body.hasListener, isTrue);
                if (oversized) {
                  body.add(List<int>.filled(17, 0x20));
                } else {
                  async.elapse(const Duration(milliseconds: 600));
                  body.add([0x20]);
                  async.flushMicrotasks();
                  expect(errors, isEmpty);
                  async.elapse(const Duration(milliseconds: 400));
                }
                async.flushMicrotasks();
                try {
                  expect(errors, hasLength(1));
                  final failure = errors.single;
                  expect(
                    failure,
                    isA<McpAuthorizationDiscoveryException>().having(
                      (error) => error.message,
                      'message',
                      contains(oversized ? 'exceeds' : 'timed out'),
                    ),
                  );
                  expect(successes, isEmpty);
                  expect(cancellations, 1);
                  expect(body.hasListener, isFalse);
                  expect(cleanup.isCompleted, isFalse);
                  expect(client.closes, owned ? [true] : isEmpty);
                  if (cleanupFails) {
                    cleanup.completeError(StateError('private-cleanup-error'));
                  } else {
                    cleanup.complete();
                  }
                  async.flushMicrotasks();
                  expect(errors, [same(failure)]);
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

void _testFallbackDuringCleanup() {
  for (final owned in [false, true]) {
    for (final cleanupFails in [false, true]) {
      test('discovery body fallback owned=$owned cleanupFails=$cleanupFails '
          'succeeds while previous cancellation remains pending', () {
        final uncaught = <Object>[];
        runZonedGuarded(() {
          fakeAsync((async) {
            final issuer = Uri.parse('https://issuer.example');
            final cleanup = Completer<void>();
            var cancellations = 0;
            final body = StreamController<List<int>>(
              onCancel: () {
                cancellations++;
                return cleanup.future;
              },
            );
            final fallback = _Request(
              _Response(
                Stream.value(
                  utf8.encode(
                    jsonEncode({
                      'issuer': issuer.toString(),
                      'authorization_endpoint':
                          'https://issuer.example/authorize',
                      'token_endpoint': 'https://issuer.example/token',
                      'response_types_supported': ['code'],
                      'code_challenge_methods_supported': ['S256'],
                    }),
                  ),
                ),
              ),
            );
            final client = _Client(
              _Request(_Response(body.stream)),
              fallback: fallback,
            );
            final errors = <Object>[];
            final successes = <McpAuthorizationServerDiscovery>[];
            final operation = HttpOverrides.runZoned(
              () => discoverMcpAuthorizationServerMetadata(
                issuer,
                httpClient: owned ? null : client,
                maxMetadataBytes: 1024,
              ),
              createHttpClient: (_) => client,
            );
            unawaited(
              operation.then<void>(
                successes.add,
                onError: (Object error) => errors.add(error),
              ),
            );
            async.flushMicrotasks();
            body.add(List<int>.filled(1025, 0x20));
            async.flushMicrotasks();
            try {
              expect(errors, isEmpty);
              expect(successes, hasLength(1));
              expect(successes.single.metadata.issuer, issuer);
              expect(
                successes.single.metadata.tokenEndpoint,
                Uri.parse('https://issuer.example/token'),
              );
              expect(client.opens, 2);
              expect(cancellations, 1);
              expect(body.hasListener, isFalse);
              expect(cleanup.isCompleted, isFalse);
              expect(client.closes, owned ? [true] : isEmpty);
              if (cleanupFails) {
                cleanup.completeError(StateError('private-cleanup-error'));
              } else {
                cleanup.complete();
              }
              async.flushMicrotasks();
              expect(errors, isEmpty);
              expect(successes, hasLength(1));
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
      });
    }
  }
}

void _testAuthorizationServerBodyDeadline() {
  for (final owned in [false, true]) {
    for (final cleanupFails in [false, true]) {
      test('authorization server body owned=$owned cleanupFails=$cleanupFails '
          'detaches before asynchronous cleanup finishes', () async {
        final uncaught = <Object>[];
        final errors = <Object>[];
        final successes = <Object>[];
        late Completer<void> cleanup;
        var cancellations = 0;
        late StreamController<List<int>> body;
        late _Client client;
        await runZonedGuarded(
          () =>
              (() async {
                cleanup = Completer<void>();
                body = StreamController<List<int>>(
                  onCancel: () {
                    cancellations++;
                    return cleanup.future;
                  },
                );
                client = _Client(_Request(_Response(body.stream)));
                final operation = HttpOverrides.runZoned(
                  () => discoverMcpAuthorizationServerMetadata(
                    Uri.parse('https://issuer.example'),
                    httpClient: owned ? null : client,
                    timeout: const Duration(milliseconds: 50),
                  ),
                  createHttpClient: (_) => client,
                );
                await operation.then<void>(
                  successes.add,
                  onError: (Object error) => errors.add(error),
                );
                try {
                  expect(errors, hasLength(1));
                  expect(
                    errors.single,
                    isA<McpAuthorizationDiscoveryException>().having(
                      (error) => error.message,
                      'message',
                      contains('timed out'),
                    ),
                  );
                  expect(successes, isEmpty);
                  expect(cancellations, 1);
                  expect(body.hasListener, isFalse);
                  expect(cleanup.isCompleted, isFalse);
                  expect(client.closes, owned ? [true] : isEmpty);
                  if (cleanupFails) {
                    cleanup.completeError(StateError('private-cleanup-error'));
                  } else {
                    cleanup.complete();
                  }
                  await Future<void>.delayed(Duration.zero);
                } finally {
                  if (!cleanup.isCompleted) cleanup.complete();
                  unawaited(body.close());
                }
              })().then<void>(
                (_) {},
                onError: (Object error) => uncaught.add(error),
              ),
          (error, _) => uncaught.add(error),
        );
        expect(uncaught, isEmpty);
      });
    }
  }
}
