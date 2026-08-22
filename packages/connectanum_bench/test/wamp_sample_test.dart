import 'package:connectanum_bench/src/wamp_workload_runner.dart';
import 'package:test/test.dart';

void main() {
  group('WampSample timing', () {
    test('new samples capture the measured latency window', () {
      final sample = WampSample(
        worker: 0,
        iteration: 1,
        latencyMs: 12.5,
        requestBytes: 10,
        responseBytes: 20,
      );

      expect(sample.startedAtUs, isNotNull);
      expect(sample.completedAtUs, isNotNull);
      expect(sample.completedAtUs! - sample.startedAtUs!, 12500);
    });

    test('legacy JSON remains timing-free when decoded and encoded', () {
      final sample = WampSample.fromJson(_sampleJson());

      expect(sample.startedAtUs, isNull);
      expect(sample.completedAtUs, isNull);
      expect(sample.toJson(), _sampleJson());
    });

    test('timing bounds survive a JSON round trip', () {
      final json = _sampleJson(
        startedAtUs: 1000,
        completedAtUs: 3500,
      );

      expect(WampSample.fromJson(json).toJson(), json);
    });

    test('invalid latencies do not create timing bounds', () {
      final sample = WampSample(
        worker: 0,
        iteration: 1,
        latencyMs: -1,
        requestBytes: 10,
        responseBytes: 20,
      );

      expect(sample.startedAtUs, isNull);
      expect(sample.completedAtUs, isNull);
    });
  });

  group('WampSampleWindow', () {
    test('uses the wall-clock span for overlapping samples', () {
      final window = WampSampleWindow.fromSamples([
        _sample(startedAtUs: 1000, completedAtUs: 4000),
        _sample(startedAtUs: 2000, completedAtUs: 6000),
      ]);

      expect(window, isNotNull);
      expect(window!.startedAtUs, 1000);
      expect(window.completedAtUs, 6000);
      expect(window.elapsedMs, 5.0);
    });

    test('includes sequential gaps instead of summing latencies', () {
      final window = WampSampleWindow.fromSamples([
        _sample(startedAtUs: 1000, completedAtUs: 2000),
        _sample(startedAtUs: 3000, completedAtUs: 5000),
      ]);

      expect(window, isNotNull);
      expect(window!.elapsedMs, 4.0);
    });

    test('ignores incomplete and inverted bounds', () {
      final window = WampSampleWindow.fromSamples([
        _sample(startedAtUs: null, completedAtUs: null),
        _sample(startedAtUs: 5000, completedAtUs: 4000),
        _sample(startedAtUs: 7000, completedAtUs: 9000),
      ]);

      expect(window, isNotNull);
      expect(window!.toJson(), {
        'started_at_us': 7000,
        'completed_at_us': 9000,
      });
    });

    test('returns null when no valid bounds exist', () {
      final window = WampSampleWindow.fromSamples([
        _sample(startedAtUs: null, completedAtUs: null),
        _sample(startedAtUs: 5, completedAtUs: 4),
      ]);

      expect(window, isNull);
    });
  });
}

WampSample _sample({required int? startedAtUs, required int? completedAtUs}) {
  return WampSample.fromJson(
    _sampleJson(
      startedAtUs: startedAtUs,
      completedAtUs: completedAtUs,
    ),
  );
}

Map<String, Object?> _sampleJson({int? startedAtUs, int? completedAtUs}) => {
  'worker': 0,
  'iteration': 0,
  'latency_ms': 1.0,
  'request_bytes': 10,
  'response_bytes': 20,
  'started_at_us': ?startedAtUs,
  'completed_at_us': ?completedAtUs,
};
