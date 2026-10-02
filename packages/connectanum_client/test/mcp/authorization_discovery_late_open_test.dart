import 'dart:async';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

class _DelayedClient implements HttpClient {
  final opened = Completer<HttpClientRequest>();
  final requested = <Uri>[];
  final closes = <bool>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
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
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborts.add(exception);
  }

  @override
  HttpHeaders get headers {
    headerReads++;
    throw StateError('A timed-out request must not receive headers.');
  }

  @override
  Future<HttpClientResponse> close() {
    closeCalls++;
    throw StateError('A timed-out request must not be sent.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final closeClient in [false, true]) {
    for (final failOpen in [false, true]) {
      test('late request closeClient=$closeClient failOpen=$failOpen', () {
        fakeAsync((async) {
          final endpoint = Uri.parse('https://mcp.example/mcp');
          final client = _DelayedClient();
          final request = _LateRequest();
          final errors = <Object>[];
          final successes = <McpProtectedResourceDiscovery>[];
          final hooks = <HttpClientRequest>[];
          unawaited(
            discoverMcpProtectedResourceMetadata(
              endpoint,
              httpClient: client,
              closeHttpClient: closeClient,
              timeout: const Duration(seconds: 1),
              onRequestOpened: hooks.add,
            ).then(successes.add, onError: (Object error) => errors.add(error)),
          );
          async.flushMicrotasks();
          expect(client.requested, [endpoint]);
          expect(errors, isEmpty);
          expect(client.closes, isEmpty);

          // Observe the deadline outcome, not a test-runner timeout.
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
          expect(successes, isEmpty);
          expect(errors, hasLength(1));
          final error = errors.single;
          expect(
            error,
            isA<McpAuthorizationDiscoveryException>()
                .having((value) => value.uri, 'uri', endpoint)
                .having(
                  (value) => value.message,
                  'message',
                  'Protected Resource Metadata discovery timed out.',
                ),
          );
          expect(client.closes, closeClient ? [true] : isEmpty);

          if (failOpen) {
            client.opened.completeError(const SocketException('late failure'));
          } else {
            client.opened.complete(request);
          }
          async.flushMicrotasks();
          expect(errors, [same(error)]);
          expect(successes, isEmpty);
          expect(hooks, isEmpty);
          expect(client.requested, [endpoint]);
          expect(client.closes, closeClient ? [true] : isEmpty);
          expect(request.closeCalls, 0);
          expect(request.headerReads, 0);
          if (failOpen) {
            expect(request.aborts, isEmpty);
          } else {
            expect(request.aborts, hasLength(1));
            expect(
              request.aborts.single,
              isA<TimeoutException>().having(
                (value) => value.message,
                'message',
                'Protected Resource Metadata discovery timed out.',
              ),
            );
          }
          expect(async.pendingTimers, isEmpty);
        });
      });
    }
  }
}
