import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectanum_core/src/message/result.dart';
import 'package:connectanum_core/src/serializer/abstract_serializer.dart';
import 'package:connectanum_core/src/serializer/cbor/serializer.dart'
    as cbor_serializer;
import 'package:connectanum_core/src/serializer/json/serializer.dart'
    as json_serializer;
import 'package:connectanum_core/src/serializer/msgpack/serializer.dart'
    as msgpack_serializer;

const _targetBytesPerRound = 64 * 1024 * 1024;
const _maximumControlIterationsPerRound = 5000;
const _maximumStructuredIterationsPerRound = 500;
const _maximumBinaryIterationsPerRound = 1000;
const _keywordArguments = <String, dynamic>{
  'key_0': 0,
  'key_1': 1,
  'key_2': 2,
  'key_3': 3,
  'key_4': 4,
  'key_5': 5,
  'key_6': 6,
  'key_7': 7,
  'key_8': 8,
  'key_9': 9,
  'key_10': 10,
  'key_11': 11,
  'key_12': 12,
  'key_13': 13,
  'key_14': 14,
  'key_15': 15,
  'key_16': 16,
  'key_17': 17,
  'key_18': 18,
  'key_19': 19,
  'key_20': 20,
  'key_21': 21,
  'key_22': 22,
  'key_23': 23,
  'key_24': 24,
  'key_25': 25,
  'key_26': 26,
  'key_27': 27,
  'key_28': 28,
  'key_29': 29,
  'key_30': 30,
  'key_31': 31,
  'key_32': 32,
  'key_33': 33,
  'key_34': 34,
  'key_35': 35,
  'key_36': 36,
  'key_37': 37,
  'key_38': 38,
  'key_39': 39,
  'key_40': 40,
  'key_41': 41,
  'key_42': 42,
  'key_43': 43,
  'key_44': 44,
  'key_45': 45,
  'key_46': 46,
  'key_47': 47,
  'key_48': 48,
  'key_49': 49,
  'key_50': 50,
  'key_51': 51,
  'key_52': 52,
  'key_53': 53,
  'key_54': 54,
  'key_55': 55,
  'key_56': 56,
  'key_57': 57,
  'key_58': 58,
  'key_59': 59,
  'key_60': 60,
  'key_61': 61,
  'key_62': 62,
  'key_63': 63,
  'key_64': 64,
  'key_65': 65,
  'key_66': 66,
  'key_67': 67,
  'key_68': 68,
  'key_69': 69,
  'key_70': 70,
  'key_71': 71,
  'key_72': 72,
  'key_73': 73,
  'key_74': 74,
  'key_75': 75,
  'key_76': 76,
  'key_77': 77,
  'key_78': 78,
  'key_79': 79,
  'key_80': 80,
  'key_81': 81,
  'key_82': 82,
  'key_83': 83,
  'key_84': 84,
  'key_85': 85,
  'key_86': 86,
  'key_87': 87,
  'key_88': 88,
  'key_89': 89,
  'key_90': 90,
  'key_91': 91,
  'key_92': 92,
  'key_93': 93,
  'key_94': 94,
  'key_95': 95,
  'key_96': 96,
  'key_97': 97,
  'key_98': 98,
  'key_99': 99,
  'key_100': 100,
  'key_101': 101,
  'key_102': 102,
  'key_103': 103,
  'key_104': 104,
  'key_105': 105,
  'key_106': 106,
  'key_107': 107,
  'key_108': 108,
  'key_109': 109,
  'key_110': 110,
  'key_111': 111,
  'key_112': 112,
  'key_113': 113,
  'key_114': 114,
  'key_115': 115,
  'key_116': 116,
  'key_117': 117,
  'key_118': 118,
  'key_119': 119,
  'key_120': 120,
  'key_121': 121,
  'key_122': 122,
  'key_123': 123,
  'key_124': 124,
  'key_125': 125,
  'key_126': 126,
  'key_127': 127,
};

Future<void> main(List<String> arguments) async {
  final label = arguments[0];
  final outputPath = arguments.length > 1 ? arguments[1] : null;
  final serializerFilter = arguments.length > 2 ? arguments[2] : null;
  final scenarioFilter = arguments.length > 3 ? arguments[3] : null;
  final iterationOverride = arguments.length > 4
      ? int.parse(arguments[4])
      : null;
  final showProgress = arguments.length > 5 && arguments[5] == 'progress';
  if (iterationOverride != null && iterationOverride <= 0) {
    throw ArgumentError.value(iterationOverride, 'iterationOverride');
  }
  await _writeProgress(showProgress, 'initializing serializers');
  final serializers = <String, AbstractSerializer>{
    'json': json_serializer.Serializer(),
    'msgpack': msgpack_serializer.Serializer(),
    'cbor': cbor_serializer.Serializer(),
  };
  const scenarios = <String>[
    'envelope_control',
    'arguments_7',
    'binary_64k',
    'keywords_128',
  ];
  await _writeProgress(showProgress, 'starting benchmark');
  final results = <Map<String, Object?>>[];

  for (final serializerEntry in serializers.entries) {
    if (serializerFilter != null && serializerFilter != serializerEntry.key) {
      continue;
    }
    for (final scenario in scenarios) {
      if (scenarioFilter != null && scenarioFilter != scenario) {
        continue;
      }
      await _writeProgress(
        showProgress,
        '${serializerEntry.key}/$scenario: constructing message',
      );
      final message = _messageForScenario(scenario);
      await _writeProgress(
        showProgress,
        '${serializerEntry.key}/$scenario: serializing frame',
      );
      final encoded = serializerEntry.value.serialize(message);
      final frame = encoded is Uint8List
          ? encoded
          : Uint8List.fromList(utf8.encode(encoded as String));
      final iterations =
          iterationOverride ??
          max(
            500,
            min(
              switch (scenario) {
                'envelope_control' => _maximumControlIterationsPerRound,
                'binary_64k' => _maximumBinaryIterationsPerRound,
                _ => _maximumStructuredIterationsPerRound,
              },
              _targetBytesPerRound ~/ frame.length,
            ),
          );
      final warmups = iterationOverride == null
          ? min(1000, max(100, iterations ~/ 5))
          : min(100, iterations);
      await _writeProgress(
        showProgress,
        '${serializerEntry.key}/$scenario: '
        '$warmups warmups, $iterations iterations per round',
      );
      var checksum = 0;
      for (var index = 0; index < warmups; index++) {
        checksum += _deserializeAndConsume(
          serializerEntry.value,
          frame,
          scenario,
        );
      }
      final samples = <Map<String, Object?>>[];
      for (var round = 0; round < 7; round++) {
        final stopwatch = Stopwatch()..start();
        for (var index = 0; index < iterations; index++) {
          checksum += _deserializeAndConsume(
            serializerEntry.value,
            frame,
            scenario,
          );
        }
        stopwatch.stop();
        final seconds = max(1, stopwatch.elapsedMicroseconds) / 1000000;
        samples.add({
          'ops_per_second': iterations / seconds,
          'gbit_per_second': frame.length * iterations * 8 / seconds / 1e9,
        });
        await _writeProgress(
          showProgress,
          '${serializerEntry.key}/$scenario: '
          'round ${round + 1}/7 in ${stopwatch.elapsedMicroseconds} us',
        );
      }
      results.add({
        'serializer': serializerEntry.key,
        'scenario': scenario,
        'frame_bytes': frame.length,
        'iterations_per_round': iterations,
        'warmups': warmups,
        'samples': samples,
        'checksum': checksum,
      });
    }
  }

  final output = jsonEncode({
    'label': label,
    'process': {
      'current_rss_bytes': ProcessInfo.currentRss,
      'max_rss_bytes': ProcessInfo.maxRss,
    },
    'results': results,
  });
  if (outputPath != null) {
    File(outputPath).writeAsStringSync('$output\n');
  }
  print(output);
}

Result _messageForScenario(String scenario) {
  switch (scenario) {
    case 'envelope_control':
      return Result(1, ResultDetails());
    case 'arguments_7':
      return Result(
        1,
        ResultDetails(),
        arguments: List<int>.generate(7, (index) => index + 1),
      );
    case 'binary_64k':
      return Result(
        1,
        ResultDetails(),
        arguments: <dynamic>[Uint8List(64 * 1024)],
      );
    case 'keywords_128':
      return Result(
        1,
        ResultDetails(),
        arguments: <dynamic>[],
        argumentsKeywords: _keywordArguments,
      );
  }
  throw ArgumentError.value(scenario, 'scenario');
}

Future<void> _writeProgress(bool enabled, String message) async {
  if (!enabled) {
    return;
  }
  stderr.writeln(message);
  await stderr.flush();
}

int _deserializeAndConsume(
  AbstractSerializer serializer,
  Uint8List frame,
  String scenario,
) {
  final result = serializer.deserialize(frame) as Result;
  switch (scenario) {
    case 'envelope_control':
      return result.callRequestId;
    case 'arguments_7':
      final values = result.arguments!;
      return values.length + (values.first as int) + (values.last as int);
    case 'binary_64k':
      final bytes = result.arguments!.single as Uint8List;
      return bytes.length + bytes.first + bytes.last;
    case 'keywords_128':
      final values = result.argumentsKeywords!;
      return values.length +
          (values['key_0'] as int) +
          (values['key_127'] as int);
  }
  throw ArgumentError.value(scenario, 'scenario');
}
