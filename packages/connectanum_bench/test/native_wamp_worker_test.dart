import 'package:connectanum_bench/src/native_wamp_worker.dart';
import 'package:test/test.dart';

void main() {
  test('native worker process metrics preserve byte counters', () {
    final metrics = NativeWampWorkerProcessMetrics.fromJson({
      'pid': 42,
      'rss_before_bytes': 67_108_864,
      'current_rss_bytes': 536_870_912,
      'max_rss_bytes': 805_306_368,
    });

    expect(metrics.pid, 42);
    expect(metrics.rssBeforeBytes, 67_108_864);
    expect(metrics.currentRssBytes, 536_870_912);
    expect(metrics.maxRssBytes, 805_306_368);
    expect(metrics.toJson(), {
      'pid': 42,
      'rss_before_bytes': 67_108_864,
      'current_rss_bytes': 536_870_912,
      'max_rss_bytes': 805_306_368,
    });
  });
}
