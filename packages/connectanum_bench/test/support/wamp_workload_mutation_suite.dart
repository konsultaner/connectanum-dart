import 'package:test/test.dart';

import '../wamp_sample_test.dart' as sample;
import '../wamp_sample_boundaries_test.dart' as sample_boundaries;
import '../wamp_scenario_boundaries_test.dart' as scenario_boundaries;
import '../wamp_scenario_copy_test.dart' as scenario_copy;
import '../wamp_event_buffer_regression_test.dart' as event_buffer;
import '../wamp_pubsub_failure_regression_test.dart' as pubsub_failures;
import '../wamp_factory_regression_test.dart' as factory_regressions;
import '../wamp_session_factory_test.dart' as factories;
import '../wamp_session_wire_regression_test.dart' as wire;
import '../wamp_transport_targets_test.dart' as targets;
import '../wamp_transport_targets_boundaries_test.dart' as target_boundaries;
import '../wamp_transport_targets_ranking_test.dart' as target_ranking;
import '../wamp_workload_runner_test.dart' as workloads;
import '../wamp_workload_failure_regression_test.dart' as workload_failures;
import '../wamp_workload_timing_test.dart' as workload_timing;
import '../wamp_workload_diagnostics_regression_test.dart'
    as workload_diagnostics;
import '../wamp_file_workload_integrity_test.dart' as file_integrity;
import '../wamp_file_workload_scheduling_test.dart' as file_scheduling;
import '../wamp_file_registration_deadline_test.dart' as file_deadlines;
import '../wamp_file_cleanup_failure_test.dart' as file_cleanup;

void main() {
  group('workload behavior', workloads.main);
  group('workload failure regressions', workload_failures.main);
  group('workload latency and byte accounting', workload_timing.main);
  group('workload timeout and late cleanup', workload_diagnostics.main);
  group('file payload integrity', file_integrity.main);
  group('file transfer scheduling', file_scheduling.main);
  group('file registration deadlines', file_deadlines.main);
  group('file cleanup failures', file_cleanup.main);
  group('wire integration', wire.main);
  group('session factory', factories.main);
  group('factory regression matrix', factory_regressions.main);
  group('transport target selection', targets.main);
  group('sample accounting', sample.main);
  group('sample interchange boundaries', sample_boundaries.main);
  group('scenario configuration boundaries', scenario_boundaries.main);
  group('scenario copy isolation', scenario_copy.main);
  group('buffer failure preservation', event_buffer.main);
  group('pubsub failure ownership', pubsub_failures.main);
  group('transport target boundaries', target_boundaries.main);
  group('transport target ranking', target_ranking.main);
}
