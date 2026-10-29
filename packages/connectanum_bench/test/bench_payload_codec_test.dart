@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:connectanum_bench/src/bench_payload/codec.dart';
import 'package:connectanum_client/native_buffers.dart';
import 'package:connectanum_core/connectanum_core.dart';
import 'package:connectanum_core/src/serializer/owned_copy_metrics.dart';
import 'package:connectanum_core/cbor_serializer.dart' as cbor;
import 'package:connectanum_core/msgpack_serializer.dart' as msgpack;
import 'package:test/test.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:connectanum_bench/src/bench_payload/generated/workload_payload_connectanum.bench_generated.dart'
    as schema;

import 'support/native_library.dart';

void main() {
  final nativeLibrary = nativeBenchTestLibrary();
  test(
    'body preserves its arithmetic byte sequence for every seed and tail',
    () {
      for (var iteration = 0; iteration < 256; iteration++) {
        for (final length in [
          ...List.generate(18, (index) => index),
          23,
          24,
          25,
          31,
          32,
          33,
          255,
          256,
          257,
          4097,
        ]) {
          final bytes = BenchPayloadCodec.body(
            worker: 0,
            iteration: iteration,
            length: length,
          );
          expect(
            bytes,
            orderedEquals(
              List.generate(
                length,
                (index) => (iteration * 29 + index * 31) & 0xff,
              ),
            ),
            reason: 'iteration=$iteration length=$length',
          );
          expect(bytes.offsetInBytes, 0);
          expect(bytes.buffer.lengthInBytes, length);
        }
      }
    },
  );

  test(
    'large bodies preserve high identities and independent mutable storage',
    () {
      for (final worker in [0, 7, 0xffffffff]) {
        for (final iteration in [0, 11, 0xffffffff]) {
          for (final length in [65535, 65536, 65537]) {
            final bytes = BenchPayloadCodec.body(
              worker: worker,
              iteration: iteration,
              length: length,
            );
            expect(
              bytes,
              orderedEquals(
                List.generate(
                  length,
                  (index) => (worker * 17 + iteration * 29 + index * 31) & 0xff,
                ),
              ),
              reason: 'worker=$worker iteration=$iteration length=$length',
            );
            final other = BenchPayloadCodec.body(
              worker: worker,
              iteration: iteration,
              length: length,
            );
            bytes[0] ^= 0xff;
            expect(other[0], (worker * 17 + iteration * 29) & 0xff);
          }
        }
      }
    },
  );

  test('managed typed fixture observes its byte-vector input copy', () {
    OwnedCopyMetrics.enable();
    final before = OwnedCopyMetrics.snapshot()!;
    final bytes = BenchPayloadCodec.encodeDart(
      worker: 7,
      iteration: 11,
      bodyBytes: 65536,
    );
    final after = OwnedCopyMetrics.snapshot()!;
    expect(
      after['flatbuffer_vector_copy_bytes']! -
          before['flatbuffer_vector_copy_bytes']!,
      65536,
    );
    expect(
      after['flatbuffer_growth_copy_bytes']! -
          before['flatbuffer_growth_copy_bytes']!,
      0,
    );
    BenchPayloadCodec.verify(
      bytes: bytes,
      worker: 7,
      iteration: 11,
      bodyBytes: 65536,
    );
  });

  test(
    'fragmented Dart fixture borrows its body and counts only its prefix',
    () {
      OwnedCopyMetrics.enable();
      final before = OwnedCopyMetrics.snapshot()!;
      final source = BenchPayloadCodec.encodeDartParts(
        worker: 7,
        iteration: 11,
        bodyBytes: 65536,
      );
      final after = OwnedCopyMetrics.snapshot()!;
      expect(source.fragments[1].length, 65536);
      expect(source.fragments[1].offsetInBytes, 0);
      expect(source.fragments[1].buffer.lengthInBytes, 65536);
      expect(
        after['flatbuffer_vector_copy_bytes']! -
            before['flatbuffer_vector_copy_bytes']!,
        0,
      );
      expect(
        after['coalescing_copy_bytes']! - before['coalescing_copy_bytes']!,
        0,
      );
      expect(
        after['clone_copy_bytes']! - before['clone_copy_bytes']!,
        source.fragments.first.length,
      );
      BenchPayloadCodec.verify(
        bytes: source.bytes,
        worker: 7,
        iteration: 11,
        bodyBytes: 65536,
      );
    },
  );

  test(
    'Dart FlatBuffers fixture fills its backing array with unchanged wire bytes',
    () {
      for (final size in [0, 1, 2, 3, 4, 5, 7, 8, 9, 16, 65535, 65536]) {
        for (final worker in [0, 1, 0xffffffff]) {
          for (final iteration in [0, 1, 0xffffffff]) {
            final expectedBuilder = fb.Builder(
              initialSize: (size + 128 + 7) & ~7,
              deduplicateTables: false,
            );
            expectedBuilder.finish(
              schema.WorkloadPayloadObjectBuilder(
                worker: worker,
                iteration: iteration,
                body: BenchPayloadCodec.body(
                  worker: worker,
                  iteration: iteration,
                  length: size,
                ),
              ).finish(expectedBuilder),
              'CBEN',
            );
            final bytes = BenchPayloadCodec.encodeDart(
              worker: worker,
              iteration: iteration,
              bodyBytes: size,
            );
            expect(bytes, orderedEquals(expectedBuilder.buffer));
            expect(
              bytes.offsetInBytes,
              0,
              reason: 'body=$size worker=$worker iteration=$iteration',
            );
            expect(bytes.buffer.lengthInBytes, bytes.length);
          }
        }
      }
    },
  );

  for (final codec in [
    ('cbor', cbor.Serializer()),
    ('msgpack', msgpack.Serializer()),
  ]) {
    for (final bodyBytes in [0, 23, 24, 255, 256, 65535, 65536]) {
      test(
        'native ${codec.$1} PPT matches regular bytes at body length $bodyBytes',
        () {
          final allocator = NativeBufferAllocator.instance(
            libraryPath: nativeLibrary,
          );
          for (final worker in [
            0,
            23,
            24,
            127,
            128,
            255,
            256,
            65535,
            65536,
            0xffffffff,
          ]) {
            final iteration = 0xffffffff - worker;
            final expected = codec.$2.serializePPT(
              PPTPayload(
                arguments: [
                  BenchPayloadCodec.dynamicValue(
                    worker: worker,
                    iteration: iteration,
                    bodyBytes: bodyBytes,
                  ),
                ],
              ),
            );
            final native = BenchPayloadCodec.encodeNativePpt(
              allocator,
              serializer: codec.$1,
              worker: worker,
              iteration: iteration,
              bodyBytes: bodyBytes,
            );
            late Uint8List bytes;
            try {
              bytes = native.bytes;
              expect(bytes, expected);
              expect(native.inputCopiedBytes, 0);
              expect(native.growthCopiedBytes, 0);
              final decoded = codec.$2.deserializePPT(bytes)!;
              expect(decoded.arguments, hasLength(1));
              expect(decoded.argumentsKeywords, isNull);
              BenchPayloadCodec.verifyDynamic(
                value: decoded.arguments!.single,
                worker: worker,
                iteration: iteration,
                bodyBytes: bodyBytes,
              );
            } finally {
              native.dispose();
            }
            // The exported SDK view retains the frozen allocation independently.
            expect(bytes, expected);
          }
        },
        skip: nativeLibrary == null
            ? 'Native transport artifact unavailable'
            : false,
      );
    }

    test(
      'native ${codec.$1} PPT rejects invalid application bounds',
      () {
        final allocator = NativeBufferAllocator.instance(
          libraryPath: nativeLibrary,
        );
        for (final input in [
          (-1, 0, 0),
          (0x100000000, 0, 0),
          (0, -1, 0),
          (0, 0x100000000, 0),
          (0, 0, -1),
          (0, 0, 64 * 1024 * 1024 + 1),
        ]) {
          expect(
            () => BenchPayloadCodec.encodeNativePpt(
              allocator,
              serializer: codec.$1,
              worker: input.$1,
              iteration: input.$2,
              bodyBytes: input.$3,
            ),
            throwsRangeError,
          );
        }
      },
      skip: nativeLibrary == null
          ? 'Native transport artifact unavailable'
          : false,
    );
  }

  test(
    'native dynamic PPT rejects unsupported serializers',
    () {
      final allocator = NativeBufferAllocator.instance(
        libraryPath: nativeLibrary,
      );
      for (final serializer in ['flatbuffers', 'json', 'CBOR', '']) {
        expect(
          () => BenchPayloadCodec.encodeNativePpt(
            allocator,
            serializer: serializer,
            worker: 0,
            iteration: 0,
            bodyBytes: 0,
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.name,
              'name',
              'serializer',
            ),
          ),
        );
      }
    },
    skip: nativeLibrary == null
        ? 'Native transport artifact unavailable'
        : false,
  );

  for (final bodyBytes in [0, 1, 3, 7, 8, 257, 1024, 65535, 65536, 65537]) {
    test(
      'default native allocation avoids growth for $bodyBytes body bytes',
      () {
        final native = BenchPayloadCodec.encodeNative(
          NativeBufferAllocator.instance(libraryPath: nativeLibrary),
          worker: 7,
          iteration: 19,
          bodyBytes: bodyBytes,
        );
        addTearDown(native.dispose);
        expect(native.growthCopiedBytes, 0);
        expect(native.inputCopiedBytes, 0);
        expect(
          native.bytes,
          BenchPayloadCodec.encodeDart(
            worker: 7,
            iteration: 19,
            bodyBytes: bodyBytes,
          ),
        );
      },
      skip: nativeLibrary == null
          ? 'Native transport artifact unavailable'
          : false,
    );
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
        expect(native.inputCopiedBytes, 0);
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
    expect(() => decodedBody[0] = 0, throwsUnsupportedError);
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

  test(
    'native FlatBuffers validates bounds with an explicit initial size',
    () {
      final allocator = NativeBufferAllocator.instance(
        libraryPath: nativeLibrary,
      );
      for (final input in [
        (-1, 0, 0),
        (0x100000000, 0, 0),
        (0, -1, 0),
        (0, 0x100000000, 0),
        (0, 0, -1),
        (0, 0, 64 * 1024 * 1024 + 1),
      ]) {
        expect(
          () => BenchPayloadCodec.encodeNative(
            allocator,
            worker: input.$1,
            iteration: input.$2,
            bodyBytes: input.$3,
            initialSize: 8,
          ),
          throwsRangeError,
        );
      }
    },
    skip: nativeLibrary == null
        ? 'Native transport artifact unavailable'
        : false,
  );

  test(
    'native generation preserves maximum identity and every boundary byte',
    () {
      final allocator = NativeBufferAllocator.instance(
        libraryPath: nativeLibrary,
      );
      for (final size in [0, 1, 7, 8, 257, 65535, 65536, 65537]) {
        for (final identity in [(0, 0), (1, 1), (0xffffffff, 0xffffffff)]) {
          final owner = BenchPayloadCodec.encodeNative(
            allocator,
            worker: identity.$1,
            iteration: identity.$2,
            bodyBytes: size,
          );
          try {
            expect(
              owner.bytes,
              BenchPayloadCodec.encodeDart(
                worker: identity.$1,
                iteration: identity.$2,
                bodyBytes: size,
              ),
            );
            expect(owner.inputCopiedBytes, 0);
            expect(owner.growthCopiedBytes, 0);
          } finally {
            owner.dispose();
          }
        }
      }
    },
    skip: nativeLibrary == null
        ? 'Native transport artifact unavailable'
        : false,
  );

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

  test('checks each FlatBuffers body byte in aligned word groups', () {
    const worker = 7;
    const iteration = 19;
    const bodyBytes = 15;
    final bytes = BenchPayloadCodec.encodeDart(
      worker: worker,
      iteration: iteration,
      bodyBytes: bodyBytes,
    );
    final bodyOffset = _findSubsequence(
      bytes,
      BenchPayloadCodec.body(
        worker: worker,
        iteration: iteration,
        length: bodyBytes,
      ),
    );

    for (var offset = 0; offset < bodyBytes; offset += 1) {
      final corrupted = Uint8List.fromList(bytes)
        ..[bodyOffset + offset] ^= 0xff;
      expect(
        () => BenchPayloadCodec.verify(
          bytes: corrupted,
          worker: worker,
          iteration: iteration,
          bodyBytes: bodyBytes,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('byte $offset'),
          ),
        ),
      );
    }
  });

  test('checks every byte of an aligned read-only subview with guards', () {
    const worker = 31;
    const iteration = 47;
    const bodyBytes = 19;
    const prefixBytes = 4;
    final expected = BenchPayloadCodec.body(
      worker: worker,
      iteration: iteration,
      length: bodyBytes,
    );
    // A matching first word before the view catches readers that accidentally
    // start at the buffer origin and skip the view's first corrupted word.
    final backing = Uint8List(bodyBytes + 8)
      ..setRange(0, prefixBytes, expected)
      ..setRange(prefixBytes, prefixBytes + bodyBytes, expected)
      ..setRange(prefixBytes + bodyBytes, bodyBytes + 8, expected);
    final view = Uint8List.sublistView(
      backing,
      prefixBytes,
      prefixBytes + bodyBytes,
    ).asUnmodifiableView();
    final value = <String, Object?>{
      'worker': worker,
      'iteration': iteration,
      'body': view,
    };
    BenchPayloadCodec.verifyDynamic(
      value: value,
      worker: worker,
      iteration: iteration,
      bodyBytes: bodyBytes,
    );
    for (var offset = 0; offset < bodyBytes; offset += 1) {
      backing[prefixBytes + offset] ^= 0xff;
      expect(
        () => BenchPayloadCodec.verifyDynamic(
          value: value,
          worker: worker,
          iteration: iteration,
          bodyBytes: bodyBytes,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('byte $offset'),
          ),
        ),
      );
      backing[prefixBytes + offset] ^= 0xff;
    }
    expect(view, orderedEquals(expected));
    expect(
      backing.take(prefixBytes),
      orderedEquals(expected.take(prefixBytes)),
    );
    expect(
      backing.skip(prefixBytes + bodyBytes),
      orderedEquals(expected.take(4)),
    );
  });

  test('checks unaligned read-only typed bodies without copying', () {
    const worker = 31;
    const iteration = 47;
    const bodyBytes = 65539;
    final expected = BenchPayloadCodec.body(
      worker: worker,
      iteration: iteration,
      length: bodyBytes,
    );
    final backing = Uint8List(bodyBytes + 2)
      ..setRange(1, bodyBytes + 1, expected);
    final view = Uint8List.sublistView(
      backing,
      1,
      bodyBytes + 1,
    ).asUnmodifiableView();
    final value = <String, Object?>{
      'worker': worker,
      'iteration': iteration,
      'body': view,
    };

    BenchPayloadCodec.verifyDynamic(
      value: value,
      worker: worker,
      iteration: iteration,
      bodyBytes: bodyBytes,
    );
    BenchPayloadCodec.verifyDynamic(
      value: {...value, 'body': expected.toList()},
      worker: worker,
      iteration: iteration,
      bodyBytes: bodyBytes,
    );
    expect(() => view[0] = 0, throwsUnsupportedError);

    const corruptedOffset = 32770;
    backing[corruptedOffset + 1] ^= 0xff;
    expect(
      () => BenchPayloadCodec.verifyDynamic(
        value: value,
        worker: worker,
        iteration: iteration,
        bodyBytes: bodyBytes,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('byte $corruptedOffset'),
        ),
      ),
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
