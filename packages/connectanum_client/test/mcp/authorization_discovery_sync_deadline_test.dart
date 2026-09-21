@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

class _Headers implements HttpHeaders {
  _Headers({this.slowRead = false});
  final bool slowRead;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  void forEach(void Function(String, List<String>) action) {
    if (slowRead) sleep(const Duration(milliseconds: 1100));
    action('content-type', ['application/json']);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends StreamView<List<int>> implements HttpClientResponse {
  _Response(this.stage, bool fail, Map<String, Object?> document)
    : headers = _Headers(slowRead: stage == 'responseHeaders'),
      super(
        fail
            ? Stream.error(StateError('private-late-body-error'))
            : Stream.value(utf8.encode(jsonEncode(document))),
      );
  final String stage;
  var listens = 0;

  @override
  final HttpHeaders headers;
  @override
  int get statusCode => 200;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listens++;
    if (stage == 'body') sleep(const Duration(milliseconds: 1100));
    return super.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.stage, this.fail, this.response);
  final String stage;
  final bool fail;
  final HttpClientResponse response;
  final aborts = <Object?>[];
  final _headers = _Headers();
  var sends = 0;
  var headerReads = 0;
  @override
  HttpHeaders get headers {
    headerReads++;
    if (stage == 'headers' && headerReads == 1) {
      sleep(const Duration(milliseconds: 1100));
    }
    return _headers;
  }

  @override
  Future<HttpClientResponse> close() {
    sends++;
    if (stage == 'close') {
      sleep(const Duration(milliseconds: 1100));
      if (fail) return Future.error(StateError('private-late-close-error'));
    }
    return Future.value(response);
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      aborts.add(exception);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.request);
  final _Request request;
  final closes = <bool>[];
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async => request;
  @override
  void close({bool force = false}) => closes.add(force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final authorizationServer in [false, true]) {
    for (final owned in [false, true]) {
      for (final stage in [
        'none',
        'callback',
        'headers',
        'close',
        'responseHeaders',
        'body',
      ]) {
        for (final failPending in [false, true]) {
          if (stage != 'close' && stage != 'body' && failPending) continue;
          test('discovery sync deadline AS=$authorizationServer owned=$owned '
              'stage=$stage failure=$failPending '
              'observes the pending future', () async {
            final endpoint = Uri.parse('https://issuer.example/mcp');
            final document = authorizationServer
                ? <String, Object?>{
                    'issuer': endpoint.toString(),
                    'authorization_endpoint':
                        'https://issuer.example/authorize',
                    'token_endpoint': 'https://issuer.example/token',
                    'response_types_supported': ['code'],
                    'code_challenge_methods_supported': ['S256'],
                  }
                : <String, Object?>{
                    'resource': endpoint.toString(),
                    'authorization_servers': ['https://issuer.example'],
                  };
            final response = _Response(
              stage,
              stage == 'body' && failPending,
              document,
            );
            final request = _Request(stage, failPending, response);
            final client = _Client(request);
            final hooks = <HttpClientRequest>[];
            void onRequestOpened(HttpClientRequest opened) {
              hooks.add(opened);
              if (stage == 'callback') {
                sleep(const Duration(milliseconds: 1100));
              }
            }

            final errors = <Object>[];
            final successes = <Object>[];
            final uncaught = <Object>[];
            await runZonedGuarded(() async {
              final operation = HttpOverrides.runZoned(
                () => authorizationServer
                    ? discoverMcpAuthorizationServerMetadata(
                        endpoint,
                        httpClient: owned ? null : client,
                        timeout: const Duration(seconds: 1),
                        onRequestOpened: onRequestOpened,
                      )
                    : discoverMcpProtectedResourceMetadata(
                        endpoint,
                        httpClient: owned ? null : client,
                        timeout: const Duration(seconds: 1),
                        onRequestOpened: onRequestOpened,
                      ),
                createHttpClient: (_) => client,
              );
              await operation.then<void>(
                successes.add,
                onError: (Object error) => errors.add(error),
              );
              await Future<void>.delayed(Duration.zero);
            }, (error, _) => uncaught.add(error));
            if (stage == 'none') {
              expect(errors, isEmpty);
              expect(successes, hasLength(1));
              if (authorizationServer) {
                expect(
                  successes.single,
                  isA<McpAuthorizationServerDiscovery>().having(
                    (value) => value.metadata.issuer,
                    'issuer',
                    endpoint,
                  ),
                );
              } else {
                expect(
                  successes.single,
                  isA<McpProtectedResourceDiscovery>().having(
                    (value) => value.metadata.resource,
                    'resource',
                    endpoint,
                  ),
                );
              }
              expect(request.aborts, isEmpty);
              expect(request.sends, 1);
            } else {
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
              expect(request.aborts, hasLength(1));
            }
            expect(client.closes, owned ? [true] : isEmpty);
            expect(hooks, [same(request)]);
            expect(uncaught, isEmpty);
            if (stage == 'callback') {
              expect(request.headerReads, 0);
            }
            if (stage == 'callback' || stage == 'headers') {
              expect(request.sends, 0);
            }
            expect(
              response.listens,
              stage == 'body' || stage == 'none' ? 1 : 0,
            );
          });
        }
      }
    }
  }
}
