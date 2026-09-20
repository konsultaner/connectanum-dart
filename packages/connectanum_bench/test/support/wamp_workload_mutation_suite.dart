import 'package:test/test.dart';

import '../wamp_sample_test.dart' as sample;
import '../wamp_sample_boundaries_test.dart' as sample_boundaries;
import '../wamp_scenario_boundaries_test.dart' as scenario_boundaries;
import '../wamp_event_buffer_regression_test.dart' as event_buffer;
import '../wamp_pubsub_failure_regression_test.dart' as pubsub_failures;
import '../wamp_factory_regression_test.dart' as factory_regressions;
import '../wamp_session_factory_test.dart' as factories;
import '../wamp_session_wire_regression_test.dart' as wire;
import '../wamp_transport_targets_test.dart' as targets;
import '../wamp_transport_targets_boundaries_test.dart' as target_boundaries;
import '../wamp_transport_targets_ranking_test.dart' as target_ranking;
import '../wamp_workload_runner_test.dart' as workloads;

void main() {
  group('workload behavior', workloads.main);
  group('wire integration', wire.main);
  group('session factory', factories.main);
  group('factory regression matrix', factory_regressions.main);
  group('transport target selection', targets.main);
  group('sample accounting', sample.main);
  group('sample interchange boundaries', sample_boundaries.main);
  group('scenario configuration boundaries', scenario_boundaries.main);
  group('buffer failure preservation', event_buffer.main);
  group('pubsub failure ownership', pubsub_failures.main);
  group('transport target boundaries', target_boundaries.main);
  group('transport target ranking', target_ranking.main);
}
