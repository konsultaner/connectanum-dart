import 'package:connectanum_bench/connectanum_bench.dart';
import 'package:test/test.dart';

void main() {
  group('BenchmarkConfig', () {
    test('parses YAML scalar values into benchmark scenarios', () {
      final config = BenchmarkConfig.fromYaml('''
benchmarks:
  - name: rawsocket_rpc_package_runner
    type: wamp_rawsocket_rpc
    duration: 1ms
    concurrency: 2
    rate: 3
    extra:
      serializer: json
      path: bench.rpc.echo
      iterations: 1
      request_bytes: 16
''');

      final scenario = config.scenarios.single;
      expect(scenario.name, 'rawsocket_rpc_package_runner');
      expect(scenario.type, 'wamp_rawsocket_rpc');
      expect(scenario.duration, const Duration(milliseconds: 1));
      expect(scenario.concurrency, 2);
      expect(scenario.targetRatePerSecond, 3);
      expect(scenario.extra['serializer'], 'json');
      expect(scenario.extra['path'], 'bench.rpc.echo');
      expect(scenario.extra['iterations'], 1);
      expect(scenario.extra['request_bytes'], 16);
    });
  });
}
