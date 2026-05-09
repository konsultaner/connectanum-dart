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

  test(
    'IO entrypoint re-exports Streamable resource and prompt helpers',
    () async {
      final endpoint = await _StreamableResourcePromptEndpoint.bind();
      addTearDown(endpoint.close);

      final client = McpStreamableHttpClient(endpoint.uri);
      addTearDown(() => client.close(force: true));

      final initialize = await client.initialize(id: 'io-streamable-init');
      expect(
        _jsonMapFrom(
          initialize['result'],
          label: 'initialize result',
        )['protocolVersion'],
        mcpLatestProtocolVersion,
      );
      expect(client.sessionId, 'io-session-1');

      final streamableContents = await client.readResource(
        _ioResourceUri,
        id: 'io-streamable-resource-read',
      );
      expect(streamableContents.single['text'], contains('IO entrypoint'));
      expect(client.lastEventId, 'io-session-1:post:1');

      final streamablePrompt = await client.getPrompt(
        _ioPromptName,
        id: 'io-streamable-prompt-get',
        arguments: const <String, String>{'taskId': 'T-streamable'},
      );
      expect(
        jsonEncode(streamablePrompt['messages']),
        contains('T-streamable'),
      );
      expect(client.lastEventId, 'io-session-1:post:2');

      final sessionId = client.sessionId;
      final lastEventId = client.lastEventId;

      final directResources = await client.listResources(
        id: 'io-direct-resources',
        directJson: true,
      );
      expect(directResources.resources.single['uri'], _ioResourceUri);

      final directPrompt = await client.getPrompt(
        _ioPromptName,
        id: 'io-direct-prompt-get',
        arguments: const <String, String>{'taskId': 'T-direct'},
        directJson: true,
      );
      expect(jsonEncode(directPrompt['messages']), contains('T-direct'));

      final directBatch = await client.postBatch(
        <McpJsonMap>[
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'io-batch-resource-read',
            'method': 'resources/read',
            'params': <String, Object?>{'uri': _ioResourceUri},
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'io-batch-prompt-get',
            'method': 'prompts/get',
            'params': <String, Object?>{
              'name': _ioPromptName,
              'arguments': <String, Object?>{'taskId': 'T-batch'},
            },
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 'io-batch-missing-resource',
            'method': 'resources/read',
            'params': <String, Object?>{'uri': 'app://io/missing'},
          },
        ],
        streamable: false,
        includeSession: false,
      );

      expect(directBatch, hasLength(3));
      expect(
        jsonEncode(
          _jsonRpcResult(
            directBatch![0],
            id: 'io-batch-resource-read',
          )['contents'],
        ),
        contains('IO entrypoint'),
      );
      expect(
        jsonEncode(_jsonRpcResult(directBatch[1], id: 'io-batch-prompt-get')),
        contains('T-batch'),
      );
      expect(
        _jsonMapFrom(
          directBatch[2]['error'],
          label: 'missing resource batch error',
        )['message'],
        contains('app://io/missing'),
      );

      expect(client.sessionId, sessionId);
      expect(client.lastEventId, lastEventId);
      expect(endpoint.requests, hasLength(6));
      expect(endpoint.requests[0].sessionId, isNull);
      expect(endpoint.requests[1].sessionId, 'io-session-1');
      expect(endpoint.requests[2].sessionId, 'io-session-1');
      expect(endpoint.requests[3].sessionId, isNull);
      expect(endpoint.requests[4].sessionId, isNull);
      expect(endpoint.requests[5].sessionId, isNull);
      expect(endpoint.requests[3].accept, 'application/json');
      expect(endpoint.requests[4].accept, 'application/json');
      expect(endpoint.requests[5].accept, 'application/json');
    },
  );
}

const String _ioResourceUri = 'app://io-entrypoint/context';
const String _ioPromptName = 'io.summarize';

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

final class _StreamableResourcePromptEndpoint {
  _StreamableResourcePromptEndpoint._(this._server) {
    _subscription = _server.listen(_handle);
  }

  final HttpServer _server;
  final requests = <_StreamableSeenRequest>[];
  late final StreamSubscription<HttpRequest> _subscription;
  var _eventCounter = 0;

  Uri get uri => Uri(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
    path: '/mcp',
  );

  static Future<_StreamableResourcePromptEndpoint> bind() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _StreamableResourcePromptEndpoint._(server);
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final message = jsonDecode(body);
    requests.add(_StreamableSeenRequest.from(request, message));

    if (request.method != 'POST') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final response = _responseFor(request, message);
    if (response == null) {
      request.response.statusCode = HttpStatus.accepted;
      await request.response.close();
      return;
    }

    if (_shouldWriteSse(request, message)) {
      await _writeSse(request, _jsonMapFrom(response, label: 'SSE response'));
      return;
    }
    await _writeJsonValue(request, response);
  }

  Object? _responseFor(HttpRequest request, Object? message) {
    if (message case final List<Object?> batch) {
      return <Object?>[
        for (final item in batch)
          if (item case final Map<Object?, Object?> map)
            if (map['id'] != null)
              _responseForSingle(request, <String, Object?>{
                for (final entry in map.entries)
                  if (entry.key case final String key) key: entry.value,
              }),
      ];
    }
    if (message case final Map<Object?, Object?> map) {
      final json = <String, Object?>{
        for (final entry in map.entries)
          if (entry.key case final String key) key: entry.value,
      };
      if (json['id'] == null) {
        return null;
      }
      return _responseForSingle(request, json);
    }
    return <String, Object?>{
      'jsonrpc': '2.0',
      'id': null,
      'error': <String, Object?>{'code': -32600, 'message': 'invalid request'},
    };
  }

  Map<String, Object?> _responseForSingle(
    HttpRequest request,
    Map<String, Object?> message,
  ) {
    final id = message['id'];
    switch (message['method']) {
      case 'initialize':
        request.response.headers.set('MCP-Session-Id', 'io-session-1');
        request.response.headers.set(
          'MCP-Protocol-Version',
          mcpLatestProtocolVersion,
        );
        return _result(id, <String, Object?>{
          'protocolVersion': mcpLatestProtocolVersion,
          'capabilities': <String, Object?>{},
          'serverInfo': <String, Object?>{
            'name': 'io-entrypoint-test',
            'version': '1.0.0',
          },
        });
      case 'resources/list':
        return _result(id, <String, Object?>{
          'resources': <Object?>[
            <String, Object?>{
              'uri': _ioResourceUri,
              'name': 'io-context',
              'mimeType': 'text/plain',
            },
          ],
        });
      case 'resources/read':
        final params = _jsonMapFrom(
          message['params'],
          label: 'resource params',
        );
        final uri = params['uri'];
        if (uri != _ioResourceUri) {
          return _error(id, -32004, 'Resource not found: $uri');
        }
        return _result(id, <String, Object?>{
          'contents': <Object?>[
            <String, Object?>{
              'uri': _ioResourceUri,
              'mimeType': 'text/plain',
              'text': 'IO entrypoint resource context',
            },
          ],
        });
      case 'prompts/get':
        final params = _jsonMapFrom(message['params'], label: 'prompt params');
        if (params['name'] != _ioPromptName) {
          return _error(id, -32004, 'Prompt not found: ${params['name']}');
        }
        final arguments = _jsonMapFrom(
          params['arguments'],
          label: 'prompt arguments',
        );
        return _result(id, <String, Object?>{
          'description': 'Summarize a task.',
          'messages': <Object?>[
            <String, Object?>{
              'role': 'user',
              'content': <String, Object?>{
                'type': 'text',
                'text': 'Summarize ${arguments['taskId']}.',
              },
            },
          ],
        });
      default:
        return _error(id, -32601, 'unsupported method');
    }
  }

  bool _shouldWriteSse(HttpRequest request, Object? message) {
    final acceptsSse =
        request.headers
            .value(HttpHeaders.acceptHeader)
            ?.contains('text/event-stream') ??
        false;
    return acceptsSse && message is Map && message['method'] != 'initialize';
  }

  Future<void> _writeJsonValue(HttpRequest request, Object? body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _writeSse(HttpRequest request, Map<String, Object?> body) async {
    _eventCounter += 1;
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.writeln('id: io-session-1:post:$_eventCounter');
    request.response.writeln('data: ${jsonEncode(body)}');
    request.response.writeln();
    await request.response.close();
  }

  Map<String, Object?> _result(Object? id, Map<String, Object?> result) =>
      <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};

  Map<String, Object?> _error(Object? id, int code, String message) =>
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': code, 'message': message},
      };
}

final class _StreamableSeenRequest {
  const _StreamableSeenRequest({
    required this.accept,
    required this.sessionId,
    required this.body,
  });

  final String? accept;
  final String? sessionId;
  final Object? body;

  factory _StreamableSeenRequest.from(HttpRequest request, Object? body) {
    return _StreamableSeenRequest(
      accept: request.headers.value(HttpHeaders.acceptHeader),
      sessionId: request.headers.value('MCP-Session-Id'),
      body: body,
    );
  }
}

Map<String, Object?> _jsonRpcResult(
  Map<String, Object?> response, {
  required Object? id,
}) {
  expect(response['id'], id);
  expect(response, isNot(contains('error')));
  return _jsonMapFrom(response['result'], label: 'JSON-RPC result');
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
