import 'dart:typed_data';

import 'package:connectanum_bench/src/mqtt_gateway_measurement.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  test(
    'exact delivery aggregates latency without retaining payload buffers',
    () {
      final m = GatewayDeliveryMeasurement(
        payloadBytes: 128,
        requireOrder: true,
      )..begin(2, 3);
      for (var i = 0; i < 3; i++) {
        m.accept(gatewayBenchmarkPayload(128, 2, i, 100), 110 + i);
      }
      expect(m.complete, isTrue);
      expect(m.received, 3);
      expect(m.summary()['latency_histogram_us'], [
        [10, 1],
        [11, 1],
        [12, 1],
      ]);
      m.begin(3, 1);
      m.accept(gatewayBenchmarkPayload(128, 3, 0, 200), 210);
      expect(m.summary()['received'], 1);
    },
  );
  test(
    'independent concurrent RPCs report ordering without inventing a guarantee',
    () {
      final m = GatewayDeliveryMeasurement(
        payloadBytes: 24,
        requireOrder: false,
      )..begin(1, 2);
      m.accept(gatewayBenchmarkPayload(24, 1, 1, 100), 110);
      m.accept(gatewayBenchmarkPayload(24, 1, 0, 90), 120);
      expect(m.summary()['order_errors'], 2);
      expect(m.summary()['first_sent_us'], 90);
    },
  );
  test('warm, peak and post-drain memory are sampled separately', () {
    fakeAsync((clock) {
      var rss = 100;
      final meter = GatewayMemoryMeter(readRss: () => rss)..begin();
      rss = 250;
      clock.elapse(const Duration(milliseconds: 20));
      rss = 120;
      expect(meter.snapshot(), {
        'warm_rss_bytes': 100,
        'peak_rss_bytes': 250,
        'drained_rss_bytes': 120,
      });
      meter.close();
      rss = 1000;
      clock.elapse(const Duration(seconds: 1));
      meter.begin();
      expect(meter.snapshot()['peak_rss_bytes'], 1000);
    });
  });
  test('the production RSS sampler returns actual process memory', () {
    final meter = GatewayMemoryMeter()..begin();
    expect(meter.snapshot()['warm_rss_bytes'], greaterThan(0));
    meter.close();
  });
  test('malformed and incomplete benchmark inputs fail closed', () {
    expect(() => gatewayBenchmarkPayload(23, 1, 0, 100), throwsArgumentError);
    final m = GatewayDeliveryMeasurement(payloadBytes: 128, requireOrder: true);
    expect(() => m.begin(-1, 1), throwsArgumentError);
    expect(() => m.begin(1, 0), throwsArgumentError);
    expect(() => m.begin(1, 1000001), throwsArgumentError);
    expect(m.summary, throwsStateError);
    m.begin(1, 1);
    expect(() => m.accept(Uint8List(0), 110), throwsFormatException);
    for (final offset in [0, 4, 15, 127]) {
      final p = gatewayBenchmarkPayload(128, 1, 0, 100);
      p[offset] ^= 1;
      expect(() => m.accept(p, 110), throwsFormatException);
    }
    expect(
      () => m.accept(gatewayBenchmarkPayload(128, 1, 0, 100), 99),
      throwsFormatException,
    );
    m.accept(gatewayBenchmarkPayload(128, 1, 0, 100), 100);
    expect(m.summary, throwsStateError);
    expect(
      () => m.accept(gatewayBenchmarkPayload(128, 1, 0, 100), 110),
      throwsFormatException,
    );
    final short = GatewayDeliveryMeasurement(
      payloadBytes: 16,
      requireOrder: true,
    )..begin(1, 1);
    expect(() => short.accept(Uint8List(16), 110), throwsFormatException);
    final ordered = GatewayDeliveryMeasurement(
      payloadBytes: 24,
      requireOrder: true,
    )..begin(1, 2);
    expect(
      () => ordered.accept(gatewayBenchmarkPayload(24, 1, 1, 100), 110),
      throwsFormatException,
    );
  });
}
