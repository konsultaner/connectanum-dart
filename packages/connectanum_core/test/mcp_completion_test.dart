import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

void main() {
  group('MCP completion protocol types', () {
    test('serialize prompt and resource-template completion requests', () {
      final promptRequest = _valid(
        () => McpCompletionRequest(
          reference: McpPromptReference(
            name: 'summarize-task',
            title: 'Summarize task',
          ),
          argument: McpCompletionArgument(name: 'taskId', value: 'T-'),
          context: McpCompletionContext(
            arguments: <String, String>{'project': 'alpha'},
          ),
        ),
      );
      expect(promptRequest.toJson(), <String, Object?>{
        'ref': <String, Object?>{
          'type': 'ref/prompt',
          'name': 'summarize-task',
          'title': 'Summarize task',
        },
        'argument': <String, Object?>{'name': 'taskId', 'value': 'T-'},
        'context': <String, Object?>{
          'arguments': <String, String>{'project': 'alpha'},
        },
      });

      final resourceRequest = _valid(
        () => McpCompletionRequest(
          reference: McpResourceTemplateReference(
            uri: 'app://tasks/{taskId}',
          ),
          argument: McpCompletionArgument(name: 'taskId', value: 'T-1'),
        ),
      );
      expect(resourceRequest.toJson()['ref'], <String, Object?>{
        'type': 'ref/resource',
        'uri': 'app://tasks/{taskId}',
      });
      expect(
        _valid(
          () => McpCompletionRequest.fromJson(resourceRequest.toJson()),
        ).toJson(),
        resourceRequest.toJson(),
      );
    });

    test('completion results enforce the protocol response bound', () {
      final result = _valid(
        () => McpCompletionResult(
          values: const <String>['T-100', 'T-101'],
          total: 3,
          hasMore: true,
        ),
      );
      expect(result.toJson(), <String, Object?>{
        'completion': <String, Object?>{
          'values': <String>['T-100', 'T-101'],
          'total': 3,
          'hasMore': true,
        },
      });
      expect(
        () => McpCompletionResult(
          values: List<String>.generate(101, (index) => '$index'),
        ),
        throwsArgumentError,
      );
      expect(
        () => McpCompletionResult(values: const ['one'], total: 0),
        throwsArgumentError,
      );
    });
  });
}

T _valid<T>(T Function() construct) {
  late T value;
  expect(() => value = construct(), returnsNormally);
  return value;
}
