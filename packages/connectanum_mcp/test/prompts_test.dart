import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('MCP prompts', () {
    test('initialize advertises prompts when prompts are configured', () async {
      final server = _server();

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': mcpLatestProtocolVersion,
          'capabilities': {},
          'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
        },
      });

      final result = response?['result'] as Map<String, Object?>;
      expect(result['capabilities'], {
        'tools': <String, Object?>{},
        'prompts': <String, Object?>{},
      });
    });

    test('prompts/list returns typed prompt definitions', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 10,
        'method': 'prompts/list',
        'params': {},
      });

      final result = response?['result'] as Map<String, Object?>;
      final prompts = result['prompts'] as List<Object?>;
      expect(result.containsKey('nextCursor'), isFalse);
      expect(prompts, [
        {
          'name': 'task.summary',
          'title': 'Task Summary',
          'description': 'Summarizes an application task.',
          'arguments': [
            {
              'name': 'task_id',
              'title': 'Task ID',
              'description': 'Application task identifier.',
              'required': true,
            },
            {'name': 'tone', 'description': 'Optional response tone.'},
          ],
        },
      ]);
    });

    test('prompts/list paginates with opaque cursors', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        promptListPageSize: 2,
        prompts: [_prompt('alpha'), _prompt('beta'), _prompt('gamma')],
      );
      await _initializeAndStart(server);

      final firstResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 11,
        'method': 'prompts/list',
        'params': {},
      });

      final first = firstResponse?['result'] as Map<String, Object?>;
      expect(_promptNames(first), ['alpha', 'beta']);
      final cursor = first['nextCursor'];
      expect(cursor, isA<String>());

      final secondResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 12,
        'method': 'prompts/list',
        'params': {'cursor': cursor},
      });

      final second = secondResponse?['result'] as Map<String, Object?>;
      expect(_promptNames(second), ['gamma']);
      expect(second.containsKey('nextCursor'), isFalse);
    });

    test('prompts/list returns deterministic name ordering', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        prompts: [_prompt('gamma'), _prompt('alpha'), _prompt('beta')],
      );
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 19,
        'method': 'prompts/list',
        'params': {},
      });

      final result = response?['result'] as Map<String, Object?>;
      expect(_promptNames(result), ['alpha', 'beta', 'gamma']);
    });

    test('prompts/list rejects stale cursors', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(
          name: 'connectanum-test',
          version: '0.1.0',
        ),
        promptListPageSize: 1,
        prompts: [_prompt('alpha'), _prompt('beta')],
      );
      await _initializeAndStart(server);

      final firstResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 13,
        'method': 'prompts/list',
        'params': {},
      });
      final first = firstResponse?['result'] as Map<String, Object?>;
      final staleCursor = first['nextCursor'];
      expect(staleCursor, isA<String>());

      server.prompts.register(_prompt('gamma'));
      final staleResponse = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 14,
        'method': 'prompts/list',
        'params': {'cursor': staleCursor},
      });

      final error = staleResponse?['error'] as Map<String, Object?>;
      expect(error['code'], McpErrorCodes.invalidParams);
    });

    test('prompts/list rejects malformed cursor strings', () async {
      final server = _server();
      await _initializeAndStart(server);

      for (final cursor in ['', 'cursor with space', 'cursor\nnext']) {
        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 'cursor-$cursor',
          'method': 'prompts/list',
          'params': {'cursor': cursor},
        });

        final error = response?['error'] as Map<String, Object?>;
        expect(error['code'], McpErrorCodes.invalidParams);
        expect(error['message'], contains('cursor must be a non-empty string'));
      }
    });

    test(
      'prompt registry replaceAll swaps prompts and invalidates cursors',
      () {
        final registry = McpPromptRegistry([
          _prompt('alpha'),
          _prompt('beta'),
        ], 1);
        final firstPage = registry.listPage();
        expect(
          _promptNames({
            'prompts': firstPage.prompts
                .map((prompt) => prompt.toJson())
                .toList(),
          }),
          ['alpha'],
        );
        expect(firstPage.nextCursor, isA<String>());

        registry.replaceAll([_prompt('gamma')]);

        expect(registry.list().map((prompt) => prompt.name), ['gamma']);
        expect(
          () => registry.listPage(cursor: firstPage.nextCursor),
          throwsA(
            isA<McpException>().having(
              (error) => error.code,
              'code',
              McpErrorCodes.invalidParams,
            ),
          ),
        );
      },
    );

    test(
      'prompts/get passes string arguments to the registered prompt',
      () async {
        final server = _server();
        await _initializeAndStart(server);

        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 15,
          'method': 'prompts/get',
          'params': {
            'name': 'task.summary',
            'arguments': {'task_id': 'T-42', 'tone': 'brief'},
          },
        });

        final result = response?['result'] as Map<String, Object?>;
        expect(result['description'], 'Task summary prompt for T-42.');
        expect(result['messages'], [
          {
            'role': 'user',
            'content': {
              'type': 'text',
              'text': 'Summarize task T-42 in a brief tone.',
            },
          },
          {
            'role': 'assistant',
            'content': {
              'type': 'resource',
              'resource': {
                'uri': 'app://tasks/T-42',
                'mimeType': 'application/json',
                'text': '{"id":"T-42"}',
              },
            },
          },
        ]);
      },
    );

    test('prompts/get validates required arguments', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 16,
        'method': 'prompts/get',
        'params': {'name': 'task.summary'},
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(error['code'], McpErrorCodes.invalidParams);
      expect(error['message'], contains('task_id'));
    });

    test('prompts/get rejects non-string arguments', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 17,
        'method': 'prompts/get',
        'params': {
          'name': 'task.summary',
          'arguments': {'task_id': 42},
        },
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(error['code'], McpErrorCodes.invalidParams);
    });

    test('unknown prompts are invalid params errors', () async {
      final server = _server();
      await _initializeAndStart(server);

      final response = await server.handleMessage({
        'jsonrpc': '2.0',
        'id': 18,
        'method': 'prompts/get',
        'params': {'name': 'missing'},
      });

      final error = response?['error'] as Map<String, Object?>;
      expect(error['code'], McpErrorCodes.invalidParams);
    });

    test('prompts/get rejects malformed prompt names before lookup', () async {
      final server = _server();
      await _initializeAndStart(server);

      for (final name in ['', 'task summary', 'task\nsummary']) {
        final response = await server.handleMessage({
          'jsonrpc': '2.0',
          'id': 'prompt-$name',
          'method': 'prompts/get',
          'params': {'name': name},
        });

        final error = response?['error'] as Map<String, Object?>;
        expect(error['code'], McpErrorCodes.invalidParams);
        expect(error['message'], contains('prompts/get.params.name'));
        expect(error['message'], contains('non-empty string'));
      }
    });

    test('prompt definitions validate names and argument duplicates', () {
      expect(
        () => McpPrompt(name: '', handler: (_) => McpPromptResult.text('')),
        throwsArgumentError,
      );
      expect(() => McpPromptArgument(name: ''), throwsArgumentError);
      expect(
        () => McpPrompt(
          name: 'duplicate',
          arguments: [
            McpPromptArgument(name: 'value'),
            McpPromptArgument(name: 'value'),
          ],
          handler: (_) => McpPromptResult.text(''),
        ),
        throwsArgumentError,
      );
    });
  });
}

McpServer _server() => McpServer(
  serverInfo: const McpServerInfo(name: 'connectanum-test', version: '0.1.0'),
  prompts: [
    McpPrompt(
      name: 'task.summary',
      title: 'Task Summary',
      description: 'Summarizes an application task.',
      arguments: [
        McpPromptArgument(
          name: 'task_id',
          title: 'Task ID',
          description: 'Application task identifier.',
          required: true,
        ),
        McpPromptArgument(name: 'tone', description: 'Optional response tone.'),
      ],
      handler: (request) {
        final taskId = request.arguments['task_id']!;
        final tone = request.arguments['tone'] ?? 'neutral';
        return McpPromptResult(
          description: 'Task summary prompt for $taskId.',
          messages: [
            McpPromptMessage.user(
              McpTextContent('Summarize task $taskId in a $tone tone.'),
            ),
            McpPromptMessage.assistant(
              McpEmbeddedResourceContent(
                resource: McpTextResourceContent(
                  uri: 'app://tasks/$taskId',
                  mimeType: 'application/json',
                  text: '{"id":"$taskId"}',
                ),
              ),
            ),
          ],
        );
      },
    ),
  ],
);

McpPrompt _prompt(String name) =>
    McpPrompt(name: name, handler: (_) => McpPromptResult.text(name));

List<String> _promptNames(Map<String, Object?> listResult) {
  final prompts = listResult['prompts'] as List<Object?>;
  return [
    for (final prompt in prompts)
      (prompt as Map<String, Object?>)['name']! as String,
  ];
}

Future<void> _initializeAndStart(McpServer server) async {
  await server.handleMessage({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': {
      'protocolVersion': mcpLatestProtocolVersion,
      'capabilities': {},
      'clientInfo': {'name': 'test-client', 'version': '1.0.0'},
    },
  });
  await server.handleMessage({
    'jsonrpc': '2.0',
    'method': 'notifications/initialized',
  });
}
