@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

class _DelayedRealClient implements HttpClient {
  _DelayedRealClient(this.delegate);
  final HttpClient delegate;
  final opened = Completer<void>();
  final release = Completer<void>();
  final closes = <bool>[];

  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    final request = await delegate.getUrl(uri);
    opened.complete();
    await release.future;
    return request;
  }

  @override
  void close({bool force = false}) {
    closes.add(force);
    delegate.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final authorizationServer in [false, true]) {
    test(
      'real late-open discovery AS=$authorizationServer absorbs abort errors',
      () async {
        final uncaught = <Object>[];
        final failures = <Object>[];
        final successes = <Object>[];
        final received = <String>[];
        final openedHooks = <HttpClientRequest>[];
        await runZonedGuarded(() async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final endpoint = Uri.parse('http://127.0.0.1:${server.port}/mcp');
          final requests = server.listen((request) async {
            received.add(request.uri.toString());
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
          });
          final client = _DelayedRealClient(HttpClient());
          try {
            final operation = authorizationServer
                ? discoverMcpAuthorizationServerMetadata(
                    endpoint,
                    httpClient: client,
                    timeout: const Duration(milliseconds: 200),
                    onRequestOpened: openedHooks.add,
                  )
                : discoverMcpProtectedResourceMetadata(
                    endpoint,
                    httpClient: client,
                    timeout: const Duration(milliseconds: 200),
                    onRequestOpened: openedHooks.add,
                  );
            final settled = operation.then<void>(
              successes.add,
              onError: (Object error) => failures.add(error),
            );
            await client.opened.future;
            await settled;
            client.release.complete();
            await Future<void>.delayed(const Duration(milliseconds: 50));
            expect(client.closes, isEmpty);
          } finally {
            if (!client.release.isCompleted) client.release.complete();
            client.close(force: true);
            await requests.cancel();
            await server.close(force: true);
          }
        }, (error, _) => uncaught.add(error));
        expect(successes, isEmpty);
        expect(failures, hasLength(1));
        expect(failures.single, isA<McpAuthorizationDiscoveryException>());
        expect(received, isEmpty);
        expect(openedHooks, isEmpty);
        expect(uncaught, isEmpty);
      },
    );
  }
}
