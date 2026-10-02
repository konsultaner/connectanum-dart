import 'dart:convert';

import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:test/test.dart';

void main() {
  group('sample JSON boundary', () {
    test('numeric JSON spellings preserve all values and timing units', () {
      final sample = WampSample.fromJson(
        jsonDecode('''{
          "worker": 3.0,
          "iteration": 7.0,
          "latency_ms": 5,
          "request_bytes": 4294967296.0,
          "response_bytes": 4294967297.0,
          "started_at_us": 1000000.0,
          "completed_at_us": 1005000.0
        }''')
            as Map<String, Object?>,
      );
      expect(sample.worker, 3);
      expect(sample.iteration, 7);
      expect(sample.latencyMs, 5.0);
      expect(sample.requestBytes, 4294967296);
      expect(sample.responseBytes, 4294967297);
      expect(sample.startedAtUs, 1000000);
      expect(sample.completedAtUs, 1005000);
      expect(sample.toJson(), {
        'worker': 3,
        'iteration': 7,
        'latency_ms': 5.0,
        'request_bytes': 4294967296,
        'response_bytes': 4294967297,
        'started_at_us': 1000000,
        'completed_at_us': 1005000,
      });
    });

    for (final field in [
      'worker',
      'iteration',
      'latency_ms',
      'request_bytes',
      'response_bytes',
    ]) {
      for (final value in <Object?>[null, '1', true, [], {}]) {
        test('rejects $field=$value without coercing non-numbers', () {
          expect(
            () => WampSample.fromJson({..._json(), field: value}),
            throwsFormatException,
          );
        });
      }
      test('requires $field', () {
        final json = _json()..remove(field);
        expect(() => WampSample.fromJson(json), throwsFormatException);
      });
    }

    for (final field in ['started_at_us', 'completed_at_us']) {
      for (final value in <Object>['1', false, [], {}]) {
        test('rejects malformed optional $field=$value', () {
          expect(
            () => WampSample.fromJson({..._json(), field: value}),
            throwsFormatException,
          );
        });
      }
      test('preserves one-sided $field without inventing the other bound', () {
        final json = {..._json(), field: 1234};
        expect(WampSample.fromJson(json).toJson(), json);
      });
    }

    test('explicit null bounds are omitted and maps do not alias samples', () {
      final json = {
        ..._json(),
        'started_at_us': null,
        'completed_at_us': null,
      };
      final sample = WampSample.fromJson(json);
      json['worker'] = 99;
      final encoded = sample.toJson();
      expect(encoded, _json());
      encoded['request_bytes'] = 99;
      expect(sample.worker, 2);
      expect(sample.requestBytes, 23);
      expect(sample.toJson(), _json());
    });
  });

  group('sample timing boundaries', () {
    for (final latency in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('non-finite latency $latency cannot invent a measured span', () {
        final sample = WampSample(
          worker: 2,
          iteration: 4,
          latencyMs: latency,
          requestBytes: 23,
          responseBytes: 41,
        );
        expect(sample.startedAtUs, isNull);
        expect(sample.completedAtUs, isNull);
        expect(sample.toJson(), isNot(contains('started_at_us')));
        expect(sample.toJson(), isNot(contains('completed_at_us')));
        expect(WampSampleWindow.fromSamples([sample]), isNull);
      });
    }

    test('zero latency still has a valid, zero-length measured window', () {
      final sample = WampSample(
        worker: 0,
        iteration: 0,
        latencyMs: 0,
        requestBytes: 0,
        responseBytes: 0,
      );
      expect(sample.startedAtUs, isNotNull);
      expect(sample.startedAtUs, sample.completedAtUs);
      final window = WampSampleWindow.fromSamples([sample]);
      expect(window, isNotNull);
      expect(window!.elapsedMs, 0.0);
    });

    test('empty samples have no measured window', () {
      expect(WampSampleWindow.fromSamples([]), isNull);
    });

    test('unordered and nested samples use the outer wall-clock span', () {
      final samples = [
        _sample(4000, 7000),
        _sample(2000, 8000),
        _sample(3000, 5000),
        _sample(1000, 6000),
      ];
      for (final ordered in [samples, samples.reversed]) {
        final window = WampSampleWindow.fromSamples(ordered);
        expect(window, isNotNull);
        expect(window!.toJson(), {
          'started_at_us': 1000,
          'completed_at_us': 8000,
        });
        expect(window.elapsedMs, 7.0);
      }
    });

    test('incomplete samples cannot extend a valid measured window', () {
      final window = WampSampleWindow.fromSamples([
        _sample(0, null),
        _sample(null, 1000000),
        _sample(1000, 2500),
        _sample(9999, 9),
      ]);
      expect(window, isNotNull);
      expect(window!.startedAtUs, 1000);
      expect(window.completedAtUs, 2500);
      expect(window.elapsedMs, 1.5);
    });

    test('all incomplete samples provide no measured window', () {
      expect(
        WampSampleWindow.fromSamples([_sample(0, null), _sample(null, 9)]),
        isNull,
      );
    });
  });
}

Map<String, Object?> _json() => {
  'worker': 2,
  'iteration': 4,
  'latency_ms': 1.5,
  'request_bytes': 23,
  'response_bytes': 41,
};

WampSample _sample(int? start, int? end) => WampSample.fromJson({
  ..._json(),
  'started_at_us': start,
  'completed_at_us': end,
});
