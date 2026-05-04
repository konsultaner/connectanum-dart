import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectanum_mcp/connectanum_mcp_io.dart';
import 'package:test/test.dart';

void main() {
  test(
    'IO entrypoint re-exports MCP primitives and direct WAMP helpers',
    () async {
      final tool = McpTool(
        name: 'app.echo',
        description: 'Echoes a request.',
        handler: (request) async => McpToolResult.text(
          'echo:${request.arguments['value']}',
          structuredContent: <String, Object?>{'ok': true},
        ),
      );

      final toolResult = await tool.handler(
        const McpToolRequest(
          name: 'app.echo',
          arguments: <String, Object?>{'value': 'ready'},
        ),
      );
      expect(tool.name, 'app.echo');
      expect(toolResult.structuredContent, {'ok': true});

      final endpoint = await _DirectWampEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      final catalog = await client.listWampApi(
        id: 'io-entrypoint-api-list',
        kind: 'procedure',
        directJson: true,
      );

      expect(catalog['procedures'], hasLength(1));
      expect(client.sessionId, isNull);
      expect(endpoint.requests, hasLength(1));

      final request = endpoint.requests.single;
      expect(request.accept, 'application/json');
      expect(request.sessionId, isNull);
      expect(request.body['method'], 'connectanum.tool.call');

      final params = _jsonMapFrom(request.body['params'], label: 'tool params');
      expect(params['name'], 'connectanum.api.list');
      expect(_jsonMapFrom(params['arguments'], label: 'tool arguments'), {
        'kind': 'procedure',
      });
    },
  );
}

final class _DirectWampEndpoint {
  _DirectWampEndpoint._(this._server) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  final requests = <_SeenRequest>[];
  late final StreamSubscription<HttpRequest> _subscription;

  Uri get uri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/mcp',
  );

  static Future<_DirectWampEndpoint> bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _DirectWampEndpoint._(server);
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final jsonBody = _jsonMapFrom(jsonDecode(body), label: 'request');
    requests.add(_SeenRequest.from(request, jsonBody));

    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final params = _jsonMapFrom(jsonBody['params'], label: 'params');
    if (jsonBody['method'] != 'connectanum.tool.call' ||
        params['name'] != 'connectanum.api.list') {
      await _writeJson(request, <String, Object?>{
        'jsonrpc': '2.0',
        'id': jsonBody['id'],
        'error': <String, Object?>{
          'code': -32601,
          'message': 'unsupported method',
        },
      });
      return;
    }

    await _writeJson(request, <String, Object?>{
      'jsonrpc': '2.0',
      'id': jsonBody['id'],
      'result': <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': 'ok'},
        ],
        'structuredContent': <String, Object?>{
          'procedures': <Object?>[
            <String, Object?>{'procedure': 'app.echo', 'title': 'Echo'},
          ],
        },
        'isError': false,
      },
    });
  }

  Future<void> _writeJson(
    HttpRequest request,
    Map<String, Object?> body,
  ) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}

final class _SeenRequest {
  const _SeenRequest({
    required this.accept,
    required this.sessionId,
    required this.body,
  });

  final String? accept;
  final String? sessionId;
  final Map<String, Object?> body;

  factory _SeenRequest.from(HttpRequest request, Map<String, Object?> body) {
    return _SeenRequest(
      accept: request.headers.value(HttpHeaders.acceptHeader),
      sessionId: request.headers.value('MCP-Session-Id'),
      body: body,
    );
  }
}

Map<String, Object?> _jsonMapFrom(Object? value, {required String label}) {
  if (value case final Map<Object?, Object?> map) {
    return <String, Object?>{
      for (final entry in map.entries)
        if (entry.key case final String key) key: entry.value,
    };
  }
  throw StateError('Expected $label to be a JSON object, got $value.');
}
