// Cross-language schema fixtures; these are synthetic counters, not benchmarks.
import 'dart:convert';
import 'dart:io';
import 'package:connectanum_bench/src/encoded_wamp_volume.dart';
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
          final input = ownedCopyFixture(scenario);
          // Deliberately synthetic, distinct component observations exercise the
          // same volume producer as live reports without entering copy totals.
          final observations = {
            ['dart_owned_buffer_copy_breakdown', 'client']: native ? 0 : 31,
            ['dart_owned_buffer_copy_breakdown', 'router']: 0,
            ['native_codec_copy_breakdown', 'client']: native ? 41 : 0,
            ['native_codec_copy_breakdown', 'router']: 71,
          };
          for (final entry in observations.entries) {
            final before = {
              encodedWampVolumeVersionField: 1,
              encodedWampVolumeBytesField: 17,
              encodedWampVolumeRejectedField: 5,
            };
            copyMetricMapAt(
              input,
              entry.key,
            )['encoded_wamp_volume'] = encodedWampVolumeDelta(before, {
              ...before,
              encodedWampVolumeBytesField: 17 + entry.value,
            });
          }
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
                input,
                scenario: scenario,
              ),
            }),
          );
        }
      }
    }
  }
}
