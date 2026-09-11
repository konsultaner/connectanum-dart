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

void main(List<String> arguments) {
  final label = arguments[0];
  final serializerFilter = arguments.length > 2 ? arguments[2] : null;
  final scenarioFilter = arguments.length > 3 ? arguments[3] : null;
  final serializers = <String, AbstractSerializer>{
    'json': json_serializer.Serializer(),
    'msgpack': msgpack_serializer.Serializer(),
    'cbor': cbor_serializer.Serializer(),
  };
  final messages = <String, Result>{
    'control': Result(1, ResultDetails()),
    'structured_16k': Result(
      1,
      ResultDetails(),
      arguments: <dynamic>[
        <String, dynamic>{'text': 'x' * (16 * 1024)},
      ],
    ),
    'nested_16': Result(
      1,
      ResultDetails(),
      arguments: <dynamic>[_nestedList(16)],
    ),
    'array_1024': Result(
      1,
      ResultDetails(),
      arguments: <dynamic>[
        List<int>.generate(1024, (index) => index),
      ],
    ),
    'map_512': Result(
      1,
      ResultDetails(),
      arguments: <dynamic>[
        <String, int>{
          for (var index = 0; index < 512; index++) 'key_$index': index,
        },
      ],
    ),
  };
  final results = <Map<String, Object?>>[];

  for (final serializerEntry in serializers.entries) {
    if (serializerFilter != null && serializerFilter != serializerEntry.key) {
      continue;
    }
    for (final messageEntry in messages.entries) {
      if (scenarioFilter != null && scenarioFilter != messageEntry.key) {
        continue;
      }
      final encoded = serializerEntry.value.serialize(messageEntry.value);
      final frame = encoded is Uint8List
          ? encoded
          : Uint8List.fromList(utf8.encode(encoded as String));
      final iterations = max(
        2000,
        min(1000000, (256 * 1024 * 1024) ~/ frame.length),
      );
      final warmups = min(10000, max(1000, iterations ~/ 5));
      var checksum = 0;
      for (var index = 0; index < warmups; index++) {
        if (serializerEntry.value.deserialize(frame) != null) {
          checksum++;
        }
      }
      final samples = <Map<String, Object?>>[];
      for (var round = 0; round < 7; round++) {
        final stopwatch = Stopwatch()..start();
        for (var index = 0; index < iterations; index++) {
          if (serializerEntry.value.deserialize(frame) != null) {
            checksum++;
          }
        }
        stopwatch.stop();
        final seconds = stopwatch.elapsedMicroseconds / 1000000;
        samples.add({
          'ops_per_second': iterations / seconds,
          'gbit_per_second': frame.length * iterations * 8 / seconds / 1e9,
        });
      }
      results.add({
        'serializer': serializerEntry.key,
        'scenario': messageEntry.key,
        'frame_bytes': frame.length,
        'iterations_per_round': iterations,
        'warmups': warmups,
        'samples': samples,
        'checksum': checksum,
      });
    }
  }

  if ((serializerFilter == null || serializerFilter == 'cbor') &&
      (scenarioFilter == null || scenarioFilter == 'indefinite_control')) {
    final indefiniteCborFrame = Uint8List.fromList(const [
      0x9f,
      0x18,
      0x32,
      0x01,
      0xa0,
      0x81,
      0xf6,
      0xff,
    ]);
    final indefiniteCborSerializer = cbor_serializer.Serializer();
    final indefiniteIterations = max(
      2000,
      min(1000000, (256 * 1024 * 1024) ~/ indefiniteCborFrame.length),
    );
    final indefiniteWarmups = min(
      10000,
      max(1000, indefiniteIterations ~/ 5),
    );
    var indefiniteChecksum = 0;
    for (var index = 0; index < indefiniteWarmups; index++) {
      if (indefiniteCborSerializer.deserialize(indefiniteCborFrame) != null) {
        indefiniteChecksum++;
      }
    }
    final indefiniteSamples = <Map<String, Object?>>[];
    for (var round = 0; round < 7; round++) {
      final stopwatch = Stopwatch()..start();
      for (var index = 0; index < indefiniteIterations; index++) {
        if (indefiniteCborSerializer.deserialize(indefiniteCborFrame) != null) {
          indefiniteChecksum++;
        }
      }
      stopwatch.stop();
      final seconds = stopwatch.elapsedMicroseconds / 1000000;
      indefiniteSamples.add({
        'ops_per_second': indefiniteIterations / seconds,
        'gbit_per_second':
            indefiniteCborFrame.length *
            indefiniteIterations *
            8 /
            seconds /
            1e9,
      });
    }
    results.add({
      'serializer': 'cbor',
      'scenario': 'indefinite_control',
      'frame_bytes': indefiniteCborFrame.length,
      'iterations_per_round': indefiniteIterations,
      'warmups': indefiniteWarmups,
      'samples': indefiniteSamples,
      'checksum': indefiniteChecksum,
    });
  }

  final output = jsonEncode({
    'label': label,
    'process': {
      'current_rss_bytes': ProcessInfo.currentRss,
      'max_rss_bytes': ProcessInfo.maxRss,
    },
    'results': results,
  });
  if (arguments.length > 1) {
    File(arguments[1]).writeAsStringSync('$output\n');
  }
  print(output);
}

Object? _nestedList(int depth) {
  Object? value;
  for (var index = 0; index < depth; index++) {
    value = <dynamic>[value];
  }
  return value;
}
