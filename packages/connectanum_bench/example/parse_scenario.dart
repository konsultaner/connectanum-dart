import 'package:connectanum_bench/connectanum_bench.dart';

void main() {
  final config = BenchmarkConfig.fromYaml('''
benchmarks:
  - name: websocket-smoke
    type: wamp_rpc
    duration: 5s
    concurrency: 8
''');

  print(config.toPrettyJson());
}
