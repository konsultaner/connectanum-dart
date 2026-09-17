import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  test('completion capability must agree with configured handlers', () {
    const info = McpServerInfo(name: 'validation', version: '1');
    expect(
      () => McpServer(
        serverInfo: info,
        capabilities: const McpServerCapabilities(
          completions: McpCompletionCapabilities(),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => McpServer(
        serverInfo: info,
        capabilities: const McpServerCapabilities(),
        prompts: [
          McpPrompt(
            name: 'echo',
            handler: (_) => McpPromptResult.text('ok'),
            complete: (_) => McpCompletionResult(values: ['ok']),
          ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test(
    'initialization instructions and prompt failure keep the session usable',
    () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(name: 'validation', version: '1'),
        instructions: 'Choose a tool to continue.',
        prompts: [
          McpPrompt(
            name: 'failed',
            handler: (_) => throw StateError('unavailable'),
          ),
        ],
      );
      addTearDown(server.shutdown);
      final initialized = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': mcpLatestSessionProtocolVersion},
      });
      expect(
        (initialized?['result'] as Map)['instructions'],
        'Choose a tool to continue.',
      );
      await server.handleMessage({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });
      final failed = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'prompts/get',
        'params': {'name': 'failed'},
      });
      expect((failed?['error'] as Map)['code'], McpErrorCodes.internalError);
      expect(failed, isNot(contains('result')));
      expect(
        await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'ping',
        }),
        {'jsonrpc': '2.0', 'id': 3, 'result': <String, Object?>{}},
      );
    },
  );

  test(
    'invalid operation parameters never dispatch application handlers',
    () async {
      var dispatched = 0;
      final server = McpServer(
        serverInfo: const McpServerInfo(name: 'validation', version: '1'),
        tools: [
          McpTool(
            name: 'echo',
            handler: (_) {
              dispatched++;
              return McpToolResult.text('ok');
            },
          ),
        ],
        prompts: [
          McpPrompt(
            name: 'echo',
            handler: (_) {
              dispatched++;
              return McpPromptResult.text('ok');
            },
          ),
        ],
        resources: [
          McpResource(
            uri: 'app:///echo',
            name: 'echo',
            read: (_) {
              dispatched++;
              return [];
            },
          ),
        ],
        onSubscribeResource: (_) {
          dispatched++;
        },
        onUnsubscribeResource: (_) {
          dispatched++;
        },
      );
      addTearDown(server.shutdown);
      final initialization = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 'initialize-validation',
        'method': 'initialize',
        'params': {'protocolVersion': mcpLatestSessionProtocolVersion},
      });
      expect(initialization?['result'], isA<Map>());
      await server.handleMessage({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });
      final cases = <(String, Map<String, Object?>)>[
        for (final method in [
          'tools/list',
          'prompts/list',
          'resources/list',
          'resources/templates/list',
        ])
          for (final cursor in [7, '', 'with space'])
            (method, {'cursor': cursor}),
        for (final name in [7, '', 'with space'])
          ('tools/call', {'name': name}),
        for (final name in [7, '', 'with space'])
          ('prompts/get', {'name': name}),
        for (final arguments in [
          7,
          {1: 'value'},
          {'key': 1},
        ])
          ('prompts/get', {'name': 'echo', 'arguments': arguments}),
        for (final method in [
          'resources/read',
          'resources/subscribe',
          'resources/unsubscribe',
        ])
          for (final uri in [7, '', 'relative', 'app:///with space'])
            (method, {'uri': uri}),
        ('tools/call', {'name': 'echo', 'requestState': 7}),
        (
          'tools/call',
          {
            'name': 'echo',
            'arguments': {1: 'value'},
          },
        ),
        (
          'tools/call',
          {
            'name': 'echo',
            'inputResponses': {'id': 7},
          },
        ),
        ('tools/call', {'name': 'echo', '_meta': 7}),
        ('completion/complete', {}),
        (
          'completion/complete',
          {
            'ref': {'type': 'ref/resource', 'uri': 'app:///{id}'},
            'argument': {'name': 'id', 'value': 'a'},
          },
        ),
      ];
      for (var index = 0; index < cases.length; index++) {
        final (method, params) = cases[index];
        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': index,
          'method': method,
          'params': params,
        });
        expect(response?['id'], index);
        expect(response, isNot(contains('result')), reason: '$method $params');
        expect(
          (response?['error'] as Map)['code'],
          McpErrorCodes.invalidParams,
          reason: '$method $params',
        );
      }
      expect(dispatched, 0);
    },
  );

  test(
    'initialization rejects absent or non-string protocol versions',
    () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(name: 'validation', version: '1'),
      );
      for (final version in [null, 7, true, <Object?>[]]) {
        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': {'protocolVersion': version},
        });
        expect(
          (response?['error'] as Map)['code'],
          McpErrorCodes.invalidParams,
        );
        expect(server.state, McpServerState.created);
      }
      server.shutdown();
    },
  );

  test('input-required results reject malformed form requests', () {
    expect(() => McpToolResult.inputRequired(), throwsArgumentError);
    expect(
      () => McpToolResult.inputRequired(inputRequests: {'': {}}),
      throwsArgumentError,
    );
    final validParams = <String, Object?>{
      'message': 'Choose a value',
      'requestedSchema': {'type': 'object', 'properties': {}},
    };
    final invalid = <Map<String, Object?>>[
      {'method': 'tools/call', 'params': validParams},
      {
        'method': 'elicitation/create',
        'params': {...validParams, 'mode': 'url'},
      },
      for (final message in [null, '', 7])
        {
          'method': 'elicitation/create',
          'params': {...validParams, 'message': message},
        },
      for (final schema in [
        {'type': 'array', 'properties': {}},
        {'type': 'object', 'properties': []},
      ])
        {
          'method': 'elicitation/create',
          'params': {...validParams, 'requestedSchema': schema},
        },
    ];
    for (final request in invalid) {
      expect(
        () => McpToolResult.inputRequired(inputRequests: {'id': request}),
        throwsArgumentError,
        reason: '$request',
      );
    }
  });

  test(
    'JSON-RPC helpers preserve error data and reject non-object parameters',
    () {
      final error = McpException(
        McpErrorCodes.invalidParams,
        'invalid',
        data: {'field': 'name'},
      );
      expect(error.toString(), 'McpException(-32602, invalid)');
      expect(JsonRpcResponse.error('request-1', error).toJson(), {
        'jsonrpc': '2.0',
        'id': 'request-1',
        'error': {
          'code': -32602,
          'message': 'invalid',
          'data': {'field': 'name'},
        },
      });
      for (final value in [
        7,
        true,
        [],
        {1: 'not a JSON key'},
      ]) {
        expect(
          () => jsonMapFrom(value),
          throwsA(
            isA<McpException>().having(
              (error) => error.code,
              'code',
              McpErrorCodes.invalidParams,
            ),
          ),
        );
      }
      expect(jsonMapFrom(null), isEmpty);
    },
  );

  test('capability metadata faithfully advertises optional fields', () {
    expect(
      const McpServerInfo(
        name: 'app',
        version: '1',
        title: 'App',
        description: 'Public tools',
      ).toJson(),
      {
        'name': 'app',
        'version': '1',
        'title': 'App',
        'description': 'Public tools',
      },
    );
    expect(
      const McpServerCapabilities(
        tools: McpToolCapabilities(listChanged: true),
        prompts: McpPromptCapabilities(listChanged: true),
      ).toJson(),
      {
        'tools': {'listChanged': true},
        'prompts': {'listChanged': true},
      },
    );
    expect(const McpServerCapabilities(tools: null).toJson(), isEmpty);
  });

  test('tool names enforce both alphabet and length boundaries', () {
    for (final name in ['', 'a b', 'a/b', 'a' * 129]) {
      expect(
        () => McpTool(name: name, handler: (_) => McpToolResult.text('ok')),
        throwsArgumentError,
      );
    }
    for (final name in ['a', 'a' * 128, 'a_0.b-c']) {
      expect(
        McpTool(
          name: name,
          handler: (_) => McpToolResult.text('ok'),
        ).toJson()['name'],
        name,
      );
    }
  });
}
