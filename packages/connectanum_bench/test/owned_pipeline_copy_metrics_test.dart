import 'dart:convert';
import 'package:connectanum_bench/src/encoded_wamp_volume.dart';
import 'package:connectanum_bench/src/codec_copy_metrics.dart';
import 'package:connectanum_bench/src/owned_copy_metrics.dart';
import 'package:connectanum_bench/src/raw_frame_copy_metrics.dart';
import 'package:test/test.dart';
import 'package:connectanum_bench/src/native_crypto_copy_metrics.dart';
import 'package:connectanum_bench/src/owned_pipeline_copy_metrics.dart';

import 'support/owned_copy_fixtures.dart';

void main() {
  test(
    'encoded message volume is independent of E2EE and transcode copy totals',
    () {
      final scenario = ownedCopyScenario();
      final input = ownedCopyFixture(scenario);
      final before = mergeOwnedPipelineCopyMetrics(input, scenario: scenario);
      final boundaries = [
        ['dart_owned_buffer_copy_breakdown', 'client'],
        ['dart_owned_buffer_copy_breakdown', 'router'],
        ['native_codec_copy_breakdown', 'client'],
        ['native_codec_copy_breakdown', 'router'],
      ];
      for (var i = 0; i < boundaries.length; i++) {
        copyMetricMapAt(input, boundaries[i])['encoded_wamp_volume'] = {
          'status': 'measured',
          'measurement_scope': encodedWampVolumeScope,
          'accepted_bytes': (i + 1) * 11,
          'rejected_submissions': 0,
        };
      }
      final measured = mergeOwnedPipelineCopyMetrics(input, scenario: scenario);
      final volume = measured['encoded_wamp_volume'] as Map;
      expect(volume['status'], 'measured');
      expect(volume['accepted_bytes'], 110);
      expect(volume['components'], {
        'client_dart': 11,
        'router_dart': 22,
        'client_native': 33,
        'router_native': 44,
      });
      for (final field in ['e2ee_copy_bytes', 'transcode_copy_bytes']) {
        expect(measured[field], before[field]);
      }
      copyMetricMapAt(input, boundaries.last).remove('encoded_wamp_volume');
      final incomplete = mergeOwnedPipelineCopyMetrics(
        input,
        scenario: scenario,
      );
      expect(
        (incomplete['encoded_wamp_volume'] as Map)['status'],
        'not_measured',
      );
      expect(
        incomplete['transcode_copy_bytes'],
        before['transcode_copy_bytes'],
      );
    },
  );

  test(
    'Dart transport retains supporting native codec/hash copy observations',
    () {
      final scenario = ownedCopyScenario(native: false);
      final input = ownedCopyFixture(scenario);
      copyMetricMapAt(input, ['native_codec_copy_breakdown'])['client'] =
          codecCopyComponent(23);
      copyMetricMapAt(input, ['raw_frame_copy_breakdown'])['client'] =
          rawCopyComponent(31);
      final result = mergeOwnedPipelineCopyMetrics(input, scenario: scenario);
      expect(result['e2ee_copy_bytes'], 18 + 70 + 23 + 29 + 31 + 37 + 10);
    },
  );

  for (final native in [true, false]) {
    for (final secure in [true, false]) {
      for (final ws in [true, false]) {
        test('disjoint owned totals native=$native secure=$secure ws=$ws', () {
          final scenario = ownedCopyScenario(
            native: native,
            secure: secure,
            ws: ws,
          );
          final input = ownedCopyFixture(scenario);
          final original = jsonEncode(input);
          final result = mergeOwnedPipelineCopyMetrics(
            input,
            scenario: scenario,
          );
          final transport = input['transport_copy_bytes'] as int;
          final expected =
              18 + 70 + 29 + 37 + transport + (native ? 23 + 31 + 7 : 0);
          expect(result['e2ee_copy_bytes'], expected);
          expect(result['transcode_copy_bytes'], 136);
          final breakdown = result['e2ee_copy_breakdown'] as Map;
          expect(breakdown['coverage'], 'complete_connectanum_owned_path');
          expect(
            breakdown['non_transport_owned_copy_bytes'],
            expected - transport,
          );
          expect(breakdown['unknown_boundaries'], isEmpty);
          expect(
            breakdown['provider_staging_diagnostics'],
            input['e2ee_copy_breakdown'],
          );
          expect(
            breakdown['unmeasured_dependency_boundaries'],
            contains('crypto_dependency_internals'),
          );
          expect(jsonEncode(input), original);
        });
      }
    }
  }
  for (final encrypted in [true, false]) {
    for (final mixed in [true, false]) {
      test(
        'only applicable totals are replaced e2ee=$encrypted mixed=$mixed',
        () {
          final scenario = ownedCopyScenario(
            encrypted: encrypted,
            mixed: mixed,
          );
          final result = mergeOwnedPipelineCopyMetrics(
            ownedCopyFixture(scenario),
            scenario: scenario,
          );
          expect(
            result['e2ee_copy_bytes'],
            encrypted ? isA<int>() : isA<Map>(),
          );
          expect(
            result['transcode_copy_bytes'],
            mixed ? isA<int>() : isA<Map>(),
          );
        },
      );
    }
  }
  final componentFields = <List<String>, List<String>>{
    ['dart_owned_buffer_copy_breakdown', 'client']: [
      ...ownedCopyObservationFields,
      'known_copy_bytes',
    ],
    ['dart_owned_buffer_copy_breakdown', 'router', 'main_isolate']: [
      ...ownedCopyObservationFields,
      'known_copy_bytes',
    ],
    ['dart_owned_buffer_copy_breakdown', 'router', 'workers', '9']: [
      ...ownedCopyObservationFields,
      'known_copy_bytes',
    ],
    ['native_codec_copy_breakdown', 'client']: [
      ...codecCopyMetricFields,
      'known_copy_bytes',
    ],
    ['native_codec_copy_breakdown', 'router']: [
      ...codecCopyMetricFields,
      'known_copy_bytes',
    ],
    ['raw_frame_copy_breakdown', 'client']: [
      ...rawFrameCopyMetricFields,
      'known_copy_bytes',
    ],
    ['raw_frame_copy_breakdown', 'router']: [
      ...rawFrameCopyMetricFields,
      'known_copy_bytes',
    ],
    ['native_crypto_copy_breakdown']: [
      ...nativeCryptoCopyFields,
      'known_copy_bytes',
    ],
  };
  for (final entry in componentFields.entries) {
    for (final field in entry.value) {
      for (final invalid in <Object?>[null, -1, true, 1.0, '1', [], {}]) {
        test('${entry.key}.$field=$invalid cannot certify E2EE', () {
          final scenario = ownedCopyScenario();
          final input = ownedCopyFixture(scenario);
          copyMetricMapAt(input, entry.key)[field] = invalid;
          final result = mergeOwnedPipelineCopyMetrics(
            input,
            scenario: scenario,
          );
          expect((result['e2ee_copy_bytes'] as Map)['status'], 'not_measured');
          expect((result['e2ee_copy_breakdown'] as Map)['coverage'], 'partial');
          if (entry.key.contains('router')) {
            expect(
              (result['transcode_copy_bytes'] as Map)['status'],
              'not_measured',
            );
          }
        });
      }
    }
  }
  for (final path in componentFields.keys) {
    test('forged subtotal $path cannot certify totals', () {
      final scenario = ownedCopyScenario();
      final input = ownedCopyFixture(scenario);
      final map = copyMetricMapAt(input, path);
      map['known_copy_bytes'] = (map['known_copy_bytes'] as int) + 1;
      expect(
        (mergeOwnedPipelineCopyMetrics(
              input,
              scenario: scenario,
            )['e2ee_copy_bytes']
            as Map)['status'],
        'not_measured',
      );
    });
  }
  for (final field in [
    'failed_copy_operations',
    'unmeasured_copy_operations',
  ]) {
    test('a positive $field prevents certification', () {
      final scenario = ownedCopyScenario();
      final input = ownedCopyFixture(scenario);
      copyMetricMapAt(input, [
        'dart_owned_buffer_copy_breakdown',
        'client',
      ])[field] = 1;
      expect(
        (mergeOwnedPipelineCopyMetrics(
              input,
              scenario: scenario,
            )['e2ee_copy_bytes']
            as Map)['status'],
        'not_measured',
      );
    });
  }
  test('native and portable provider mismatch is unavailable', () {
    final scenario = ownedCopyScenario();
    final input = ownedCopyFixture(scenario);
    final client = copyMetricMapAt(input, [
      'dart_owned_buffer_copy_breakdown',
      'client',
    ]);
    client['portable_crypto_copy_bytes'] = 5;
    client['known_copy_bytes'] = 23;
    expect(
      (mergeOwnedPipelineCopyMetrics(
            input,
            scenario: scenario,
          )['e2ee_copy_bytes']
          as Map)['status'],
      'not_measured',
    );
  });
  test(
    'client unknowns do not hide independently measured router transcodes',
    () {
      final scenario = ownedCopyScenario();
      final input = ownedCopyFixture(scenario);
      copyMetricMapAt(input, ['native_crypto_copy_breakdown'])['status'] =
          'not_measured';
      final result = mergeOwnedPipelineCopyMetrics(input, scenario: scenario);
      expect((result['e2ee_copy_bytes'] as Map)['status'], 'not_measured');
      expect(result['transcode_copy_bytes'], 136);
    },
  );
  final malformed = <void Function(Map)>[
    (input) => input['measurement_scope'] = 'legacy',
    (input) => input['transport_copy_bytes'] = 9,
    (input) =>
        copyMetricMapAt(input, ['coverage'])['unknown_boundaries'] = <String>[
          'missing bridge',
        ],
    (input) =>
        copyMetricMapAt(input, ['coverage'])['unknown_boundaries'] = null,
    (input) => copyMetricMapAt(input, [
      'coverage',
    ])['unmeasured_dependency_boundaries'] = <String>['unexpected'],
    (input) => copyMetricMapAt(input, [
      'coverage',
    ])['unmeasured_dependency_boundaries'] = <Object>[true],
    (input) => copyMetricMapAt(input, [
      'coverage',
    ])['unmeasured_dependency_boundaries'] = null,
    (input) => copyMetricMapAt(input, ['coverage'])['transport_copy_bytes'] =
        'partial',
    (input) => copyMetricMapAt(input, [
      'known_own_copy_breakdown',
      'client',
    ]).remove('dart_to_native_copy_bytes'),
    (input) => copyMetricMapAt(input, [
      'known_own_copy_breakdown',
      'router',
    ])['io_buffer_front_copy_bytes'] = true,
    (input) => copyMetricMapAt(input, [
      'dart_owned_buffer_copy_breakdown',
      'router',
    ])['known_copy_bytes'] = 0,
    (input) => copyMetricMapAt(input, [
      'dart_owned_buffer_copy_breakdown',
      'router',
    ])['boss_generation'] = 0,
    (input) => copyMetricMapAt(input, [
      'dart_owned_buffer_copy_breakdown',
      'router',
    ])['boss_generation'] = '3',
    (input) => copyMetricMapAt(input, [
      'dart_owned_buffer_copy_breakdown',
      'router',
    ])['workers'] = {},
    (input) => copyMetricMapAt(input, [
      'dart_owned_buffer_copy_breakdown',
      'router',
    ])['workers'] = {'': dartCopyComponent(1)},
    (input) => copyMetricMapAt(input, [
      'dart_owned_buffer_copy_breakdown',
      'router',
    ])['workers'] = {1: dartCopyComponent(1)},
    (input) => input['dart_owned_buffer_copy_breakdown'] = {},
    (input) =>
        input['native_codec_copy_breakdown'] = {1: codecCopyComponent(1)},
    (input) =>
        input['native_crypto_copy_breakdown'] = {'status': 'not_measured'},
    (input) =>
        copyMetricMapAt(input, ['native_crypto_copy_breakdown'])['active'] =
            false,
  ];
  for (var i = 0; i < malformed.length; i++) {
    test(
      'malformed total or ownership input $i fails closed without throwing',
      () {
        final scenario = ownedCopyScenario();
        final input = ownedCopyFixture(scenario);
        malformed[i](input);
        final result = mergeOwnedPipelineCopyMetrics(input, scenario: scenario);
        expect((result['e2ee_copy_bytes'] as Map)['status'], 'not_measured');
        expect(
          (result['e2ee_copy_breakdown'] as Map)['unknown_boundaries'],
          isNotEmpty,
        );
      },
    );
  }
  for (final field in nativeCryptoCopyFields) {
    test('inactive native crypto field $field cannot invent activity', () {
      final scenario = ownedCopyScenario(native: false);
      final input = ownedCopyFixture(scenario);
      copyMetricMapAt(input, ['native_crypto_copy_breakdown'])[field] = 1;
      expect(
        (mergeOwnedPipelineCopyMetrics(
              input,
              scenario: scenario,
            )['e2ee_copy_bytes']
            as Map)['status'],
        'not_measured',
      );
    });
  }
  for (final field in nativeCryptoCopyFields.take(3)) {
    test('inactive local bridge field $field cannot be absent', () {
      final scenario = ownedCopyScenario(native: false);
      final input = ownedCopyFixture(scenario);
      copyMetricMapAt(input, ['native_crypto_copy_breakdown'])[field] = null;
      expect(
        (mergeOwnedPipelineCopyMetrics(
              input,
              scenario: scenario,
            )['e2ee_copy_bytes']
            as Map)['status'],
        'not_measured',
      );
    });
  }
}
