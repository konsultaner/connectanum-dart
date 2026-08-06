import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpStreamableHttpClient operation deadline', () {
    test('rejects non-positive request timeouts', () {
      final endpoint = Uri.parse('http://127.0.0.1:1/mcp');

      expect(
        () => McpStreamableHttpClient(endpoint, requestTimeout: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => McpStreamableHttpClient.stateless(
          endpoint,
          clientInfo: const <String, Object?>{
            'name': 'deadline-test',
            'version': '1.0.0',
          },
          requestTimeout: const Duration(milliseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test(
      'bounds delayed request opening and keeps shared transport reusable',
      () async {
        final endpoint = await _DeadlineEndpoint.bind();
        addTearDown(endpoint.close);
        final transport = _DelayedFirstPostHttpClient(HttpClient());
        addTearDown(() => transport.close(force: true));
        final client = McpStreamableHttpClient(
          endpoint.uri,
          httpClient: transport,
          requestTimeout: const Duration(milliseconds: 500),
        );
        addTearDown(() => client.close(force: true));

        final pending = client.pingDirect(id: 'delayed-open');
        await transport.waitForPost();
        await expectLater(pending, throwsA(isA<TimeoutException>()));

        transport.releasePost();
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(endpoint.requestCount, 0);

        final recovered = await client.pingDirect(id: 'after-delayed-open');
        expect(recovered, isEmpty);
        expect(endpoint.requestCount, 1);
      },
    );

    test('bounds response headers under one request deadline', () async {
      final endpoint = await _DeadlineEndpoint.bind();
      addTearDown(endpoint.close);
      final client = McpStreamableHttpClient(
        endpoint.uri,
        requestTimeout: const Duration(milliseconds: 250),
      );
      addTearDown(() => client.close(force: true));
      client.sessionId = 'kept-session';
      client.lastEventId = 'kept-session:event:1';

      final pending = client.pingDirect(
        id: 'stalled-headers',
        headers: const <String, String>{'x-test-stall': 'headers'},
      );
      await endpoint.waitForStalledHeaders();
      await expectLater(pending, throwsA(isA<TimeoutException>()));
      expect(client.sessionId, 'kept-session');
      expect(client.lastEventId, 'kept-session:event:1');

      endpoint.releaseStalledHeaders();
      expect(await client.pingDirect(id: 'after-stalled-headers'), isEmpty);
    });

    test(
      'bounds buffered response bodies under one request deadline',
      () async {
        final endpoint = await _DeadlineEndpoint.bind();
        addTearDown(endpoint.close);
        final client = McpStreamableHttpClient(
          endpoint.uri,
          requestTimeout: const Duration(milliseconds: 250),
        );
        addTearDown(() => client.close(force: true));
        client.sessionId = 'kept-session';
        client.lastEventId = 'kept-session:event:2';

        final pending = client.pingDirect(
          id: 'stalled-body',
          headers: const <String, String>{'x-test-stall': 'body'},
        );
        await endpoint.waitForStalledBody();
        await expectLater(pending, throwsA(isA<TimeoutException>()));
        expect(client.sessionId, 'kept-session');
        expect(client.lastEventId, 'kept-session:event:2');

        endpoint.releaseStalledBody();
        expect(await client.pingDirect(id: 'after-stalled-body'), isEmpty);
      },
    );

    test(
      'bounds GET and DELETE response headers without clearing state',
      () async {
        for (final operation in <String>['poll', 'delete']) {
          final endpoint = await _DeadlineEndpoint.bind();
          addTearDown(endpoint.close);
          final client = McpStreamableHttpClient(
            endpoint.uri,
            requestTimeout: const Duration(milliseconds: 250),
          );
          addTearDown(() => client.close(force: true));
          client.sessionId = 'kept-$operation-session';
          client.lastEventId = 'kept-$operation-session:event:1';

          final Future<void> pending = operation == 'poll'
              ? client
                    .poll(
                      headers: const <String, String>{
                        'x-test-stall': 'headers',
                      },
                    )
                    .then<void>((_) {})
              : client.deleteSession(
                  headers: const <String, String>{'x-test-stall': 'headers'},
                );
          await endpoint.waitForStalledHeaders();
          await expectLater(pending, throwsA(isA<TimeoutException>()));
          expect(client.sessionId, 'kept-$operation-session');
          expect(client.lastEventId, 'kept-$operation-session:event:1');
          endpoint.releaseStalledHeaders();
        }
      },
    );

    test(
      'bounds listener setup while established SSE remains long lived',
      () async {
        final endpoint = await _DeadlineEndpoint.bind();
        addTearDown(endpoint.close);
        final client = McpStreamableHttpClient.stateless(
          endpoint.uri,
          clientInfo: const <String, Object?>{
            'name': 'deadline-test',
            'version': '1.0.0',
          },
          requestTimeout: const Duration(milliseconds: 250),
        );
        addTearDown(() => client.close(force: true));

        final stalled = client.listen(
          id: 'stalled-listener',
          toolsListChanged: true,
          headers: const <String, String>{'x-test-stall': 'listener-ack'},
        );
        await endpoint.waitForStalledListener();
        await expectLater(stalled, throwsA(isA<TimeoutException>()));
        endpoint.releaseStalledListener();

        final subscription = await client.listen(
          id: 'established-listener',
          toolsListChanged: true,
        );
        var closed = false;
        unawaited(subscription.closed.then((_) => closed = true));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(closed, isFalse);
        await subscription.close();
      },
    );
  });
}

final class _DelayedFirstPostHttpClient implements HttpClient {
  _DelayedFirstPostHttpClient(this._delegate);

  final HttpClient _delegate;
  final Completer<void> _postStarted = Completer<void>();
  final Completer<void> _releasePost = Completer<void>();
  var _posts = 0;

  Future<void> waitForPost() => _postStarted.future;

  void releasePost() {
    if (!_releasePost.isCompleted) {
      _releasePost.complete();
    }
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    _posts += 1;
    if (_posts == 1) {
      if (!_postStarted.isCompleted) {
        _postStarted.complete();
      }
      await _releasePost.future;
    }
    return _delegate.postUrl(url);
  }

  @override
  void close({bool force = false}) => _delegate.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DeadlineEndpoint {
  _DeadlineEndpoint._(this._server) {
    _server.listen(_handleRequest);
  }

  final HttpServer _server;
  final Completer<void> _stalledHeaders = Completer<void>();
  final Completer<void> _releaseHeaders = Completer<void>();
  final Completer<void> _stalledBody = Completer<void>();
  final Completer<void> _releaseBody = Completer<void>();
  final Completer<void> _stalledListener = Completer<void>();
  final Completer<void> _releaseListener = Completer<void>();
  final Set<HttpResponse> _listenerResponses = <HttpResponse>{};
  var requestCount = 0;

  static Future<_DeadlineEndpoint> bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _DeadlineEndpoint._(server);
  }

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/mcp');

  Future<void> waitForStalledHeaders() => _stalledHeaders.future;
  Future<void> waitForStalledBody() => _stalledBody.future;
  Future<void> waitForStalledListener() => _stalledListener.future;

  void releaseStalledHeaders() {
    if (!_releaseHeaders.isCompleted) {
      _releaseHeaders.complete();
    }
  }

  void releaseStalledBody() {
    if (!_releaseBody.isCompleted) {
      _releaseBody.complete();
    }
  }

  void releaseStalledListener() {
    if (!_releaseListener.isCompleted) {
      _releaseListener.complete();
    }
  }

  Future<void> close() async {
    releaseStalledHeaders();
    releaseStalledBody();
    releaseStalledListener();
    for (final response in _listenerResponses.toList(growable: false)) {
      try {
        await response.close();
      } catch (_) {
        // A timed-out listener can already have closed its socket.
      }
    }
    await _server.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    requestCount += 1;
    final stall = request.headers.value('x-test-stall');
    Object? message;
    if (request.method == 'POST') {
      final text = await utf8.decodeStream(request);
      if (text.isNotEmpty) {
        message = jsonDecode(text);
      }
    }
    if (stall == 'headers') {
      if (!_stalledHeaders.isCompleted) {
        _stalledHeaders.complete();
      }
      await _releaseHeaders.future;
    }
    if (stall == 'body') {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{');
      await request.response.flush();
      if (!_stalledBody.isCompleted) {
        _stalledBody.complete();
      }
      await _releaseBody.future;
      try {
        request.response.write('}');
        await request.response.close();
      } catch (_) {
        // The client is expected to abort the stalled response on timeout.
      }
      return;
    }
    if (message is Map && message['method'] == 'subscriptions/listen') {
      await _handleListener(request, message, stalled: stall == 'listener-ack');
      return;
    }
    if (request.method == 'GET') {
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.headers.set(
        'MCP-Protocol-Version',
        McpStreamableHttpClient.latestSessionProtocolVersion,
      );
      request.response.headers.set('MCP-Session-Id', 'kept-poll-session');
      await request.response.close();
      return;
    }
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;
    final id = message is Map ? message['id'] : null;
    request.response.write(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': <String, Object?>{},
      }),
    );
    try {
      await request.response.close();
    } catch (_) {
      // A timed-out header request can already have closed its socket.
    }
  }

  Future<void> _handleListener(
    HttpRequest request,
    Map<Object?, Object?> message, {
    required bool stalled,
  }) async {
    final response = request.response;
    _listenerResponses.add(response);
    response.statusCode = HttpStatus.ok;
    response.bufferOutput = false;
    response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    response.headers.set(
      'MCP-Protocol-Version',
      McpStreamableHttpClient.latestProtocolVersion,
    );
    await response.flush();
    if (stalled) {
      if (!_stalledListener.isCompleted) {
        _stalledListener.complete();
      }
      await _releaseListener.future;
      return;
    }
    response.write(
      'data: ${jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/subscriptions/acknowledged',
        'params': <String, Object?>{
          '_meta': <String, Object?>{'io.modelcontextprotocol/subscriptionId': message['id']},
          'notifications': <String, Object?>{'toolsListChanged': true},
        },
      })}\n\n',
    );
    await response.flush();
  }
}
