@TestOn('vm')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:connectanum_client/src/transport/native/canonical_base64_io.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/json_serializer.dart' as json_serializer;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack_serializer;
import 'package:test/test.dart';

import '../../test_support/native_runtime_support.dart';

void main() {
  test(
    'native canonical JSON codecs preserve wire bytes and owned output',
    () {
      final source = Uint8List.fromList(
        List<int>.generate(
          nativeCanonicalBase64Threshold + 1,
          (index) => (index * 29) & 0xff,
        ),
      );
      final serializer = json_serializer.Serializer();
      installNativeCanonicalBase64Codecs(serializer);

      final fragments = serializer.serializeFragments(
        Call(41, 'bench.binary', arguments: [source]),
      )!;
      final wireBytes = Uint8List.fromList(
        fragments.expand((fragment) => fragment).toList(),
      );
      expect(
        wireBytes,
        orderedEquals(
          utf8.encode(
            serializer.serializeToString(
              Call(41, 'bench.binary', arguments: [source]),
            ),
          ),
        ),
      );
      final stringDecoded =
          serializer.deserializeFromString(utf8.decode(wireBytes)) as Call;
      final stringDecodedBinary = stringDecoded.arguments!.single as Uint8List;
      expect(stringDecodedBinary, orderedEquals(source));

      final decoded = serializer.deserialize(wireBytes) as Call;
      final decodedBinary = decoded.arguments!.single as Uint8List;
      expect(decodedBinary, orderedEquals(source));

      expect(
        NativeClientRuntime.releaseOwnedExternalBytes(fragments[1]),
        isTrue,
      );
      expect(
        NativeClientRuntime.releaseOwnedExternalBytes(decodedBinary),
        isTrue,
      );
      expect(
        NativeClientRuntime.releaseOwnedExternalBytes(stringDecodedBinary),
        isTrue,
      );
    },
    skip: nativeClientRuntimeSkipReason(),
  );

  test('native String base64 ranges own mutable independent results', () {
    final runtime = NativeClientRuntime.instance();
    final source = Uint8List.fromList(
      List.generate(65537, (i) => (i * 31) & 255),
    );
    final encoded = base64.encode(source);
    const prefix = 'é💡:';
    final input = '$prefix$encoded:tail☃';
    final first = runtime.decodeCanonicalBase64String(
      input,
      prefix.length,
      prefix.length + encoded.length,
    )!;
    final second = runtime.decodeCanonicalBase64String(
      input,
      prefix.length,
      prefix.length + encoded.length,
    )!;
    expect(first, orderedEquals(source));
    expect(second, orderedEquals(source));
    first[0] ^= 255;
    expect(second[0], source[0]);
    expect(first[0], isNot(second[0]));
    expect(NativeClientRuntime.releaseOwnedExternalBytes(first), isTrue);
    expect(second, orderedEquals(source));
    expect(NativeClientRuntime.releaseOwnedExternalBytes(second), isTrue);
    for (final context in ['', 'ascii:', 'é:', '💡:', 'x' * 4097]) {
      final contextual = '$context$encoded:suffix';
      final decoded = runtime.decodeCanonicalBase64String(
        contextual,
        context.length,
        context.length + encoded.length,
      )!;
      expect(decoded, orderedEquals(source));
      decoded[0] ^= 255;
      expect(source[0], 0);
      expect(NativeClientRuntime.releaseOwnedExternalBytes(decoded), isTrue);
    }
    expect(runtime.decodeCanonicalBase64String('', 0, 0), isEmpty);
    expect(
      () => runtime.decodeCanonicalBase64String(input, -1, 1),
      throwsRangeError,
    );
    expect(
      () => runtime.decodeCanonicalBase64String(input, 2, 1),
      throwsRangeError,
    );
    expect(
      () => runtime.decodeCanonicalBase64String(input, 0, input.length + 1),
      throwsRangeError,
    );
    for (final invalid in [
      'AB==',
      'AA=',
      'AA--',
      'AA__',
      'AA==extra',
      'éAAA',
      'A😀=',
    ]) {
      expect(
        runtime.decodeCanonicalBase64String(invalid, 0, invalid.length),
        isNull,
        reason: invalid,
      );
    }
  }, skip: nativeClientRuntimeSkipReason());

  test('native canonical JSON codecs ignore binary serializers', () {
    final serializer = msgpack_serializer.Serializer();
    final source = Uint8List.fromList(const [0, 1, 2, 253, 254, 255]);

    installNativeCanonicalBase64Codecs(serializer);
    final decoded =
        serializer.deserialize(
              serializer.serialize(
                Call(42, 'bench.binary', arguments: [source]),
              ),
            )
            as Call;

    expect(decoded.arguments!.single, orderedEquals(source));
  });
}
