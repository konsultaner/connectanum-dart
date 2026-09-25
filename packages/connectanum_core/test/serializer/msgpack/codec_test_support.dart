import 'dart:typed_data';

import 'package:connectanum_core/src/serializer/msgpack/codec.dart' as codec;
import 'package:test/test.dart';

// Valid inputs must complete, not just avoid a wrong value. Execute once so a
// stateful iterable is not consumed twice, then let the caller check the result.
T _success<T>(T Function() operation) {
  late T value;
  expect(() => value = operation(), returnsNormally);
  return value;
}

Uint8List serialize(Object? value) => _success(() => codec.serialize(value));

dynamic deserialize(Uint8List bytes) =>
    _success(() => codec.deserialize(bytes));
