import 'package:connectanum_mcp/connectanum_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('MCP completion', () {
    test(
      'advertises and serves prompt and resource-template completions',
      () async {
        final seen = <McpCompletionRequest>[];
        final server = McpServer(
          serverInfo: const McpServerInfo(
            name: 'completion-test',
            version: '1',
          ),
          prompts: <McpPrompt>[
            McpPrompt(
              name: 'summarize-task',
              arguments: <McpPromptArgument>[
                McpPromptArgument(name: 'taskId'),
              ],
              handler: (_) => McpPromptResult.text('summary'),
              complete: (request) {
                seen.add(request);
                return McpCompletionResult(
                  values: <String>['T-100', 'T-101'],
                  total: 2,
                  hasMore: false,
                );
              },
            ),
          ],
          resourceTemplates: <McpResourceTemplate>[
            McpResourceTemplate(
              uriTemplate: 'app://tasks/{taskId}',
              name: 'task',
              complete: (_) => McpCompletionResult(
                values: <String>['T-200'],
              ),
            ),
          ],
        );

        final initialized = await server.handleMessage(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': <String, Object?>{'protocolVersion': '2025-11-25'},
        });
        expect(
          ((initialized as Map)['result'] as Map)['capabilities'],
          containsPair('completions', isA<Map>()),
        );
        await server.handleMessage(<String, Object?>{
          'jsonrpc': '2.0',
          'method': 'notifications/initialized',
          'params': <String, Object?>{},
        });

        final promptResponse = await server.handleMessage(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'completion/complete',
          'params': <String, Object?>{
            'ref': <String, Object?>{
              'type': 'ref/prompt',
              'name': 'summarize-task',
            },
            'argument': <String, Object?>{'name': 'taskId', 'value': 'T-'},
            'context': <String, Object?>{
              'arguments': <String, String>{'project': 'alpha'},
            },
          },
        });
        expect(
          ((promptResponse as Map)['result'] as Map)['completion'],
          <String, Object?>{
            'values': <String>['T-100', 'T-101'],
            'total': 2,
            'hasMore': false,
          },
        );
        expect(seen.single.argument.value, 'T-');
        expect(
          seen.single.context!.arguments,
          containsPair('project', 'alpha'),
        );

        final resourceResponse = await server.handleMessage(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'completion/complete',
          'params': <String, Object?>{
            'ref': <String, Object?>{
              'type': 'ref/resource',
              'uri': 'app://tasks/{taskId}',
            },
            'argument': <String, Object?>{'name': 'taskId', 'value': 'T-2'},
          },
        });
        expect(
          (((resourceResponse as Map)['result'] as Map)['completion']
              as Map)['values'],
          <String>['T-200'],
        );
      },
    );

    test('rejects unknown references and undeclared arguments', () async {
      final server = McpServer(
        serverInfo: const McpServerInfo(name: 'completion-test', version: '1'),
        prompts: <McpPrompt>[
          McpPrompt(
            name: 'summarize-task',
            arguments: <McpPromptArgument>[
              McpPromptArgument(name: 'taskId'),
            ],
            handler: (_) => McpPromptResult.text('summary'),
            complete: (_) => McpCompletionResult(values: <String>[]),
          ),
        ],
      );
      await server.handleMessage(<String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, Object?>{'protocolVersion': '2025-11-25'},
      });
      await server.handleMessage(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
        'params': <String, Object?>{},
      });

      for (final params in <Map<String, Object?>>[
        <String, Object?>{
          'ref': <String, Object?>{'type': 'ref/prompt', 'name': 'missing'},
          'argument': <String, Object?>{'name': 'taskId', 'value': ''},
        },
        <String, Object?>{
          'ref': <String, Object?>{
            'type': 'ref/prompt',
            'name': 'summarize-task',
          },
          'argument': <String, Object?>{'name': 'unknown', 'value': ''},
        },
      ]) {
        final response = await server.handleMessage(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 'invalid',
          'method': 'completion/complete',
          'params': params,
        });
        expect(((response as Map)['error'] as Map)['code'], -32602);
      }
    });
  });
}
