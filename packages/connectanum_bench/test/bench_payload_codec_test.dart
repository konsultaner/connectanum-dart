@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:connectanum_bench/src/bench_payload/codec.dart';
import 'package:connectanum_client/native_buffers.dart';
import 'package:test/test.dart';

import 'support/native_library.dart';

void main() {
  final nativeLibrary = nativeBenchTestLibrary();

  for (final bodyBytes in [0, 1, 1024, 64 * 1024]) {
    test(
      'Dart and native FlatBuffers match for $bodyBytes body bytes',
      () {
        final expectedWorker = 7;
        final expectedIteration = 19;
        final dartBytes = BenchPayloadCodec.encodeDart(
          worker: expectedWorker,
          iteration: expectedIteration,
          bodyBytes: bodyBytes,
        );
        final native = BenchPayloadCodec.encodeNative(
          NativeBufferAllocator.instance(libraryPath: nativeLibrary),
          worker: expectedWorker,
          iteration: expectedIteration,
          bodyBytes: bodyBytes,
          initialSize: 32,
        );
        addTearDown(native.dispose);

        expect(native.bytes, dartBytes);
        expect(native.inputCopiedBytes, bodyBytes);
        BenchPayloadCodec.verify(
          bytes: dartBytes,
          worker: expectedWorker,
          iteration: expectedIteration,
          bodyBytes: bodyBytes,
        );
        BenchPayloadCodec.verify(
          bytes: native.bytes,
          worker: expectedWorker,
          iteration: expectedIteration,
          bodyBytes: bodyBytes,
        );
      },
      skip: nativeLibrary == null
          ? 'Native transport artifact unavailable'
          : false,
    );
  }

  test('rejects worker, iteration, body and schema mismatches', () {
    final bytes = BenchPayloadCodec.encodeDart(
      worker: 2,
      iteration: 3,
      bodyBytes: 16,
    );
    expect(
      () => BenchPayloadCodec.verify(
        bytes: bytes,
        worker: 1,
        iteration: 3,
        bodyBytes: 16,
      ),
      throwsFormatException,
    );
    expect(
      () => BenchPayloadCodec.verify(
        bytes: bytes,
        worker: 2,
        iteration: 4,
        bodyBytes: 16,
      ),
      throwsFormatException,
    );
    expect(
      () => BenchPayloadCodec.verify(
        bytes: bytes,
        worker: 2,
        iteration: 3,
        bodyBytes: 17,
      ),
      throwsFormatException,
    );
    final decodedBody = BenchPayloadCodec.decode(bytes).body!;
    expect(() => decodedBody[0] = 0, throwsStateError);
    final bodyOffset = _findSubsequence(
      bytes,
      BenchPayloadCodec.body(worker: 2, iteration: 3, length: 16),
    );
    expect(bodyOffset, greaterThanOrEqualTo(8));
    final corruptBody = Uint8List.fromList(bytes)..[bodyOffset] ^= 0xff;
    expect(
      () => BenchPayloadCodec.verify(
        bytes: corruptBody,
        worker: 2,
        iteration: 3,
        bodyBytes: 16,
      ),
      throwsFormatException,
    );
    final invalid = bytes.toList()..[4] ^= 0xff;
    expect(() => BenchPayloadCodec.decode(invalid), throwsFormatException);
    expect(
      () => BenchPayloadCodec.decode(bytes.sublist(0, 7)),
      throwsFormatException,
    );
    expect(
      () => BenchPayloadCodec.decode(bytes.sublist(0, 8)),
      throwsRangeError,
    );
  });

  test('preserves the largest application identity fields', () {
    final bytes = BenchPayloadCodec.encodeDart(
      worker: 0xffffffff,
      iteration: 0xffffffff,
      bodyBytes: 0,
    );
    final decoded = BenchPayloadCodec.decode(bytes);
    expect(decoded.worker, 0xffffffff);
    expect(decoded.iteration, 0xffffffff);
  });

  test(
    'identity matching ignores malformed FlatBuffers instead of throwing',
    () {
      final valid = BenchPayloadCodec.encodeDart(
        worker: 2,
        iteration: 3,
        bodyBytes: 16,
      );
      for (final invalid in [
        valid.sublist(0, 7),
        valid.sublist(0, 8),
        Uint8List.fromList(valid)..[4] ^= 0xff,
      ]) {
        expect(
          BenchPayloadCodec.matchesIdentity(
            invalid,
            serializer: 'flatbuffers',
            worker: 2,
            iteration: 3,
          ),
          isFalse,
        );
      }
      expect(
        BenchPayloadCodec.matchesIdentity(
          valid,
          serializer: 'flatbuffers',
          worker: 2,
          iteration: 3,
        ),
        isTrue,
      );
    },
  );

  test('validates dynamic CBOR and MessagePack record values', () {
    final value = BenchPayloadCodec.dynamicValue(
      worker: 7,
      iteration: 19,
      bodyBytes: 32,
    );
    BenchPayloadCodec.verifyDynamic(
      value: value,
      worker: 7,
      iteration: 19,
      bodyBytes: 32,
    );
    expect(
      BenchPayloadCodec.matchesIdentity(
        value,
        serializer: 'cbor',
        worker: 7,
        iteration: 19,
      ),
      isTrue,
    );
    expect(
      () => BenchPayloadCodec.verifyDynamic(
        value: value,
        worker: 7,
        iteration: 20,
        bodyBytes: 32,
      ),
      throwsFormatException,
    );
    (value['body'] as Uint8List)[0] ^= 0xff;
    expect(
      () => BenchPayloadCodec.verifyDynamic(
        value: value,
        worker: 7,
        iteration: 19,
        bodyBytes: 32,
      ),
      throwsFormatException,
    );
  });
}

int _findSubsequence(List<int> bytes, List<int> sequence) {
  for (var start = 8; start <= bytes.length - sequence.length; start += 1) {
    var matches = true;
    for (var offset = 0; offset < sequence.length; offset += 1) {
      if (bytes[start + offset] != sequence[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return start;
  }
  return -1;
}
