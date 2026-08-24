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
