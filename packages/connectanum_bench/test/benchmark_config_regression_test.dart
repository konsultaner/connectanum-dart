import 'dart:async';
import 'dart:convert';

import 'package:connectanum_bench/connectanum_bench.dart';
import 'package:test/test.dart';

Map<String, Object?> _scenario([Map<String, Object?> overrides = const {}]) => {
  'name': 'sample',
  'type': 'wamp_rawsocket_rpc',
  'duration': '1s',
  ...overrides,
};

void main() {
  group('benchmark configuration validation', () {
    for (final source in [
      '',
      'null',
      '[]',
      'true',
      '{}',
      'benchmarks: null',
      'benchmarks: {}',
      'benchmarks: []',
      'benchmarks: [null]',
      'benchmarks: [7]',
      'benchmarks: [[]]',
      'benchmarks: [{}]',
      'benchmarks: [',
    ]) {
      test('rejects malformed document ${jsonEncode(source)}', () {
        expect(() => BenchmarkConfig.fromYaml(source), throwsFormatException);
      });
    }

    for (final field in ['name', 'type', 'duration']) {
      for (final value in [
        null,
        '',
        7,
        true,
        <Object?>[],
        <String, Object?>{},
      ]) {
        test('rejects $field=${jsonEncode(value)}', () {
          expect(
            () => BenchmarkScenario.fromMap(_scenario({field: value})),
            throwsA(
              isA<FormatException>().having(
                (error) => error.message,
                'field diagnostic',
                contains('scenario.$field'),
              ),
            ),
          );
        });
      }
    }

    for (final field in ['duration', 'warmup']) {
      for (final value in ['1', '1d', '1.5s', 'ms', '1xs', '']) {
        test('rejects unsupported $field ${jsonEncode(value)}', () {
          expect(
            () => BenchmarkScenario.fromMap(_scenario({field: value})),
            throwsFormatException,
          );
        });
      }
    }

    for (final field in ['concurrency', 'rate']) {
      for (final value in [true, 2.5, '2.5', 'many', [], {}]) {
        test('rejects non-integer $field=${jsonEncode(value)}', () {
          expect(
            () => BenchmarkScenario.fromMap(_scenario({field: value})),
            throwsFormatException,
          );
        });
      }
    }

    for (final value in [
      true,
      'options',
      7,
      [],
      <int, String>{1: 'one'},
    ]) {
      test('rejects non-string-map extra $value', () {
        expect(
          () => BenchmarkScenario.fromMap(_scenario({'extra': value})),
          throwsFormatException,
        );
      });
    }
    for (final key in ['null', '1', 'true', '""', '[a, b]']) {
      test('rejects non-string or empty YAML key $key at every depth', () {
        for (final source in [
          '$key: []',
          'benchmarks: [{name: sample, type: rpc, duration: 1s, extra: {$key: 1}}]',
        ]) {
          expect(() => BenchmarkConfig.fromYaml(source), throwsFormatException);
        }
      });
    }
  });

  group('benchmark duration units and JSON', () {
    final durations = <String, (Duration, String)>{
      '0ms': (Duration.zero, '0h'),
      '1ms': (Duration(milliseconds: 1), '1ms'),
      '999ms': (Duration(milliseconds: 999), '999ms'),
      '1000ms': (Duration(seconds: 1), '1s'),
      '1001ms': (Duration(milliseconds: 1001), '1001ms'),
      '59s': (Duration(seconds: 59), '59s'),
      '60s': (Duration(minutes: 1), '1m'),
      '61s': (Duration(seconds: 61), '61s'),
      '59m': (Duration(minutes: 59), '59m'),
      '60m': (Duration(hours: 1), '1h'),
      '61m': (Duration(minutes: 61), '61m'),
      '25h': (Duration(hours: 25), '25h'),
      ' 2MS ': (Duration(milliseconds: 2), '2ms'),
      ' 2S ': (Duration(seconds: 2), '2s'),
      ' 2M ': (Duration(minutes: 2), '2m'),
      ' 2H ': (Duration(hours: 2), '2h'),
    };
    for (final entry in durations.entries) {
      test('parses and normalizes ${jsonEncode(entry.key)}', () {
        final scenario = _validConfigParse(
          () => BenchmarkScenario.fromMap(
            _scenario({'duration': entry.key, 'warmup': entry.key}),
          ),
        );
        expect(scenario.duration, entry.value.$1);
        expect(scenario.warmup, entry.value.$1);
        final json = scenario.toJson();
        expect(json['duration'], entry.value.$2);
        if (entry.value.$1 == Duration.zero) {
          expect(json.containsKey('warmup'), isFalse);
        } else {
          expect(json['warmup'], entry.value.$2);
        }
        final restored = _validConfigParse(
          () => BenchmarkScenario.fromMap(json),
        );
        expect(restored.duration, entry.value.$1);
        expect(restored.warmup, entry.value.$1);
      });
    }

    test('defaults omit optional fields but retain concurrency', () {
      final parsed = _validConfigParse(
        () => BenchmarkScenario.fromMap(_scenario()),
      );
      expect(parsed.name, 'sample');
      expect(parsed.type, 'wamp_rawsocket_rpc');
      expect(parsed.warmup, Duration.zero);
      expect(parsed.concurrency, 1);
      expect(parsed.targetRatePerSecond, isNull);
      expect(parsed.extra, isEmpty);
      expect(parsed.toJson(), {
        'name': 'sample',
        'type': 'wamp_rawsocket_rpc',
        'duration': '1s',
        'concurrency': 1,
      });
      expect(
        _validConfigParse(
          () => BenchmarkScenario.fromMap(
            _scenario({'extra': <String, Object?>{}, 'rate': null}),
          ),
        ).toJson(),
        parsed.toJson(),
      );
    });

    test('integer strings retain values and zero rate is not omitted', () {
      for (final value in [0, '0', 7, '7']) {
        final parsed = _validConfigParse(
          () => BenchmarkScenario.fromMap(
            _scenario({'concurrency': '3', 'rate': value}),
          ),
        );
        expect(parsed.concurrency, 3);
        final expected = value == 0 || value == '0' ? 0 : 7;
        expect(parsed.targetRatePerSecond, expected);
        expect(parsed.toJson()['rate'], expected);
      }
    });

    test('single wraps the supplied scenario and JSON preserves fields', () {
      final extra = <String, Object?>{'serializer': 'cbor', 'iterations': 12};
      final scenario = BenchmarkScenario(
        name: 'unicode-\u00e4',
        type: 'wamp_rawsocket_rpc',
        duration: const Duration(milliseconds: 1500),
        warmup: const Duration(milliseconds: 250),
        concurrency: 4,
        targetRatePerSecond: 100,
        extra: extra,
      );
      extra['serializer'] = 'json';
      final config = BenchmarkConfig.single(scenario);
      expect(config.scenarios, [same(scenario)]);
      expect(config.toPrettyJson(), contains('\n  "benchmarks": ['));
      expect(jsonDecode(config.toPrettyJson()), {
        'benchmarks': [
          {
            'name': 'unicode-\u00e4',
            'type': 'wamp_rawsocket_rpc',
            'duration': '1500ms',
            'warmup': '250ms',
            'concurrency': 4,
            'rate': 100,
            'extra': {'serializer': 'cbor', 'iterations': 12},
          },
        ],
      });
      expect(() => scenario.extra['new'] = true, throwsUnsupportedError);
    });

    test('YAML preserves declaration order and nested option types', () {
      final config = _validConfigParse(
        () => BenchmarkConfig.fromYaml('''
benchmarks:
  - name: first
    type: rpc
    duration: 2s
    warmup: 1ms
    concurrency: "2"
    rate: "7"
    extra:
      nested:
        enabled: true
        list: [null, 1, 1.5, text, {key: value}]
  - name: second
    type: pubsub
    duration: 1m
'''),
      );
      expect(config.scenarios, hasLength(2));
      expect(config.scenarios.map((scenario) => scenario.name), [
        'first',
        'second',
      ]);
      expect(config.scenarios.first.extra, {
        'nested': {
          'enabled': true,
          'list': [
            null,
            1,
            1.5,
            'text',
            {'key': 'value'},
          ],
        },
      });
      expect(config.scenarios.first.concurrency, 2);
      expect(config.scenarios.first.targetRatePerSecond, 7);
      expect(config.scenarios.first.warmup, const Duration(milliseconds: 1));
      final restored = _validConfigParse(
        () => BenchmarkConfig.fromYaml(config.toPrettyJson()),
      );
      expect(restored.scenarios.map((scenario) => scenario.toJson()), [
        for (final scenario in config.scenarios) scenario.toJson(),
      ]);
    });
  });

  group('benchmark configuration ownership', () {
    test('YAML scenario lists have fixed length but allow replacement', () {
      final config = _validConfigParse(
        () => BenchmarkConfig.fromYaml('''
benchmarks:
  - {name: first, type: rpc, duration: 1s}
  - {name: second, type: pubsub, duration: 2s}
'''),
      );
      expect(config.scenarios, hasLength(2));
      final first = config.scenarios.first;
      final second = config.scenarios.last;
      expect(() => config.scenarios.add(first), throwsUnsupportedError);
      expect(() => config.scenarios.removeLast(), throwsUnsupportedError);
      expect(config.scenarios, [same(first), same(second)]);
      config.scenarios[0] = second;
      expect(config.scenarios, [same(second), same(second)]);
    });

    test('nested YAML option lists retain fixed-length value semantics', () {
      final config = _validConfigParse(
        () => BenchmarkConfig.fromYaml('''
benchmarks:
  - name: sample
    type: rpc
    duration: 1s
    extra:
      sizes: [0, 4096]
      batches: [[1, 2]]
'''),
      );
      expect(config.scenarios, hasLength(1));
      final options = config.scenarios.single.extra;
      expect(options['sizes'], isA<List<Object?>>());
      expect(options['batches'], isA<List<Object?>>());
      final sizes = options['sizes']! as List<Object?>;
      final batches = options['batches']! as List<Object?>;
      expect(sizes, [0, 4096]);
      expect(batches, hasLength(1));
      expect(batches.single, isA<List<Object?>>());
      final inner = batches.single! as List<Object?>;
      for (final values in [sizes, batches, inner]) {
        final before = List<Object?>.of(values);
        expect(() => values.add(7), throwsUnsupportedError);
        expect(() => values.removeLast(), throwsUnsupportedError);
        expect(values, before);
      }
      sizes[1] = 8192;
      inner[0] = 3;
      final restored = _validConfigParse(
        () => BenchmarkConfig.fromYaml(config.toPrettyJson()),
      );
      expect(restored.scenarios, hasLength(1));
      expect(restored.scenarios.single.extra, {
        'sizes': [0, 8192],
        'batches': [
          [3, 2],
        ],
      });
    });

    test('map parsing copies options and does not track caller mutations', () {
      final options = <String, Object?>{'serializer': 'cbor', 'iterations': 7};
      final input = _scenario({'extra': options, 'rate': '0'});
      final scenario = _validConfigParse(
        () => BenchmarkScenario.fromMap(input),
      );
      input['name'] = 'changed';
      input['duration'] = '2h';
      options['serializer'] = 'json';
      options.clear();
      expect(scenario.name, 'sample');
      expect(scenario.duration, const Duration(seconds: 1));
      expect(scenario.targetRatePerSecond, 0);
      expect(scenario.extra, {'serializer': 'cbor', 'iterations': 7});
      expect(() => scenario.extra.clear(), throwsUnsupportedError);
      final json = scenario.toJson();
      json['name'] = 'external';
      json.remove('rate');
      expect(scenario.toJson(), {
        'name': 'sample',
        'type': 'wamp_rawsocket_rpc',
        'duration': '1s',
        'concurrency': 1,
        'rate': 0,
        'extra': {'serializer': 'cbor', 'iterations': 7},
      });
    });

    test('programmatic configs retain caller list semantics', () {
      final scenario = _validConfigParse(
        () => BenchmarkScenario.fromMap(_scenario()),
      );
      final scenarios = [scenario];
      final config = BenchmarkConfig(scenarios: scenarios);
      expect(config.scenarios, same(scenarios));
      scenarios.add(scenario);
      expect(config.scenarios, [same(scenario), same(scenario)]);
      final single = BenchmarkConfig.single(scenario);
      expect(single.scenarios, [same(scenario)]);
      single.scenarios.add(scenario);
      expect(single.scenarios, hasLength(2));
    });
  });

  group('valid configuration assertion controls', () {
    test('preserves nullable values and evaluates exactly once', () {
      final value = Object();
      var calls = 0;
      expect(
        _validConfigParse(() {
          calls++;
          return value;
        }),
        same(value),
      );
      expect(calls, 1);
      expect(_validConfigParse<Object?>(() => null), isNull);
    });
    for (final error in <Object>[
      const FormatException('rejected valid fixture'),
      RangeError('invalid duration substring'),
    ]) {
      test(
        'reports ${error.runtimeType} as a valid-input contract failure',
        () {
          var calls = 0;
          expect(
            () => _validConfigParse<void>(() {
              calls++;
              throw error;
            }),
            throwsA(
              isA<TestFailure>().having(
                (failure) => failure.message,
                'diagnostic',
                contains('Valid benchmark configuration must parse'),
              ),
            ),
          );
          expect(calls, 1);
        },
      );
    }
    for (final error in <Object>[
      TimeoutException('deadline'),
      UnsupportedError('platform unavailable'),
      ArgumentError('unrelated argument failure'),
      StateError('unrelated state failure'),
      TypeError(),
      const StackOverflowError(),
      const OutOfMemoryError(),
      TestFailure('original assertion'),
      Object(),
    ]) {
      test('does not relabel ${error.runtimeType} as an assertion', () {
        expect(
          () => _validConfigParse<void>(() => throw error),
          throwsA(same(error)),
        );
      });
    }
  });
}

// Valid in-memory fixtures must not be rejected by the parser. Unexpected
// runtime, infrastructure and resource failures keep their original identity.
T _validConfigParse<T>(T Function() parse) {
  try {
    return parse();
  } on FormatException catch (error) {
    fail('Valid benchmark configuration must parse: $error');
  } on RangeError catch (error) {
    fail('Valid benchmark configuration must parse: $error');
  }
}
