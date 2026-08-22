@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:connectanum_client/src/transport/native/external_byte_buffer.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../test_support/native_runtime_support.dart';

String? _nativeShaRuntimeSkipReason() {
  final unavailable = nativeClientRuntimeSkipReason();
  if (unavailable != null) {
    return unavailable;
  }
  try {
    NativeClientRuntime.instance();
    return null;
  } catch (error) {
    return 'Native SHA-256 runtime unavailable: $error';
  }
}

void main() {
  test('resolves nested subviews to the correct native byte range', () {
    final bytes = allocateNativeExternalBytes(256);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = index;
    }
    final firstView = Uint8List.sublistView(bytes, 31, 193);
    final nestedView = Uint8List.sublistView(firstView, 17, 83);
    final anchor = Object();
    retainNativeExternalBytes(anchor, bytes);

    final slice = nativeExternalByteSlice(nestedView, anchor: anchor);

    expect(slice, isNotNull);
    expect(slice!.length, nestedView.length);
    expect(
      slice.pointer.asTypedList(slice.length),
      orderedEquals(nestedView),
    );
    nestedView[0] = 211;
    expect(bytes[48], 211);
    expect(slice.pointer.value, 211);
    expect(nativeExternalByteSlice(nestedView), isNull);
  });

  test('does not resolve ordinary Dart-owned byte buffers', () {
    final bytes = Uint8List.fromList(const [1, 2, 3, 4]);

    expect(nativeExternalByteSlice(bytes), isNull);
    expect(nativeExternalByteSlice(Uint8List.sublistView(bytes, 1, 3)), isNull);
  });

  test('validates allocation lengths', () {
    expect(() => allocateNativeExternalBytes(-1), throwsRangeError);
    expect(allocateNativeExternalBytes(0), isEmpty);
  });

  test(
    'native SHA-256 hashes anchored subviews without changing the digest',
    () {
      final bytes = allocateNativeExternalBytes(128 * 1024);
      for (var index = 0; index < bytes.length; index++) {
        bytes[index] = (index * 31) & 0xff;
      }
      final view = Uint8List.sublistView(bytes, 97, bytes.length - 113);
      final anchor = Object();
      retainNativeExternalBytes(anchor, bytes);
      expect(nativeExternalByteSlice(view, anchor: anchor), isNotNull);

      final runtime = NativeClientRuntime.instance();
      final directHandle = runtime.createSha256State();
      expect(
        runtime.updateSha256(directHandle, view, anchor: anchor),
        view.length,
      );
      final directDigest = runtime.finalizeSha256State(directHandle);

      final fallbackBytes = Uint8List.fromList(view);
      final fallbackHandle = runtime.createSha256State();
      expect(
        runtime.updateSha256(fallbackHandle, fallbackBytes),
        fallbackBytes.length,
      );
      final fallbackDigest = runtime.finalizeSha256State(fallbackHandle);

      expect(directDigest, orderedEquals(fallbackDigest));
      expect(directDigest, orderedEquals(sha256.convert(view).bytes));
    },
    skip: _nativeShaRuntimeSkipReason(),
  );
}
