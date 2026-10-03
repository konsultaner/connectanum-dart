import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;
import 'package:connectanum_core/json_serializer.dart' as json_codec;

/// Exercise the public Dart codec on native output and return frames to Rust.
void main(List<String> arguments) {
  final directory = Directory(arguments.single);
  final cases =
      jsonDecode(
            File(
              '../../schemas/wamp_flatbuffers/codec_cases.json',
            ).readAsStringSync(),
          )
          as List<dynamic>;
  final codec = flatbuffers.Serializer();
  final jsonCodec = json_codec.Serializer();
  for (final entry in cases.cast<Map<String, dynamic>>()) {
    final name = entry['name'] as String;
    final expected = name == 'heartbeat'
        ? Heartbeat(ping: 0, incoming: 0, outgoing: 0)
        : jsonCodec.deserialize(
            Uint8List.fromList(utf8.encode(jsonEncode(entry['message']))),
          );
    if (expected == null) {
      throw StateError('JSON reference codec did not reconstruct $name');
    }
    final actual = codec.deserialize(
      File('${directory.path}/rust_codec_$name.bin').readAsBytesSync(),
    )!;
    final matches = expected is Heartbeat
        ? actual is Heartbeat &&
              actual.ping == expected.ping &&
              actual.incoming == expected.incoming &&
              actual.outgoing == expected.outgoing &&
              same(actual.details, expected.details)
        : same(
            jsonDecode(jsonCodec.serialize(actual)),
            jsonDecode(jsonCodec.serialize(expected)),
          );
    if (!matches) {
      throw StateError('Native $name differs from the public Dart model');
    }
    File('${directory.path}/dart_codec_$name.bin').writeAsBytesSync(
      codec.serialize(actual),
    );
  }
  stdout.writeln(
    'Public Dart codec preserved all ${cases.length} native messages',
  );
}

bool same(Object? left, Object? right) {
  if (left is List && right is List) {
    return left.length == right.length &&
        List.generate(
          left.length,
          (index) => same(left[index], right[index]),
        ).every((value) => value);
  }
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && same(left[key], right[key]),
        );
  }
  return left == right;
}
