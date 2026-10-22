import 'package:test/test.dart';

import '../../benchmark/mqtt_qos0.dart';

void main() {
  test('large-payload warmup waits every bounded publish window', () async {
    final published = <int>[];
    final waited = <int>[];
    await publishMqttBenchmarkWarmup(
      messageCount: 100,
      windowMessages: 32,
      publish: (index) async {
        published.add(index);
      },
      waitForDelivery: (target) async {
        waited.add(target);
        expect(published.length, target);
      },
    );
    expect(published, List<int>.generate(100, (index) => index));
    expect(waited, [32, 64, 96, 100]);
  });

  test('unwindowed warmup keeps its original publish cadence', () async {
    var published = 0;
    var waits = 0;
    await publishMqttBenchmarkWarmup(
      messageCount: 3,
      windowMessages: 0,
      publish: (_) async {
        published++;
      },
      waitForDelivery: (_) async {
        waits++;
      },
    );
    expect(published, 3);
    expect(waits, 0);
  });
}
