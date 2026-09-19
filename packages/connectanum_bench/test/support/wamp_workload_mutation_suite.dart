import 'package:test/test.dart';

import '../wamp_sample_test.dart' as sample;
import '../wamp_session_factory_test.dart' as factories;
import '../wamp_session_wire_regression_test.dart' as wire;
import '../wamp_transport_targets_test.dart' as targets;
import '../wamp_workload_runner_test.dart' as workloads;

void main() {
  group('workload behavior', workloads.main);
  group('wire integration', wire.main);
  group('session factory', factories.main);
  group('transport target selection', targets.main);
  group('sample accounting', sample.main);
}
