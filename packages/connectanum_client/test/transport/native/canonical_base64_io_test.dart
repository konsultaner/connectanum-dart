@TestOn('vm')
library;

import 'dart:convert';
import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:connectanum_client/src/transport/native/ffi_bindings.dart';
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
    'public TypedData decoder releases borrowed offset input on every result',
    () {
      final runtime = NativeClientRuntime.instance();
      final bindings = CtFfiBindings(
        ffi.DynamicLibrary.open(runtime.libraryPath),
      );
      final decode = bindings.ctBase64DecodeVmBytes;
      final vm = ffi.DynamicLibrary.process();
      if (decode == null || !vm.providesSymbol('Dart_TypedDataAcquireData')) {
        expect(runtime.supportsCanonicalByteFrames, isFalse);
        final fallback = runtime.decodeCanonicalBase64Bytes(
          Uint8List.fromList(ascii.encode('AQID')),
          0,
          4,
        )!;
        expect(fallback, [1, 2, 3]);
        expect(NativeClientRuntime.releaseOwnedExternalBytes(fallback), isTrue);
        return;
      }
      final acquire = vm
          .lookup<ffi.NativeFunction<DartApiTypedDataAcquireNative>>(
            'Dart_TypedDataAcquireData',
          );
      final release = vm
          .lookup<ffi.NativeFunction<DartApiTypedDataReleaseNative>>(
            'Dart_TypedDataReleaseData',
          );
      final isError = vm.lookup<ffi.NativeFunction<DartApiIsErrorNative>>(
        'Dart_IsError',
      );
      for (final (encoded, expected) in [
        ('AQID', NativeTransportErrorCode.success),
        ('AB==', NativeTransportErrorCode.unsupported),
        ('A?AA', NativeTransportErrorCode.unsupported),
        ('AQI', NativeTransportErrorCode.unsupported),
      ]) {
        final backing = Uint8List.fromList([
          99,
          ...ascii.encode('xx${encoded}yy'),
          100,
        ]);
        final input = Uint8List.sublistView(
          backing,
          1,
          backing.length - 1,
        ).asUnmodifiableView();
        final out = calloc<CtExternalByteBuffer>();
        try {
          expect(
            decode(
              input,
              2,
              2 + encoded.length,
              acquire,
              release,
              isError,
              out,
            ),
            expected,
            reason: encoded,
          );
          backing.fillRange(0, backing.length, 0xee);
          // Managed allocation after the call also checks the VM acquire scope ended.
          expect(Uint8List(1024).length, 1024);
          if (expected == NativeTransportErrorCode.success) {
            expect(out.ref.ptr.asTypedList(out.ref.len), [1, 2, 3]);
            expect(out.ref.owner, isNot(ffi.nullptr));
          } else {
            expect(out.ref.ptr, ffi.nullptr);
            expect(out.ref.len, 0);
            expect(out.ref.owner, ffi.nullptr);
          }
        } finally {
          if (out.ref.owner != ffi.nullptr) {
            bindings.ctExternalByteBufferFree(out.ref.owner);
          }
          calloc.free(out);
        }
      }
      final data = Uint8List.fromList(
        List.generate(65537, (i) => (i * 37) & 255),
      );
      final encoded = Uint8List.fromList([
        0,
        ...ascii.encode(base64.encode(data)),
        0,
      ]);
      final result = runtime.decodeCanonicalBase64Bytes(
        encoded,
        1,
        encoded.length - 1,
      )!;
      encoded.fillRange(0, encoded.length, 0xee);
      expect(result, data);
      expect(NativeClientRuntime.releaseOwnedExternalBytes(result), isTrue);
    },
    skip: nativeClientRuntimeSkipReason(),
  );

  test('borrowed TypedData encoding owns output and respects offset views', () {
    final runtime = NativeClientRuntime.instance();
    for (final length in [0, 1, 2, 3, 31, 32, 33, 65537]) {
      final backing = Uint8List.fromList(
        List.generate(length + 7, (i) => (i * 37 + 11) & 255),
      );
      final input = Uint8List.sublistView(backing, 3, length + 3);
      final expected = ascii.encode(base64.encode(input));
      final encoded = runtime.tryEncodeCanonicalBase64TransportBytes(
        input.asUnmodifiableView(),
        prefix: 58,
        suffix: 3,
      );
      final bindings = CtFfiBindings(
        ffi.DynamicLibrary.open(runtime.libraryPath),
      );
      if (bindings.ctBase64EncodeVmBytes != null &&
          ffi.DynamicLibrary.process().providesSymbol(
            'Dart_TypedDataAcquireData',
          )) {
        expect(encoded, isNotNull);
      }
      if (encoded == null) {
        final fallback = runtime.encodeCanonicalBase64Bytes(input)!;
        expect(fallback, expected);
        expect(
          NativeClientRuntime.releaseOwnedExternalBytes(fallback),
          length != 0,
        );
        continue;
      }
      expect(encoded.start, 58);
      expect(encoded.end, 58 + expected.length);
      backing.fillRange(0, backing.length, 0xee);
      expect(encoded.bytes.sublist(encoded.start, encoded.end), expected);
      expect(encoded.bytes.sublist(0, 58), List.filled(58, 0));
      expect(encoded.bytes.sublist(encoded.end), [0, 0, 0]);
      encoded.bytes[0] = 123;
      expect(backing.first, 0xee);
      expect(
        NativeClientRuntime.releaseOwnedExternalBytes(encoded.bytes),
        isTrue,
      );
    }
    expect(
      () => runtime.tryEncodeCanonicalBase64TransportBytes(
        Uint8List(1),
        prefix: 4097,
      ),
      throwsRangeError,
    );
  }, skip: nativeClientRuntimeSkipReason());

  test('private WebSocket envelopes are aligned, exact and consumed once', () {
    final serializer = json_serializer.Serializer();
    installNativeCanonicalBase64Codecs(
      serializer,
      reserveWebSocketEnvelope: true,
    );
    final source = Uint8List.fromList(
      List.generate(65537, (i) => (i * 37) & 255),
    );
    final expectedSource = Uint8List.fromList(source);
    for (final procedure in [
      'a',
      'app.binary',
      'x' * 31,
      'x' * 4000,
      'x' * 4100,
    ]) {
      final message = Call(42, procedure, arguments: [source]);
      final expected = utf8.encode(serializer.serializeToString(message));
      final fragments = serializer.serializeFragments(message)!;
      final owned = takeNativeCanonicalBase64Frame(fragments);
      if (owned == null) {
        expect(fragments.expand((p) => p).toList(), expected);
      } else {
        expect(owned.bytes, expected);
        expect(owned.bytes.offsetInBytes % 16, 0);
        expect(
          () => Int32x4List.view(
            owned.bytes.buffer,
            owned.bytes.offsetInBytes,
            owned.bytes.length ~/ 16,
          ),
          returnsNormally,
        );
        expect(owned.copiedBytes, fragments[0].length + fragments[2].length);
        expect(takeNativeCanonicalBase64Frame(fragments), isNull);
        // The SDK masks these private bytes in place; a later encode must be independent.
        owned.bytes[owned.bytes.length ~/ 2] ^= 255;
        final next = serializer.serializeFragments(message)!;
        final nextOwned = takeNativeCanonicalBase64Frame(next)!;
        expect(nextOwned.bytes, expected);
      }
      expect(source, expectedSource);
    }
  }, skip: nativeClientRuntimeSkipReason());

  test('WebSocket acceleration preserves an explicit application encoder', () {
    var calls = 0;
    final serializer = json_serializer.Serializer(
      canonicalBase64ByteEncoder: (bytes) {
        calls++;
        return Uint8List.fromList(ascii.encode(base64.encode(bytes)));
      },
    );
    installNativeCanonicalBase64Codecs(
      serializer,
      reserveWebSocketEnvelope: true,
    );
    final fragments = serializer.serializeFragments(
      Call(42, 'app.binary', arguments: [Uint8List(65537)]),
    )!;
    expect(calls, 1);
    expect(takeNativeCanonicalBase64Frame(fragments), isNull);
    expect(
      utf8.decode(fragments.expand((p) => p).toList()),
      serializer.serializeToString(
        Call(42, 'app.binary', arguments: [Uint8List(65537)]),
      ),
    );
  });

  test('public VM String API decodes synchronously when available', () {
    final runtime = NativeClientRuntime.instance();
    final bindings = CtFfiBindings(
      ffi.DynamicLibrary.open(runtime.libraryPath),
    );
    final decode = bindings.ctBase64DecodeVmString;
    final vm = ffi.DynamicLibrary.process();
    ffi.Pointer<ffi.NativeFunction<DartApiStringToUtf8Native>>? convert;
    ffi.Pointer<ffi.NativeFunction<DartApiIsErrorNative>>? isError;
    try {
      convert = vm.lookup<ffi.NativeFunction<DartApiStringToUtf8Native>>(
        'Dart_StringToUTF8',
      );
      isError = vm.lookup<ffi.NativeFunction<DartApiIsErrorNative>>(
        'Dart_IsError',
      );
    } on ArgumentError {
      // Some embedders expose no public String API; the scalar path is required.
    }
    if (decode == null || convert == null || isError == null) {
      final decoded = runtime.decodeCanonicalBase64String('AQID', 0, 4)!;
      expect(decoded, [1, 2, 3]);
      expect(NativeClientRuntime.releaseOwnedExternalBytes(decoded), isTrue);
      return;
    }
    for (final (input, start, end, expected) in [
      ('prefix:AQID:suffix', 7, 11, NativeTransportErrorCode.success),
      ('\u0000:AQID', 2, 6, NativeTransportErrorCode.success),
      ('é:AQID', 2, 6, NativeTransportErrorCode.unsupported),
    ]) {
      final output = calloc<CtExternalByteBuffer>();
      try {
        expect(
          decode(input, start, end, input.length, convert, isError, output),
          expected,
        );
        if (expected == NativeTransportErrorCode.success) {
          expect(output.ref.owner, isNot(ffi.nullptr));
          expect(output.ref.ptr.asTypedList(output.ref.len), [1, 2, 3]);
        } else {
          expect(output.ref.owner, ffi.nullptr);
          expect(output.ref.ptr, ffi.nullptr);
          expect(output.ref.len, 0);
        }
      } finally {
        if (output.ref.owner != ffi.nullptr) {
          bindings.ctExternalByteBufferFree(output.ref.owner);
        }
        calloc.free(output);
      }
    }
  });

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
