// Cross-language schema fixtures; these are synthetic counters, not benchmarks.
import 'dart:convert';
import 'dart:io';
import 'package:connectanum_bench/src/owned_pipeline_copy_metrics.dart';
import 'owned_copy_fixtures.dart';

void main() {
  for (final native in [false, true]) {
    for (final secure in [false, true]) {
      for (final ws in [false, true]) {
        for (final file in [false, true]) {
          final scenario = ownedCopyScenario(
            native: native,
            secure: secure,
            ws: ws,
            fileTransfer: file,
          );
          stdout.writeln(
            jsonEncode({
              'name': '$native/$secure/$ws/$file',
              'client_impl': native ? 'native' : 'dart',
              'protocol':
                  'wamp_${ws ? "websocket" : "rawsocket"}_${file ? "file_transfer" : "rpc"}',
              'wamp_configuration': {
                ...scenario.toJson(),
                'secure_transport': secure,
              },
              'copy_metrics': mergeOwnedPipelineCopyMetrics(
                ownedCopyFixture(scenario),
                scenario: scenario,
              ),
            }),
          );
        }
      }
    }
  }
}
