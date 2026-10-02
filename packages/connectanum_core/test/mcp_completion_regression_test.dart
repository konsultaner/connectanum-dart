import 'package:connectanum_core/connectanum_core.dart';
import 'package:test/test.dart';

const _privateValue = 'private-completion-value';

Map<String, Object?> _request() => {
  'ref': <Object?, Object?>{
    'type': 'ref/prompt',
    'name': 'find-task',
    'title': 'Find a task',
  },
  'argument': <Object?, Object?>{'name': 'taskId', 'value': 'T-'},
  'context': <Object?, Object?>{
    'arguments': <Object?, Object?>{'project': 'alpha'},
  },
};

void _replace(Map<String, Object?> json, List<String> path, Object? value) {
  Map current = json;
  for (final key in path.take(path.length - 1)) {
    current = current[key] as Map;
  }
  current[path.last] = value;
}

Map<String, Object?> _result(Object? values) => {
  'completion': {'values': values},
};

void main() {
  final malformed = throwsA(
    isA<FormatException>()
        .having((error) => error.source, 'source', isNull)
        .having((error) => error.offset, 'offset', isNull)
        .having(
          (error) => error.toString(),
          'redacted input',
          isNot(contains(_privateValue)),
        ),
  );
  final nonStrings = <Object?>[null, true, false, 7, 1.5, [], {}];

  group('MCP completion request boundaries', () {
    test('parses prompt fields without a self-round-trip oracle', () {
      final request = _valid(() => McpCompletionRequest.fromJson(_request()));
      expect(request.reference, isA<McpPromptReference>());
      final reference = request.reference as McpPromptReference;
      expect(reference.name, 'find-task');
      expect(reference.title, 'Find a task');
      expect(request.argument.name, 'taskId');
      expect(request.argument.value, 'T-');
      expect(request.context, isNotNull);
      expect(request.context!.arguments, {'project': 'alpha'});
      expect(request.toJson(), _request());
    });

    for (final uri in ['app://tasks/{taskId}', 'app://tasks/42']) {
      test('parses resource reference $uri', () {
        final json = _request()..['ref'] = {'type': 'ref/resource', 'uri': uri};
        final request = _valid(() => McpCompletionRequest.fromJson(json));
        expect(request.reference, isA<McpResourceTemplateReference>());
        expect((request.reference as McpResourceTemplateReference).uri, uri);
        expect(request.toJson()['ref'], {'type': 'ref/resource', 'uri': uri});
      });
    }

    for (final title in <String?>[null, '', 'A title with spaces']) {
      test('preserves optional prompt title ${title ?? "absent"}', () {
        final json = _request();
        (json['ref'] as Map)['title'] = title;
        final reference = _valid(
          () => McpCompletionRequest.fromJson(json),
        ).reference;
        expect(reference.toJson(), {
          'type': 'ref/prompt',
          'name': 'find-task',
          'title': ?title,
        });
      });
    }

    for (final value in ['', ' ', '\t\n', '\u00e4\u4e16\ud83d\ude00']) {
      test(
        'preserves arbitrary partial and context values ${value.length}',
        () {
          final json = _request();
          _replace(json, ['argument', 'value'], value);
          _replace(json, ['context', 'arguments', 'project'], value);
          final request = _valid(() => McpCompletionRequest.fromJson(json));
          expect(request.argument.value, value);
          expect(request.argument.toJson(), {'name': 'taskId', 'value': value});
          expect(request.context, isNotNull);
          expect(request.context!.arguments, {'project': value});
        },
      );
    }

    for (final omit in [false, true]) {
      test('accepts ${omit ? "missing" : "null"} optional context', () {
        final json = _request();
        if (omit) {
          json.remove('context');
        } else {
          json['context'] = null;
        }
        final request = _valid(() => McpCompletionRequest.fromJson(json));
        expect(request.context, isNull);
        expect(request.toJson().containsKey('context'), isFalse);
      });
    }

    for (final context in <Map<String, Object?>>[
      {},
      {'arguments': null},
      {'arguments': <String, String>{}},
    ]) {
      test('retains explicit empty context $context', () {
        final request = _valid(
          () =>
              McpCompletionRequest.fromJson(_request()..['context'] = context),
        );
        expect(request.context, isNotNull);
        expect(request.context!.arguments, isEmpty);
        expect(request.toJson()['context'], isEmpty);
      });
    }

    for (final path in <List<String>>[
      ['ref'],
      ['argument'],
      ['context'],
      ['context', 'arguments'],
    ]) {
      for (final value in <Object?>[
        null,
        true,
        false,
        7,
        1.5,
        [],
        _privateValue,
      ]) {
        if (value == null && path.first == 'context') continue;
        test('rejects non-object ${path.join(".")} ${value.runtimeType}', () {
          final json = _request();
          _replace(json, path, value);
          expect(() => McpCompletionRequest.fromJson(json), malformed);
        });
      }
      for (final key in <Object?>[null, true, 1, 1.5]) {
        test('rejects non-string key in ${path.join(".")} $key', () {
          final json = _request();
          Map current = json;
          for (final part in path) {
            current = current[part] as Map;
          }
          _replace(json, path, <Object?, Object?>{
            ...current,
            key: _privateValue,
          });
          expect(() => McpCompletionRequest.fromJson(json), malformed);
        });
      }
    }

    for (final path in <List<String>>[
      ['ref', 'type'],
      ['ref', 'name'],
      ['argument', 'name'],
      ['argument', 'value'],
    ]) {
      for (final value in nonStrings) {
        test('rejects non-string ${path.join(".")} ${value.runtimeType}', () {
          final json = _request();
          _replace(json, path, value);
          expect(() => McpCompletionRequest.fromJson(json), malformed);
        });
      }
    }

    for (final value in nonStrings.where((value) => value != null)) {
      test('rejects non-string optional title ${value.runtimeType}', () {
        final json = _request();
        _replace(json, ['ref', 'title'], value);
        expect(() => McpCompletionRequest.fromJson(json), malformed);
      });
    }

    for (final path in <List<String>>[
      ['ref', 'type'],
      ['ref', 'name'],
      ['argument', 'name'],
      ['argument', 'value'],
    ]) {
      test('string error identifies ${path.join(".")} and its constraint', () {
        final json = _request();
        _replace(json, path, null);
        final constraint = path.last == 'value'
            ? 'must be a string'
            : 'must be a non-empty string';
        expect(
          () => McpCompletionRequest.fromJson(json),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'field and constraint',
              'completion/complete.params.${path.join(".")} $constraint',
            ),
          ),
        );
      });
    }

    for (final value in nonStrings) {
      test('rejects non-string resource URI ${value.runtimeType}', () {
        final json = _request()
          ..['ref'] = {'type': 'ref/resource', 'uri': value};
        expect(() => McpCompletionRequest.fromJson(json), malformed);
      });
      test('rejects non-string context value ${value.runtimeType}', () {
        final json = _request();
        _replace(json, ['context', 'arguments', 'project'], value);
        expect(() => McpCompletionRequest.fromJson(json), malformed);
      });
    }

    for (final type in ['', 'ref/tool', 'REF/PROMPT', _privateValue]) {
      test('rejects unknown reference type $type', () {
        final json = _request();
        _replace(json, ['ref', 'type'], type);
        expect(() => McpCompletionRequest.fromJson(json), malformed);
      });
    }

    for (final path in <List<String>>[
      ['ref', 'name'],
      ['argument', 'name'],
    ]) {
      test('rejects empty wire name ${path.join(".")}', () {
        final json = _request();
        _replace(json, path, '');
        expect(() => McpCompletionRequest.fromJson(json), malformed);
      });
    }

    for (final name in ['', 'a b', 'a\tb', 'a\nb', 'a\u0000b', 'a\u00a0b']) {
      test('rejects invalid constructor names ${name.codeUnits}', () {
        expect(() => McpPromptReference(name: name), throwsArgumentError);
        expect(
          () => McpCompletionArgument(name: name, value: ''),
          throwsArgumentError,
        );
        expect(
          () => McpCompletionContext(arguments: {name: ''}),
          throwsArgumentError,
        );
      });
    }

    test('context takes an immutable snapshot on both construction paths', () {
      final input = {'project': 'alpha'};
      final direct = _valid(() => McpCompletionContext(arguments: input));
      final json = _request();
      _replace(json, ['context', 'arguments'], input);
      final request = _valid(() => McpCompletionRequest.fromJson(json));
      expect(request.context, isNotNull);
      final parsed = request.context!;
      input['project'] = 'changed';
      input['later'] = 'new';
      for (final context in [direct, parsed]) {
        expect(context.arguments, {'project': 'alpha'});
        expect(
          () => context.arguments['project'] = 'changed',
          throwsUnsupportedError,
        );
        final encoded = context.toJson()['arguments'] as Map;
        expect(() => encoded.clear(), throwsUnsupportedError);
        expect(context.arguments, {'project': 'alpha'});
      }
    });
  });

  group('MCP completion result boundaries', () {
    for (final count in [0, 1, 99, 100]) {
      for (final more in <bool?>[null, false, true]) {
        for (final total in <int?>[null, count, count + 1]) {
          test('preserves count=$count total=$total hasMore=$more', () {
            final values = List.generate(count, (index) => 'value-$index');
            final expected = {
              'completion': {
                'values': values,
                'total': ?total,
                'hasMore': ?more,
              },
            };
            final direct = _valid(
              () => McpCompletionResult(
                values: values,
                total: total,
                hasMore: more,
              ),
            );
            final parsed = _valid(() => McpCompletionResult.fromJson(expected));
            for (final result in [direct, parsed]) {
              expect(result.values, values);
              expect(result.total, total);
              expect(result.hasMore, more);
              expect(result.toJson(), expected);
            }
          });
        }
      }
    }

    test('accepts explicit null optionals and drops them from output', () {
      final result = _valid(
        () => McpCompletionResult.fromJson({
          'completion': {'values': <String>[], 'total': null, 'hasMore': null},
        }),
      );
      expect(result.toJson(), _result(<String>[]));
    });

    for (final count in [101, 102]) {
      test('rejects $count candidates without truncation', () {
        final values = List.generate(count, (index) => 'value-$index');
        expect(() => McpCompletionResult(values: values), throwsArgumentError);
        expect(() => McpCompletionResult.fromJson(_result(values)), malformed);
      });
    }
    for (final count in [0, 1, 100]) {
      test('rejects total less than returned count $count', () {
        final values = List.generate(count, (index) => 'value-$index');
        expect(
          () => McpCompletionResult(values: values, total: count - 1),
          throwsArgumentError,
        );
        final json = _result(values);
        (json['completion'] as Map)['total'] = count - 1;
        expect(() => McpCompletionResult.fromJson(json), malformed);
      });
    }

    for (final invalid in <Map<String, Object?>>[
      {'values': List.filled(101, _privateValue)},
      {
        'values': [_privateValue],
        'total': 0,
      },
    ]) {
      test(
        'wire errors expose the constraint, not ArgumentError internals $invalid',
        () {
          expect(
            () => McpCompletionResult.fromJson({'completion': invalid}),
            throwsA(
              isA<FormatException>()
                  .having(
                    (error) => error.message,
                    'constraint',
                    startsWith('MCP completion '),
                  )
                  .having(
                    (error) => error.message,
                    'no value dump',
                    isNot(contains(_privateValue)),
                  ),
            ),
          );
        },
      );
    }

    for (final value in <Object?>[null, <String>[]]) {
      test('rejects a single non-string candidate ${value.runtimeType}', () {
        expect(() => McpCompletionResult.fromJson(_result([value])), malformed);
      });
    }

    for (final value in <Object?>[null, true, 1, 1.5, [], _privateValue]) {
      test('rejects non-object completion ${value.runtimeType}', () {
        expect(
          () => McpCompletionResult.fromJson({'completion': value}),
          malformed,
        );
      });
    }
    for (final key in <Object?>[null, false, 1, 1.5]) {
      test('rejects non-string completion object key $key', () {
        expect(
          () => McpCompletionResult.fromJson({
            'completion': <Object?, Object?>{
              'values': <String>[],
              key: _privateValue,
            },
          }),
          malformed,
        );
      });
    }

    for (final value in <Object?>[
      null,
      true,
      false,
      7,
      1.5,
      {},
      _privateValue,
    ]) {
      test('rejects non-list candidate container ${value.runtimeType}', () {
        expect(() => McpCompletionResult.fromJson(_result(value)), malformed);
      });
      if (value is String) continue;
      for (final index in [0, 1]) {
        test('rejects non-string candidate ${value.runtimeType} at $index', () {
          final values = <Object?>[_privateValue, _privateValue];
          values[index] = value;
          expect(
            () => McpCompletionResult.fromJson(_result(values)),
            malformed,
          );
        });
      }
    }
    for (final value in <Object?>[true, false, 1.5, '1', [], {}]) {
      test('rejects non-integer total ${value.runtimeType} $value', () {
        final json = _result(<String>[]);
        (json['completion'] as Map)['total'] = value;
        expect(() => McpCompletionResult.fromJson(json), malformed);
      });
    }
    for (final value in <Object?>[0, 1, 1.5, 'true', [], {}]) {
      test('rejects non-boolean hasMore ${value.runtimeType} $value', () {
        final json = _result(<String>[]);
        (json['completion'] as Map)['hasMore'] = value;
        expect(() => McpCompletionResult.fromJson(json), malformed);
      });
    }

    test(
      'preserves candidate order, duplicates, empty and Unicode strings',
      () {
        final input = [
          'second',
          '',
          'second',
          '\u00e4\u4e16\ud83d\ude00',
          'first',
        ];
        final direct = _valid(
          () => McpCompletionResult(values: input.map((value) => value)),
        );
        final parsed = _valid(
          () => McpCompletionResult.fromJson(_result(input)),
        );
        input.clear();
        for (final result in [direct, parsed]) {
          expect(result.values, [
            'second',
            '',
            'second',
            '\u00e4\u4e16\ud83d\ude00',
            'first',
          ]);
          expect(() => result.values.add('new'), throwsUnsupportedError);
          expect(() => result.values[0] = 'changed', throwsUnsupportedError);
          final encoded =
              (result.toJson()['completion'] as Map)['values'] as List;
          expect(() => encoded.clear(), throwsUnsupportedError);
          expect(result.values.length, 5);
        }
      },
    );
  });
}

T _valid<T>(T Function() construct) {
  late T value;
  expect(() => value = construct(), returnsNormally);
  return value;
}
