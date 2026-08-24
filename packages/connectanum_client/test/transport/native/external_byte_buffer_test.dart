@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:convert';
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
    'native base64 decoder accepts anchored ranges and owns its result',
    () {
      final source = Uint8List.fromList(
        List<int>.generate(256 * 1024 + 1, (index) => (index * 31) & 0xff),
      );
      final encoded = ascii.encode(base64.encode(source));
      final root = allocateNativeExternalBytes(encoded.length + 37);
      root.setRange(19, 19 + encoded.length, encoded);
      final view = Uint8List.sublistView(root, 19, 19 + encoded.length);
      retainNativeExternalBytes(view, root);

      final runtime = NativeClientRuntime.instance();
      final decoded = runtime.decodeCanonicalBase64Bytes(
        view,
        0,
        view.length,
      );

      expect(decoded, orderedEquals(source));
      expect(
        runtime.decodeCanonicalBase64Bytes(
          Uint8List.fromList(ascii.encode('AB==')),
          0,
          4,
        ),
        isNull,
      );
    },
    skip: _nativeShaRuntimeSkipReason(),
  );

  test(
    'native base64 encoder accepts Dart and anchored input and owns its result',
    () {
      final source = Uint8List.fromList(
        List<int>.generate(256 * 1024 + 1, (index) => (index * 29) & 0xff),
      );
      final expected = ascii.encode(base64.encode(source));
      final runtime = NativeClientRuntime.instance();

      final encodedDart = runtime.encodeCanonicalBase64Bytes(source);
      expect(encodedDart, orderedEquals(expected));
      source.fillRange(0, source.length, 0);
      expect(encodedDart, orderedEquals(expected));

      final root = allocateNativeExternalBytes(256 * 1024 + 38);
      final view = Uint8List.sublistView(root, 19, root.length - 18);
      for (var index = 0; index < view.length; index++) {
        view[index] = (index * 31) & 0xff;
      }
      final externalExpected = ascii.encode(base64.encode(view));
      retainNativeExternalBytes(view, root);
      expect(nativeExternalByteSlice(view, anchor: view), isNotNull);

      final encodedExternal = runtime.encodeCanonicalBase64Bytes(view);
      expect(encodedExternal, orderedEquals(externalExpected));
      root.fillRange(0, root.length, 0);
      expect(encodedExternal, orderedEquals(externalExpected));
    },
    skip: _nativeShaRuntimeSkipReason(),
  );

  test(
    'native-owned bytes can be released after async SHA-256 takes ownership',
    () {
      final source = Uint8List.fromList(
        List<int>.generate(1024 * 1024, (index) => (index * 23) & 0xff),
      );
      final runtime = NativeClientRuntime.instance();
      final encoded = runtime.encodeCanonicalBase64Bytes(source)!;
      final handle = runtime.createSha256State();

      expect(runtime.updateSha256(handle, encoded), encoded.length);
      expect(NativeClientRuntime.releaseOwnedExternalBytes(encoded), isTrue);
      expect(NativeClientRuntime.releaseOwnedExternalBytes(encoded), isFalse);
      expect(
        NativeClientRuntime.releaseOwnedExternalBytes(source),
        isFalse,
      );
      expect(
        runtime.finalizeSha256State(handle),
        orderedEquals(
          sha256.convert(ascii.encode(base64.encode(source))).bytes,
        ),
      );
    },
    skip: _nativeShaRuntimeSkipReason(),
  );

  test(
    'native SHA-256 can consume an external owner without a copied queue input',
    () {
      final source = Uint8List.fromList(
        List<int>.generate(1024 * 1024, (index) => (index * 37) & 0xff),
      );
      final runtime = NativeClientRuntime.instance();
      final encoded = runtime.encodeCanonicalBase64Bytes(source)!;
      final handle = runtime.createSha256State();

      expect(
        runtime.updateSha256ByConsumingExternalBytes(handle, encoded),
        encoded.length,
      );
      expect(NativeClientRuntime.releaseOwnedExternalBytes(encoded), isFalse);
      expect(
        runtime.finalizeSha256State(handle),
        orderedEquals(
          sha256.convert(ascii.encode(base64.encode(source))).bytes,
        ),
      );
    },
    skip: _nativeShaRuntimeSkipReason(),
  );

  test(
    'native SHA-256 consumes an external owner when queueing fails',
    () {
      final runtime = NativeClientRuntime.instance();
      final encoded = runtime.encodeCanonicalBase64Bytes(
        Uint8List.fromList(List<int>.generate(1024, (index) => index & 0xff)),
      )!;

      expect(
        () => runtime.updateSha256ByConsumingExternalBytes(0, encoded),
        throwsA(
          isA<NativeTransportException>().having(
            (error) => error.code,
            'code',
            NativeTransportErrorCode.invalidArgument,
          ),
        ),
      );
      expect(NativeClientRuntime.releaseOwnedExternalBytes(encoded), isFalse);
    },
    skip: _nativeShaRuntimeSkipReason(),
  );

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

  test(
    'native SHA-256 queues an owned copy of large Dart buffers',
    () {
      final bytes = Uint8List.fromList(
        List<int>.generate(1024 * 1024, (index) => (index * 17) & 0xff),
      );
      final expected = sha256.convert(bytes).bytes;
      final runtime = NativeClientRuntime.instance();
      final handle = runtime.createSha256State();

      expect(runtime.updateSha256(handle, bytes), bytes.length);
      bytes.fillRange(0, bytes.length, 0);

      expect(runtime.finalizeSha256State(handle), orderedEquals(expected));
    },
    skip: _nativeShaRuntimeSkipReason(),
  );
}
