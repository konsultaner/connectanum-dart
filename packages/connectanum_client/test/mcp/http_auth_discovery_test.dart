import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_client/mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpStreamableHttpClient HTTP auth discovery', () {
    test(
      'probes without credentials and selects the requested realm auth path',
      () async {
        final endpoint = await _FakeProtectedMcpEndpoint.bind();
        addTearDown(endpoint.close);

        final client = await McpStreamableHttpClient.discoverHttpAuthClient(
          endpoint.mcpUri,
          realm: 'realm1',
          headers: const <String, String>{
            'x-consumer-default': 'auth-only',
          },
        );
        addTearDown(() => client.close(force: true));

        expect(client.endpoint, endpoint.authUri);
        expect(endpoint.mcpRequests, hasLength(1));
        expect(endpoint.mcpRequests.single.authorization, isNull);
        expect(endpoint.mcpRequests.single.sessionId, isNull);
        expect(endpoint.mcpRequests.single.consumerDefault, isNull);
        expect(endpoint.mcpRequests.single.body['method'], 'ping');

        final grant = await client.issueTicketToken(
          realm: 'realm1',
          authId: 'consumer-1',
          ticket: 'ticket-secret',
        );

        expect(grant.accessToken, 'access-token-1');
        expect(grant.realm, 'realm1');
        expect(grant.authId, 'consumer-1');
        expect(endpoint.authRequests, hasLength(2));
        expect(
          endpoint.authRequests.map((request) => request.consumerDefault),
          everyElement('auth-only'),
        );
        expect(endpoint.authRequests.first.path, '/auth/alternate');
        expect(endpoint.authRequests.first.body, <String, Object?>{
          'realm': 'realm1',
          'authmethod': 'ticket',
          'authid': 'consumer-1',
        });
        expect(endpoint.authRequests.last.body, <String, Object?>{
          'state': 'state-1',
          'signature': 'ticket-secret',
        });
      },
    );

    test('rejects a protected endpoint without a matching auth path', () async {
      final endpoint = await _FakeProtectedMcpEndpoint.bind();
      addTearDown(endpoint.close);

      await expectLater(
        McpStreamableHttpClient.discoverHttpAuthClient(
          endpoint.mcpUri,
          realm: 'missing-realm',
        ),
        throwsA(
          isA<ConnectanumHttpAuthProtocolException>().having(
            (error) => error.message,
            'message',
            contains('requested realm'),
          ),
        ),
      );

      expect(endpoint.mcpRequests, hasLength(1));
      expect(endpoint.authRequests, isEmpty);
    });

    test(
      'rejects an MCP endpoint that does not require authentication',
      () async {
        final endpoint = await _FakeProtectedMcpEndpoint.bind(protected: false);
        addTearDown(endpoint.close);

        await expectLater(
          McpStreamableHttpClient.discoverHttpAuthClient(
            endpoint.mcpUri,
            realm: 'realm1',
          ),
          throwsA(
            isA<ConnectanumHttpAuthProtocolException>().having(
              (error) => error.message,
              'message',
              contains('require Bearer authentication'),
            ),
          ),
        );
      },
    );

    test('rejects non-401 discovery failures with a typed error', () async {
      final endpoint = await _FakeProtectedMcpEndpoint.bind(
        protectedStatusCode: HttpStatus.forbidden,
      );
      addTearDown(endpoint.close);

      await expectLater(
        McpStreamableHttpClient.discoverHttpAuthClient(
          endpoint.mcpUri,
          realm: 'realm1',
        ),
        throwsA(
          isA<ConnectanumHttpAuthProtocolException>().having(
            (error) => error.message,
            'message',
            contains('HTTP 403'),
          ),
        ),
      );
    });

    test('keeps a supplied HTTP transport caller-owned by default', () async {
      final endpoint = await _FakeProtectedMcpEndpoint.bind();
      addTearDown(endpoint.close);
      final transport = _CountingCloseHttpClient(HttpClient());
      addTearDown(() => transport.delegate.close(force: true));

      final client = await McpStreamableHttpClient.discoverHttpAuthClient(
        endpoint.mcpUri,
        realm: 'realm1',
        httpClient: transport,
      );
      client.close(force: true);

      expect(transport.postUrlCalls, 0);
      expect(transport.closeCalls, 0);
    });

    test('closes an explicitly owned transport when discovery fails', () async {
      final endpoint = await _FakeProtectedMcpEndpoint.bind();
      addTearDown(endpoint.close);
      final transport = _CountingCloseHttpClient(HttpClient());
      addTearDown(() {
        if (transport.closeCalls == 0) {
          transport.delegate.close(force: true);
        }
      });

      await expectLater(
        McpStreamableHttpClient.discoverHttpAuthClient(
          endpoint.mcpUri,
          realm: 'missing-realm',
          httpClient: transport,
          closeHttpClient: true,
        ),
        throwsA(isA<ConnectanumHttpAuthProtocolException>()),
      );

      expect(transport.closeCalls, 1);
    });

    test('rejects credential-bearing endpoints before probing', () async {
      await expectLater(
        McpStreamableHttpClient.discoverHttpAuthClient(
          Uri.parse('https://user:secret@consumer.example/mcp'),
          realm: 'realm1',
        ),
        throwsA(isA<ConnectanumHttpAuthProtocolException>()),
      );
    });

    test('rejects an invalid requested realm before probing', () async {
      await expectLater(
        McpStreamableHttpClient.discoverHttpAuthClient(
          Uri.parse('https://consumer.example/mcp'),
          realm: 'bad realm',
        ),
        throwsArgumentError,
      );
    });
  });
}

final class _FakeProtectedMcpEndpoint {
  _FakeProtectedMcpEndpoint._(
    this._server, {
    required this.protected,
    required this.protectedStatusCode,
  });

  final HttpServer _server;
  final bool protected;
  final int protectedStatusCode;
  final List<_SeenRequest> mcpRequests = <_SeenRequest>[];
  final List<_SeenRequest> authRequests = <_SeenRequest>[];
  StreamSubscription<HttpRequest>? _subscription;

  Uri get mcpUri => Uri.parse(
    'http://${_server.address.address}:${_server.port}/mcp?tenant=one',
  );

  Uri get authUri => Uri.parse(
    'http://${_server.address.address}:${_server.port}/auth/alternate',
  );

  static Future<_FakeProtectedMcpEndpoint> bind({
    bool protected = true,
    int protectedStatusCode = HttpStatus.unauthorized,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final endpoint = _FakeProtectedMcpEndpoint._(
      server,
      protected: protected,
      protectedStatusCode: protectedStatusCode,
    );
    endpoint._subscription = server.listen(endpoint._handle);
    return endpoint;
  }

  Future<void> close() async {
    await _subscription?.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final bodyText = await utf8.decoder.bind(request).join();
    final body = bodyText.isEmpty
        ? <String, Object?>{}
        : (jsonDecode(bodyText) as Map).cast<String, Object?>();
    final seen = _SeenRequest(
      path: request.uri.path,
      authorization: request.headers.value(HttpHeaders.authorizationHeader),
      sessionId: request.headers.value('MCP-Session-Id'),
      consumerDefault: request.headers.value('x-consumer-default'),
      body: body,
    );

    if (request.uri.path == '/mcp') {
      mcpRequests.add(seen);
      if (!protected) {
        _writeJson(request, <String, Object?>{
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': const <String, Object?>{},
        });
        return;
      }
      request.response.statusCode = protectedStatusCode;
      request.response.headers.add(
        HttpHeaders.wwwAuthenticateHeader,
        'Bearer realm="other", auth_path="/auth/wrong"',
      );
      request.response.headers.add(
        HttpHeaders.wwwAuthenticateHeader,
        'Bearer realm="realm1", auth_path="/auth/alternate"',
      );
      await request.response.close();
      return;
    }

    if (request.uri.path == '/auth/alternate') {
      authRequests.add(seen);
      if (!body.containsKey('state')) {
        _writeJson(
          request,
          const <String, Object?>{
            'state': 'state-1',
            'challenge': <String, Object?>{'challenge': 'ticket'},
          },
          statusCode: HttpStatus.unauthorized,
        );
        return;
      }
      _writeJson(request, const <String, Object?>{
        'status': 'ok',
        'token_type': 'Bearer',
        'access_token': 'access-token-1',
        'realm': 'realm1',
        'authid': 'consumer-1',
        'authrole': 'member',
        'authmethod': 'ticket',
        'authprovider': 'consumer-local',
      });
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  }

  void _writeJson(
    HttpRequest request,
    Map<String, Object?> body, {
    int statusCode = HttpStatus.ok,
  }) {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    unawaited(request.response.close());
  }
}

final class _SeenRequest {
  const _SeenRequest({
    required this.path,
    required this.authorization,
    required this.sessionId,
    required this.consumerDefault,
    required this.body,
  });

  final String path;
  final String? authorization;
  final String? sessionId;
  final String? consumerDefault;
  final Map<String, Object?> body;
}

final class _CountingCloseHttpClient implements HttpClient {
  _CountingCloseHttpClient(this.delegate);

  final HttpClient delegate;
  int postUrlCalls = 0;
  int closeCalls = 0;

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    postUrlCalls += 1;
    return delegate.postUrl(url);
  }

  @override
  void close({bool force = false}) {
    closeCalls += 1;
    delegate.close(force: force);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
