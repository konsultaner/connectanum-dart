@TestOn('vm')
library;

import 'dart:collection';
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/native_buffers.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/generated/wamp_wamp.proto_generated.dart'
    as wire;
import 'package:connectanum_core/src/serializer/flatbuffers/message_writer.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/validation.dart';
import 'package:connectanum_core/src/serializer/flatbuffers/wire_writer.dart';
import 'package:flat_buffers/flat_buffers.dart' as fb;
import 'package:ffi/ffi.dart' as ffi_alloc;
import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';
import 'package:connectanum_core/src/serializer/owned_copy_metrics.dart';

void main() {
  late NativeBufferAllocator allocator;
  setUpAll(() {
    allocator = NativeBufferAllocator.instance();
  });

  group('guarded in-place initialization', () {
    for (final vector in [false, true]) {
      NativeOwnedBuffer initialize(
        int length,
        void Function(NativeWritableBytes) fill,
      ) {
        if (vector) {
          final builder = allocator.flatBuffers(initialSize: 8);
          try {
            builder.finish(builder.writeByteVector(length, fill), 'BYTS');
            return builder.freeze();
          } finally {
            builder.dispose();
          }
        }
        final builder = allocator.allocate(length);
        try {
          builder.writeByteRange(0, length, fill);
          return builder.freeze();
        } finally {
          builder.dispose();
        }
      }

      Uint8List contents(NativeOwnedBuffer owner) {
        final bytes = owner.bytes;
        if (!vector) return bytes;
        final data = ByteData.sublistView(bytes);
        final root = data.getUint32(0, Endian.little);
        final length = data.getUint32(root, Endian.little);
        return Uint8List.sublistView(bytes, root + 4, root + 4 + length);
      }

      for (final length in [0, 1, 3, 4, 7, 8, 9, 257, 65535, 65536, 65537]) {
        test('scalar generation vector=$vector length=$length', () {
          final expected = Uint8List.fromList(
            List.generate(length, (index) => (index * 31) & 255),
          );
          final owner = initialize(length, (bytes) {
            final words = bytes.uint32Words(count: length >> 2);
            final input = ByteData.sublistView(expected);
            for (var i = 0; i < words.length; i++) {
              words[i] = input.getUint32(i * 4, Endian.little);
            }
            for (var i = words.length * 4; i < length; i++) {
              bytes.setUint8(i, expected[i]);
            }
          });
          addTearDown(owner.dispose);
          expect(contents(owner), expected);
          expect(owner.inputCopiedBytes, 0);
          if (vector) {
            final sdk = fb.Builder(initialSize: 8);
            sdk.finish(sdk.writeListUint8(expected), 'BYTS');
            expect(owner.bytes, sdk.buffer);
          }
        });
      }

      test('scoped views, byte order and copy accounting vector=$vector', () {
        OwnedCopyMetrics.enable();
        final before = OwnedCopyMetrics.snapshot()!;
        late NativeWritableBytes escaped;
        late NativeUint32Writer first;
        late NativeUint32Writer second;
        late NativeUint32Writer third;
        final owner = initialize(25, (bytes) {
          escaped = bytes;
          first = bytes.uint32Words(count: 2);
          first[0] = 0x01020304;
          first[1] = 0x05060708;
          bytes.setUint8(8, 0xee);
          second = bytes.uint32Words(offset: 9, count: 1, endian: Endian.big);
          second[0] = 0x11223344;
          third = bytes.uint32Words(offset: 13, count: 2);
          // Keep the third registered view open but initialize using scalars.
          bytes.setUint64(13, 0x0102030405060708, Endian.big);
          bytes.writeBytes(21, [9, 8, 7]);
        });
        final expected = ByteData(25)
          ..setUint32(0, 0x01020304, Endian.little)
          ..setUint32(4, 0x05060708, Endian.little)
          ..setUint8(8, 0xee)
          ..setUint32(9, 0x11223344, Endian.big)
          ..setUint64(13, 0x0102030405060708, Endian.big);
        expected.buffer.asUint8List().setRange(21, 24, [9, 8, 7]);
        try {
          expect(contents(owner), expected.buffer.asUint8List());
          expect(owner.inputCopiedBytes, 3);
          final after = OwnedCopyMetrics.snapshot()!;
          final key = vector
              ? 'flatbuffer_vector_copy_bytes'
              : 'clone_copy_bytes';
          expect(after[key]! - before[key]!, 3);
        } finally {
          owner.dispose();
        }
        expect(() => escaped.setUint8(0, 1), throwsStateError);
        expect(() => escaped.setUint32(0, 1), throwsStateError);
        expect(() => escaped.setUint64(0, 1), throwsStateError);
        expect(() => escaped.writeBytes(0, [1]), throwsStateError);
        expect(() => escaped.uint32Words(count: 1), throwsStateError);
        for (final words in [first, second, third]) {
          expect(() => words[0] = 1, throwsStateError);
        }
      });

      test('word bounds precede offset multiplication vector=$vector', () {
        final owner = initialize(13, (bytes) {
          for (final offset in [0, 1]) {
            final words = bytes.uint32Words(offset: offset, count: 2);
            for (final index in [-1, 2, 1 << 62]) {
              expect(() => words[index] = 1, throwsRangeError);
            }
          }
          final empty = bytes.uint32Words(offset: 13, count: 0);
          expect(() => empty[0] = 1, throwsRangeError);
          expect(() => bytes.uint32Words(count: -1), throwsRangeError);
          expect(() => bytes.uint32Words(count: 1 << 62), throwsRangeError);
          expect(
            () => bytes.uint32Words(offset: 14, count: 0),
            throwsRangeError,
          );
        });
        addTearDown(owner.dispose);
        expect(contents(owner), Uint8List(13));
      });

      test(
        'failed source copy cannot publish partial bytes vector=$vector',
        () {
          OwnedCopyMetrics.enable();
          final before = OwnedCopyMetrics.snapshot()!;
          final original = StateError('source failed after one byte');
          var reads = 0;
          expect(
            () => initialize(4, (bytes) {
              expect(
                () => bytes.writeBytes(
                  0,
                  _ReentrantBytes(() {
                    if (++reads == 2) throw original;
                  }),
                ),
                throwsA(same(original)),
              );
              expect(() => bytes.setUint8(0, 1), throwsStateError);
            }),
            throwsStateError,
          );
          expect(reads, 2);
          final after = OwnedCopyMetrics.snapshot()!;
          expect(
            after['failed_copy_operations']! -
                before['failed_copy_operations']!,
            1,
          );
        },
      );
    }

    test('reset clears old vector bytes and recovers a failed fill', () {
      final builder = allocator.flatBuffers(initialSize: 8);
      addTearDown(builder.dispose);
      late NativeUint32Writer escaped;
      final original = StateError('original fill failure');
      expect(
        () => builder.writeByteVector(32, (bytes) {
          escaped = bytes.uint32Words(count: 8);
          bytes.writeBytes(0, List.filled(32, 0x9a));
          throw original;
        }),
        throwsA(same(original)),
      );
      expect(() => escaped[0] = 1, throwsStateError);
      expect(() => builder.finish(4), throwsStateError);
      expect(builder.freeze, throwsStateError);
      expect(() => builder.writeByteVector(1, (_) {}), throwsStateError);
      builder.reset();
      final vector = builder.writeByteVector(8, (_) {});
      builder.finish(vector, 'BYTS');
      final owner = builder.freeze();
      addTearDown(owner.dispose);
      final sdk = fb.Builder(initialSize: 8);
      sdk.finish(sdk.writeListUint8(Uint8List(8)), 'BYTS');
      expect(owner.bytes, sdk.buffer);
      expect(owner.inputCopiedBytes, 32);
      expect(() => escaped[0] = 1, throwsStateError);
    });

    test('growth preserves zero initialization beside an earlier vector', () {
      final builder = allocator.flatBuffers(initialSize: 8);
      addTearDown(builder.dispose);
      final old = Uint8List(512)..fillRange(0, 512, 0x9a);
      builder.writeListUint8(old);
      late NativeUint32Writer escaped;
      builder.writeByteVector(4, (bytes) {
        escaped = bytes.uint32Words(count: 1)..[0] = 0x04030201;
      });
      final vector = builder.writeByteVector(2048, (bytes) {
        bytes.setUint8(0, 7);
      });
      expect(() => escaped[0] = 1, throwsStateError);
      builder.finish(vector, 'BYTS');
      final owner = builder.freeze();
      addTearDown(owner.dispose);
      final sdk = fb.Builder(initialSize: 8);
      sdk.writeListUint8(old);
      sdk.writeListUint8([1, 2, 3, 4]);
      final body = Uint8List(2048)..[0] = 7;
      sdk.finish(sdk.writeListUint8(body), 'BYTS');
      expect(owner.bytes, sdk.buffer);
      expect(owner.inputCopiedBytes, 512);
      expect(owner.growthCopiedBytes, greaterThan(0));
    });

    test('vector reservation rejects table state before callback', () {
      final builder = allocator.flatBuffers(initialSize: 8);
      addTearDown(builder.dispose);
      builder.startTable(1);
      var called = false;
      expect(
        () => builder.writeByteVector(4, (_) => called = true),
        throwsStateError,
      );
      expect(called, isFalse);
      builder.reset();
      builder.finish(builder.writeByteVector(0, (_) {}), 'BYTS');
      final owner = builder.freeze();
      addTearDown(owner.dispose);
    });

    test('callback blocks native builder mutation before publication', () {
      final builder = allocator.flatBuffers(initialSize: 8);
      addTearDown(builder.dispose);
      final vector = builder.writeByteVector(4, (bytes) {
        for (final attempt in <void Function()>[
          () => builder.putUint8(1),
          () => builder.startTable(1),
          () => builder.finish(4),
          builder.reset,
          builder.dispose,
          () => builder.freeze(),
          () => builder.buffer,
          () => builder.writeByteVector(4, (_) {}),
        ]) {
          expect(attempt, throwsStateError);
        }
        bytes.uint32Words(count: 1)[0] = 0x01020304;
      });
      builder.finish(vector, 'BYTS');
      final owner = builder.freeze();
      addTearDown(owner.dispose);
      expect(owner.inputCopiedBytes, 0);
    });

    test('failed fixed-size initialization cannot freeze or accept writes', () {
      final builder = allocator.allocate(8);
      addTearDown(builder.dispose);
      final original = StateError('fixed fill failure');
      expect(
        () => builder.writeByteRange(0, 8, (bytes) {
          expect(() => builder.setUint8(0, 1), throwsStateError);
          expect(builder.freeze, throwsStateError);
          expect(builder.dispose, throwsStateError);
          bytes.setUint32(0, 1);
          throw original;
        }),
        throwsA(same(original)),
      );
      expect(builder.freeze, throwsStateError);
      expect(() => builder.writeBytes(0, [1]), throwsStateError);
      expect(() => builder.writeByteRange(0, 8, (_) {}), throwsStateError);
    });

    test('fixed byte-range updates preserve untouched existing values', () {
      final builder = allocator.allocate(12);
      addTearDown(builder.dispose);
      builder.writeBytes(0, List.filled(12, 0x7b));
      builder.writeByteRange(3, 6, (bytes) {
        bytes.setUint8(1, 0x19);
      });
      final owner = builder.freeze();
      addTearDown(owner.dispose);
      final expected = Uint8List(12)..fillRange(0, 12, 0x7b);
      expected[4] = 0x19;
      expect(owner.bytes, expected);
      expect(owner.inputCopiedBytes, 12);
    });

    test('asynchronous fills close all writers before returning', () async {
      final builder = allocator.flatBuffers(initialSize: 8);
      addTearDown(builder.dispose);
      final resume = Completer<void>();
      late Future<void> pending;
      expect(
        () => builder.writeByteVector(4, (bytes) {
          final words = bytes.uint32Words(count: 1);
          return pending = () async {
            await resume.future;
            expect(() => words[0] = 1, throwsStateError);
            expect(() => bytes.setUint8(0, 1), throwsStateError);
          }();
        }),
        throwsArgumentError,
      );
      expect(builder.freeze, throwsStateError);
      builder.dispose();
      resume.complete();
      await pending;
    });

    test('void-typed asynchronous callback is rejected too', () async {
      final builder = allocator.allocate(4);
      addTearDown(builder.dispose);
      final resume = Completer<void>();
      final done = Completer<void>();
      // This intentionally passes an invalid async callback through a void type.
      // ignore: avoid_void_async
      void fill(NativeWritableBytes bytes) async {
        final words = bytes.uint32Words(count: 1);
        await resume.future;
        try {
          expect(() => words[0] = 1, throwsStateError);
        } finally {
          done.complete();
        }
      }

      expect(() => builder.writeByteRange(0, 4, fill), throwsArgumentError);
      expect(builder.freeze, throwsStateError);
      builder.dispose();
      resume.complete();
      await done.future;
    });

    test('scoped writers cannot cross an isolate port', () {
      final port = ReceivePort();
      addTearDown(port.close);
      final builder = allocator.allocate(4);
      addTearDown(builder.dispose);
      builder.writeByteRange(0, 4, (bytes) {
        final words = bytes.uint32Words(count: 1);
        expect(() => port.sendPort.send(bytes), throwsArgumentError);
        expect(() => port.sendPort.send(words), throwsArgumentError);
      });
    });
  });

  test(
    'typed word writes detach from native source and preserve copy ownership',
    () {
      OwnedCopyMetrics.enable();
      for (final length in [256, 257, 258, 259, 4096, 4097, 65536, 65537]) {
        for (final capacity in [8, length + 128]) {
          final bytes = Uint8List.fromList(
            List.generate(length, (i) => (i * 29) & 255),
          );
          final sourceBuilder = allocator.allocate(length);
          sourceBuilder.writeBytes(0, bytes);
          final source = sourceBuilder.freeze();
          final builder = allocator.flatBuffers(initialSize: capacity);
          try {
            final before = OwnedCopyMetrics.snapshot()!;
            final vector = builder.writeListUint8(
              source.bytes.asUnmodifiableView(),
            );
            source.dispose();
            builder.finish(vector, 'BYTS');
            final frozen = builder.freeze();
            try {
              final sdk = fb.Builder(initialSize: (capacity + 7) & ~7);
              sdk.finish(sdk.writeListUint8(bytes), 'BYTS');
              expect(frozen.bytes, sdk.buffer);
              expect(frozen.inputCopiedBytes, length);
              final after = OwnedCopyMetrics.snapshot()!;
              expect(
                after['flatbuffer_vector_copy_bytes']! -
                    before['flatbuffer_vector_copy_bytes']!,
                length,
              );
              expect(
                after['flatbuffer_growth_copy_bytes']! -
                    before['flatbuffer_growth_copy_bytes']!,
                builder.growthCopiedBytes,
              );
              expect(
                after['unmeasured_copy_operations'],
                before['unmeasured_copy_operations'],
              );
              expect(
                after['failed_copy_operations'],
                before['failed_copy_operations'],
              );
              expect(() => builder.writeListUint8(bytes), throwsStateError);
            } finally {
              frozen.dispose();
            }
          } finally {
            source.dispose();
            sourceBuilder.dispose();
            builder.dispose();
          }
          expect(() => builder.writeListUint8(bytes), throwsStateError);
        }
      }
    },
  );

  test('native message vectors contribute once through the shared writer', () {
    OwnedCopyMetrics.enable();
    final before = OwnedCopyMetrics.snapshot()!;
    final builder = allocator.flatBuffers(initialSize: 1024);
    try {
      final root = writeWampFlatBufferMessage(
        Call(
          7,
          'com.copy.echo',
          arguments: [
            Uint8List.fromList([1, 2, 3]),
          ],
        ),
        builder,
      );
      builder.finish(root);
      final frozen = builder.freeze();
      try {
        final after = OwnedCopyMetrics.snapshot()!;
        expect(
          after['flatbuffer_vector_copy_bytes']! -
              before['flatbuffer_vector_copy_bytes']!,
          frozen.inputCopiedBytes,
        );
        expect(frozen.inputCopiedBytes, greaterThan(0));
      } finally {
        frozen.dispose();
      }
    } finally {
      builder.dispose();
    }
  });

  test('native allocator growth is observed exactly once', () {
    OwnedCopyMetrics.enable();
    final before = OwnedCopyMetrics.snapshot()!;
    final builder = allocator.flatBuffers(initialSize: 8);
    try {
      builder.writeListUint8([1, 2, 3]);
      final root = builder.writeListUint8(List<int>.filled(257, 4));
      builder.finish(root);
      final expected = builder.growthCopiedBytes;
      expect(expected, greaterThan(0));
      final frozen = builder.freeze();
      try {
        expect(frozen.length, greaterThan(257));
        final after = OwnedCopyMetrics.snapshot()!;
        expect(
          after['flatbuffer_vector_copy_bytes']! -
              before['flatbuffer_vector_copy_bytes']!,
          260,
        );
        expect(
          after['flatbuffer_growth_copy_bytes']! -
              before['flatbuffer_growth_copy_bytes']!,
          expected,
        );
        expect(
          after['unmeasured_copy_operations'],
          before['unmeasured_copy_operations'],
        );
      } finally {
        frozen.dispose();
      }
    } finally {
      builder.dispose();
    }
  });

  for (final length in [10, 256 * 1024]) {
    test('SHA-256 bridge copies are observed for $length bytes', () {
      final runtime = NativeClientRuntime.instance();
      final payload = Uint8List(length)..[0] = 71;
      final expected = crypto.sha256.convert(payload).bytes;
      OwnedCopyMetrics.enable();
      final before = OwnedCopyMetrics.snapshot()!;
      final state = runtime.createSha256State();
      try {
        expect(runtime.updateSha256(state, payload), length);
        final digest = runtime.finalizeSha256State(state);
        expect(digest, expected);
        final after = OwnedCopyMetrics.snapshot()!;
        expect(
          after['clone_copy_bytes']! - before['clone_copy_bytes']!,
          length + 32,
        );
      } finally {
        runtime.releaseSha256State(state);
      }
    });
  }

  test('complete native ownership ABI is available', () {
    expect(
      allocator.isSupported,
      isTrue,
      reason: 'Tests require the owned-buffer native ABI',
    );
    expect(allocator.supportsOwnedE2eeEncryption, isTrue);
  });

  test('older native libraries reject the complete optional ABI', () {
    // process() sees ct_ffi symbols already loaded by build hooks. Use a
    // separate library handle with no Connectanum ownership entry points.
    final library = DynamicLibrary.open(
      Platform.isMacOS
          ? '/usr/lib/libSystem.B.dylib'
          : Platform.isWindows
          ? 'kernel32.dll'
          : 'libc.so.6',
    );
    final old = NativeBufferAllocator(library);
    expect(old.isSupported, isFalse);
    expect(() => old.allocate(0), throwsUnsupportedError);
    expect(old.flatBuffers, throwsUnsupportedError);
  });

  test(
    'version mismatch and foreign library reject before ownership transfer',
    () async {
      final source = await Isolate.resolvePackageUri(
        Uri.parse('package:connectanum_client/native_buffers.dart'),
      );
      final fixture = source!
          .resolve(
            '../test/transport/native/support/owned_buffer_abi_fixture.c',
          )
          .toFilePath();
      final directory = await Directory.systemTemp.createTemp(
        'connectanum-owned-abi-',
      );
      addTearDown(() => directory.delete(recursive: true));
      Future<NativeBufferAllocator> load(
        int version, {
        int? externalVersion,
        int? writeVersion,
        bool omitWriteFinalizer = false,
      }) async {
        final output =
            '${directory.path}/owned-$version-$externalVersion-$writeVersion-$omitWriteFinalizer.${Platform.isMacOS ? 'dylib' : 'so'}';
        final result = await Process.run('cc', [
          Platform.isMacOS ? '-dynamiclib' : '-shared',
          '-fPIC',
          '-DOWNED_BUFFER_VERSION=$version',
          if (externalVersion != null)
            '-DEXTERNAL_LEASE_VERSION=$externalVersion',
          if (writeVersion != null) '-DWRITE_RECEIPT_VERSION=$writeVersion',
          if (omitWriteFinalizer) '-DOMIT_WRITE_FINALIZER',
          '-o',
          output,
          fixture,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        return NativeBufferAllocator(DynamicLibrary.open(output));
      }

      final differentVersion = await load(2);
      expect(differentVersion.isSupported, isFalse);
      expect(() => differentVersion.allocate(8), throwsUnsupportedError);
      final foreign = await load(1);
      expect(foreign.isSupported, isTrue);
      expect(foreign.supportsWriteCompletion, isFalse);
      expect(foreign.supportsExternalTokens, isFalse);
      expect(foreign.supportsOwnedE2eeEncryption, isFalse);
      // Capability rejection must happen before reading even a non-null token.
      expect(
        () => foreign.adoptTrustedNativeToken(Pointer.fromAddress(1)),
        throwsUnsupportedError,
      );
      final wrongExternal = await load(1, externalVersion: 2);
      expect(wrongExternal.isSupported, isTrue);
      expect(wrongExternal.supportsExternalTokens, isFalse);
      expect(
        () => wrongExternal.adoptTrustedNativeToken(Pointer.fromAddress(1)),
        throwsUnsupportedError,
      );
      final buffer = allocator.allocate(8).freeze();
      expect(
        () => foreign.sendTracked(42, buffer, transfer: true),
        throwsUnsupportedError,
      );
      expect(buffer.isDisposed, isFalse);
      expect(
        () => foreign.send(42, buffer, transfer: true),
        throwsArgumentError,
      );
      expect(buffer.isDisposed, isFalse);
      expect(buffer.bytes, hasLength(8));
      buffer.dispose();

      final wrongWrite = await load(1, writeVersion: 2);
      expect(wrongWrite.isSupported, isTrue);
      expect(wrongWrite.supportsWriteCompletion, isFalse);
      final missingWrite = await load(
        1,
        writeVersion: 1,
        omitWriteFinalizer: true,
      );
      expect(missingWrite.supportsWriteCompletion, isFalse);
      await expectLater(missingWrite.drainWrites(42), throwsUnsupportedError);
      final writeOnly = await load(1, writeVersion: 1);
      expect(writeOnly.supportsWriteCompletion, isTrue);
      expect(writeOnly.supportsExternalTokens, isFalse);
      // Producer and receipt capabilities are independently versioned.
      await expectLater(
        writeOnly.drainWrites(42),
        throwsA(isA<NativeBufferException>()),
      );
    },
    skip: Platform.isWindows
        ? 'Native verification uses Unix C toolchains'
        : false,
  );

  test(
    'mutable, stale and null producer tokens reject without consumption',
    () {
      final library = DynamicLibrary.open(
        NativeClientRuntime.instance().libraryPath,
      );
      final allocate = library
          .lookupFunction<Int32 Function(Int32), int Function(int)>(
            'ct_owned_buffer_allocate',
          );
      final release = library
          .lookupFunction<Int32 Function(Int32), int Function(int)>(
            'ct_owned_buffer_release',
          );
      final identity = library
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'ct_external_buffer_store_identity',
          );
      final api = NativeBufferAllocator(library);
      expect(api.supportsExternalTokens, isTrue);
      expect(() => api.adoptTrustedNativeToken(nullptr), throwsArgumentError);
      final token = ffi_alloc.calloc<NativeBufferToken>();
      addTearDown(() => ffi_alloc.calloc.free(token));
      final id = allocate(8);
      expect(id, greaterThan(0));
      token.ref.handle = id;
      token.ref.identity = identity();
      expect(() => api.adoptTrustedNativeToken(token), throwsStateError);
      expect(token.ref.handle, id);
      expect(release(id), 0);
      expect(
        () => api.adoptTrustedNativeToken(token),
        throwsA(
          isA<NativeBufferException>().having((e) => e.code, 'code', -4),
        ),
      );
      expect(token.ref.handle, id);
    },
  );

  test(
    'native finalizers preserve derived views and release abandoned owners',
    () async {
      final source = await Isolate.resolvePackageUri(
        Uri.parse('package:connectanum_client/native_buffers.dart'),
      );
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          '--enable-vm-service=0',
          '--disable-service-auth-codes',
          'run',
          source!
              .resolve(
                '../test/transport/native/support/owned_buffer_gc_probe.dart',
              )
              .toFilePath(),
        ],
        environment: {
          'CONNECTANUM_NATIVE_LIB': NativeClientRuntime.instance().libraryPath,
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains(
          'owned-buffer-gc: derived view retained then released storage',
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'C producer leases survive derived views and release on the owner thread',
    () async {
      final source = await Isolate.resolvePackageUri(
        Uri.parse('package:connectanum_client/native_buffers.dart'),
      );
      final support = source!.resolve('../test/transport/native/support/');
      final directory = await Directory.systemTemp.createTemp(
        'connectanum-lease-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final output =
          '${directory.path}/actor.${Platform.isMacOS ? 'dylib' : 'so'}';
      final compiled = await Process.run('cc', [
        Platform.isMacOS ? '-dynamiclib' : '-shared',
        '-fPIC',
        '-pthread',
        '-Wall',
        '-Wextra',
        '-Werror',
        '-o',
        output,
        support.resolve('external_lease_actor_fixture.c').toFilePath(),
        if (!Platform.isMacOS) '-ldl',
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          '--enable-vm-service=0',
          '--disable-service-auth-codes',
          'run',
          support.resolve('external_lease_gc_probe.dart').toFilePath(),
          output,
        ],
        environment: {
          'CONNECTANUM_NATIVE_LIB': NativeClientRuntime.instance().libraryPath,
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains(
          'external-lease-gc: native owner thread released after derived view',
        ),
      );
    },
    skip: Platform.isWindows
        ? 'Native verification uses Unix C toolchains'
        : false,
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'C producer lease survives a delayed native write and releases on its owner thread',
    () async {
      final source = await Isolate.resolvePackageUri(
        Uri.parse('package:connectanum_client/native_buffers.dart'),
      );
      final support = source!.resolve('../test/transport/native/support/');
      final directory = await Directory.systemTemp.createTemp(
        'connectanum-lease-send-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final output =
          '${directory.path}/actor.${Platform.isMacOS ? 'dylib' : 'so'}';
      final compiled = await Process.run('cc', [
        Platform.isMacOS ? '-dynamiclib' : '-shared',
        '-fPIC',
        '-pthread',
        '-Wall',
        '-Wextra',
        '-Werror',
        '-o',
        output,
        support.resolve('external_lease_actor_fixture.c').toFilePath(),
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          '--enable-vm-service=0',
          '--disable-service-auth-codes',
          'run',
          support.resolve('external_lease_send_probe.dart').toFilePath(),
          output,
        ],
        environment: {
          'CONNECTANUM_NATIVE_LIB': NativeClientRuntime.instance().libraryPath,
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains(
          'external-lease-send: delayed native write preserved bytes and released once on owner thread',
        ),
      );
    },
    skip: Platform.isWindows
        ? 'Native verification uses Unix C toolchains'
        : false,
    timeout: const Timeout(Duration(seconds: 75)),
  );

  test(
    'collected write receipts return capacity without cancelling sends',
    () async {
      final source = await Isolate.resolvePackageUri(
        Uri.parse('package:connectanum_client/native_buffers.dart'),
      );
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          '--enable-vm-service=0',
          '--disable-service-auth-codes',
          'run',
          source!
              .resolve(
                '../test/transport/native/support/write_receipt_gc_probe.dart',
              )
              .toFilePath(),
        ],
        environment: {
          'CONNECTANUM_NATIVE_LIB': NativeClientRuntime.instance().libraryPath,
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains(
          'write-receipt-gc: collected observer returned capacity without cancelling frame',
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test('zero-filled native storage freezes a backward subrange', () {
    final builder = allocator.allocate(64);
    builder.setUint32(60, 0x04030201);
    final buffer = builder.freeze(offset: 56, length: 8);
    addTearDown(buffer.dispose);
    expect(buffer.bytes, [0, 0, 0, 0, 1, 2, 3, 4]);
    expect(buffer.growthCopiedBytes, 0);
    expect(buffer.inputCopiedBytes, 0);
    expect(() => builder.setUint8(0, 7), throwsStateError);
    expect(() => builder.freeze(), throwsStateError);
    builder.dispose();
    expect(buffer.bytes, hasLength(8));
  });

  test('invalid ranges preserve mutable ownership and explicit disposal', () {
    final builder = allocator.allocate(8);
    expect(() => builder.freeze(offset: 7, length: 2), throwsRangeError);
    builder.writeBytes(0, [1, 2, 3]);
    final buffer = builder.freeze();
    expect(buffer.inputCopiedBytes, 3);
    buffer.dispose();
    buffer.dispose();
    expect(() => buffer.bytes, throwsStateError);
    expect(() => builder.setUint32(0, 1), throwsStateError);
    final other = allocator.allocate(0);
    other.dispose();
    expect(() => other.freeze(), throwsStateError);
  });

  test('read-only exported subviews outlive disposed wrappers', () {
    final builder = allocator.allocate(8)..writeBytes(0, [1, 2, 3, 4]);
    final buffer = builder.freeze(length: 4);
    final retained = buffer.slice(1, 4);
    final root = buffer.bytes;
    final view = Uint8List.sublistView(root, 1, 3);
    buffer.dispose();
    retained.dispose();
    expect(view, [2, 3]);
    expect(() => root[0] = 9, throwsUnsupportedError);
    expect(() => view[0] = 9, throwsUnsupportedError);
    expect(() => root.buffer.asUint8List()[0] = 9, throwsUnsupportedError);
    expect(
      () => root.buffer.asByteData().setUint8(0, 9),
      throwsUnsupportedError,
    );
    expect(() => root.buffer.asInt8List()[0] = 9, throwsUnsupportedError);
    expect(root, [1, 2, 3, 4]);
  });

  test('empty buffers and slices retain valid ownership', () {
    final empty = allocator.allocate(0).freeze();
    final slice = empty.retain();
    empty.dispose();
    expect(slice.bytes, isEmpty);
    slice.dispose();
  });

  test('implicit freeze and slice ends preserve the remaining range', () {
    final buffer = (allocator.allocate(
      8,
    )..writeBytes(0, [0, 1, 2, 3, 4, 5, 6, 7])).freeze(offset: 4);
    final slice = buffer.slice(2);
    expect(buffer.bytes, [4, 5, 6, 7]);
    expect(slice.bytes, [6, 7]);
    buffer.dispose();
    slice.dispose();
  });

  test('FlatBuffers finish reset and freeze enforce builder state', () {
    final builder = allocator.flatBuffers();
    expect(builder.freeze, throwsStateError);
    final first = wire.MessageObjectBuilder(
      msgType: wire.AnyMessageTypeId.Call,
      msg: wire.CallObjectBuilder(request: 12, procedure: 'com.example.first'),
    );
    builder.finish(first.finish(builder));
    expect(() => builder.putUint8(7), throwsStateError);
    builder.reset();
    expect(builder.freeze, throwsStateError);
    final second = wire.MessageObjectBuilder(
      msgType: wire.AnyMessageTypeId.Call,
      msg: wire.CallObjectBuilder(request: 13, procedure: 'com.example.é🐈'),
    );
    builder.finish(second.finish(builder));
    final buffer = builder.freeze();
    expect(
      (wire.Message(buffer.bytes).msg as wire.Call).procedure,
      'com.example.é🐈',
    );
    expect((wire.Message(buffer.bytes).msg as wire.Call).request, 13);
    builder.dispose();
    builder.dispose();
    expect(builder.freeze, throwsStateError);
    expect(() => builder.reset(), throwsStateError);
    buffer.dispose();
  });

  test(
    'FlatBuffers callbacks cannot freeze or dispose during a vector write',
    () {
      final builder = allocator.flatBuffers();
      var prevented = 0;
      builder.writeListUint8(
        _ReentrantBytes(() {
          expect(builder.freeze, throwsStateError);
          expect(builder.dispose, throwsStateError);
          prevented++;
        }),
      );
      expect(prevented, greaterThan(0));
      builder.dispose();
    },
  );

  for (final webSocket in [false, true]) {
    test(
      'native ${webSocket ? 'WebSocket' : 'RawSocket'} accepts retained and transferred native frames',
      () async {
        final replies = ReceivePort();
        final messages = StreamIterator<dynamic>(replies);
        final server = await Isolate.spawn(_ownedFrameServer, (
          replies.sendPort,
          webSocket,
        ));
        addTearDown(() async {
          await messages.cancel();
          replies.close();
          server.kill(priority: Isolate.immediate);
        });
        expect(await messages.moveNext(), isTrue);
        final port = messages.current as int;
        final AbstractTransport transport = webSocket
            ? NativeWebSocketTransport.withJsonSerializer(
                'ws://127.0.0.1:$port/',
              )
            : NativeRawSocketTransport.withJsonSerializer('127.0.0.1', port);
        addTearDown(transport.close);
        final nativeTransport = transport as NativeBufferTransport;
        final builder = nativeTransport.nativeBuffers.allocate(128);
        const frame = '[48,42,{},"com.example.proc",[1]]';
        for (var index = 0; index < frame.length; index++) {
          builder.setUint8(64 + index, frame.codeUnitAt(index));
        }
        final buffer = builder.freeze(offset: 64, length: frame.length);
        addTearDown(buffer.dispose);
        expect(
          () => nativeTransport.sendEncodedNativeBuffer(buffer, transfer: true),
          throwsStateError,
        );
        expect(buffer.isDisposed, isFalse);
        await transport.open();
        await transport.onReady;
        final view = buffer.bytes;
        nativeTransport.sendEncodedNativeBuffer(buffer);
        expect(buffer.isDisposed, isFalse);
        expect(await messages.moveNext(), isTrue);
        expect(messages.current, utf8.encode(frame));
        nativeTransport.sendEncodedNativeBuffer(buffer, transfer: true);
        expect(buffer.isDisposed, isTrue);
        expect(await messages.moveNext(), isTrue);
        expect(messages.current, utf8.encode(frame));
        expect(view, utf8.encode(frame));
        expect(buffer.growthCopiedBytes, 0);
        expect(buffer.inputCopiedBytes, 0);

        final trackedBuffer = allocator.allocate(256);
        for (var i = 0; i < frame.length; i++) {
          trackedBuffer.setUint8(i, frame.codeUnitAt(i));
        }
        final frozen = trackedBuffer.freeze(length: frame.length);
        final retainedReceipt = nativeTransport.sendEncodedNativeBufferTracked(
          frozen,
        );
        expect(frozen.isDisposed, isFalse);
        expect(
          await retainedReceipt.wait(timeout: const Duration(seconds: 2)),
          NativeWriteOutcome.written,
        );
        retainedReceipt.dispose();
        retainedReceipt.dispose();
        expect(() => retainedReceipt.outcome, throwsStateError);
        expect(await messages.moveNext(), isTrue);
        expect(messages.current, utf8.encode(frame));
        final receipt = nativeTransport.sendEncodedNativeBufferTracked(
          frozen,
          transfer: true,
        );
        expect(frozen.isDisposed, isTrue);
        expect(
          await receipt.wait(timeout: const Duration(seconds: 2)),
          NativeWriteOutcome.written,
        );
        receipt.dispose();
        await nativeTransport.drainWrites();
        expect(await messages.moveNext(), isTrue);
        expect(messages.current, utf8.encode(frame));
      },
    );
  }

  test('preallocated model construction has no frame or growth copy', () {
    final buffer = allocator.buildFlatBuffer(
      wire.MessageObjectBuilder(
        msgType: wire.AnyMessageTypeId.Call,
        msg: wire.CallObjectBuilder(
          request: 77,
          procedure: 'com.example.proc',
          args: [0x80],
        ),
      ),
      initialSize: 1024,
    );
    addTearDown(buffer.dispose);
    final call = wire.Message(buffer.bytes).msg as wire.Call;
    expect(call.request, 77);
    expect(call.procedure, 'com.example.proc');
    expect(call.args, [0x80]);
    expect(buffer.growthCopiedBytes, 0);
    expect(buffer.inputCopiedBytes, 1);
  });

  test(
    'message models reuse native vectors without an envelope payload copy',
    () {
      final builder = allocator.flatBuffers(initialSize: 4096);
      addTearDown(builder.dispose);
      final vector = FlatBufferByteVectorReference(
        builder,
        builder.writeListUint8([0x81, 7]),
      );
      final message = Call(
        9007199254740992,
        'com.example.native',
        options: CallOptions(custom: {'_ready': true}),
      );
      builder.finish(
        writeWampFlatBufferMessage(
          message,
          builder,
          argumentsVector: vector,
        ),
      );
      final buffer = builder.freeze();
      addTearDown(buffer.dispose);
      final bytes = buffer.bytes;
      validateWampFlatBuffer(bytes);
      final rootMessage = wire.Message(bytes);
      final call = rootMessage.msg as wire.Call;
      expect(call.request, 9007199254740992);
      expect(call.procedure, 'com.example.native');
      expect(call.args, [0x81, 7]);
      expect(buffer.growthCopiedBytes, 0);
      expect(buffer.inputCopiedBytes, 2 + rootMessage.metadata!.length);
      final data = ByteData.sublistView(bytes);
      final root = data.getUint32(0, Endian.little);
      final rootVtable = root - data.getInt32(root, Endian.little);
      final msgField = root + data.getUint16(rootVtable + 6, Endian.little);
      final body = msgField + data.getUint32(msgField, Endian.little);
      final vtable = body - data.getInt32(body, Endian.little);
      final argsField = body + data.getUint16(vtable + 10, Endian.little);
      final argsOffset = argsField + data.getUint32(argsField, Endian.little);
      expect(argsOffset, bytes.length - vector.offset);
      builder.dispose();
      expect(call.args, [0x81, 7]);
      expect(() => builder.putUint8(1), throwsStateError);
    },
  );

  test(
    'native FlatBuffers remain physically aligned with odd capacity requests',
    () {
      final alignment =
          DynamicLibrary.open(
            NativeClientRuntime.instance().libraryPath,
          ).lookupFunction<UintPtr Function(), int Function()>(
            'ct_test_owned_buffer_last_frozen_alignment',
          );
      for (final size in [1023, 1, 9]) {
        final buffer = allocator.buildFlatBuffer(
          wire.MessageObjectBuilder(
            msgType: wire.AnyMessageTypeId.Publish,
            msg: wire.PublishObjectBuilder(
              request: 42,
              topic: 'com.example.topic',
              exclude: [4294967296],
            ),
          ),
          initialSize: size,
        );
        expect(alignment(), 0, reason: 'initialSize=$size');
        expect((wire.Message(buffer.bytes).msg as wire.Publish).exclude, [
          4294967296,
        ]);
        buffer.dispose();
      }
    },
  );

  test('repeated native growth preserves the independent table wire', () {
    int populate(fb.Builder builder) {
      final offsets = <int>[];
      for (var i = 0; i < 32; i++) {
        offsets.add(
          builder.writeString('field.$i.${List.filled(i + 1, 'x').join()}'),
        );
      }
      builder.startTable(offsets.length);
      for (var i = 0; i < offsets.length; i++) {
        builder.addOffset(i, offsets[i]);
      }
      return builder.endTable();
    }

    final builder = allocator.flatBuffers(initialSize: 8);
    addTearDown(builder.dispose);
    final expected = fb.Builder(initialSize: 8);
    expected.finish(populate(expected), 'OWNR');
    builder.finish(populate(builder), 'OWNR');
    expect(builder.allocationCount, greaterThanOrEqualTo(3));
    final owner = builder.freeze();
    addTearDown(owner.dispose);
    builder.dispose();
    expect(owner.bytes, expected.buffer);
    expect(() => builder.putUint8(1), throwsStateError);
  });

  test('native input failure after growth leaves the builder disposable', () {
    final builder = allocator.flatBuffers(initialSize: 8);
    addTearDown(builder.dispose);
    final failure = StateError('input failure after growth');
    expect(
      () => builder.writeListUint8(
        _ReentrantBytes(() => throw failure, count: 4096),
      ),
      throwsA(same(failure)),
    );
    expect(builder.allocationCount, greaterThan(1));
    expect(builder.dispose, returnsNormally);
    expect(builder.freeze, throwsStateError);
  });

  test('native growth releases frozen, failed-input and reset owners', () async {
    final source = await Isolate.resolvePackageUri(
      Uri.parse('package:connectanum_client/native_buffers.dart'),
    );
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        source!
            .resolve(
              '../test/transport/native/support/native_allocator_growth_probe.dart',
            )
            .toFilePath(),
      ],
      environment: {
        'CONNECTANUM_NATIVE_LIB': NativeClientRuntime.instance().libraryPath,
      },
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(
      result.stdout,
      contains(
        'native-allocator-growth: frozen, failed-input and reset paths release all owners',
      ),
    );
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('growth copies are counted and all writes are guarded after freeze', () {
    final builder = allocator.flatBuffers(initialSize: 8);
    final model = wire.MessageObjectBuilder(
      msgType: wire.AnyMessageTypeId.Publish,
      msg: wire.PublishObjectBuilder(
        request: 42,
        topic: 'com.example.topic',
        exclude: [1, 4294967296],
      ),
    );
    builder.finish(model.finish(builder));
    final buffer = builder.freeze();
    addTearDown(buffer.dispose);
    expect(builder.allocationCount, greaterThan(1));
    expect(buffer.growthCopiedBytes, greaterThan(0));
    expect((wire.Message(buffer.bytes).msg as wire.Publish).exclude, [
      1,
      4294967296,
    ]);
    for (final write in <void Function()>[
      () => builder.putUint8(1),
      () => builder.addOffset(0, 1),
      () => builder.startTable(1),
      () => builder.endTable(),
      () => builder.pad(1),
      () => builder.writeListUint8([1]),
      () => builder.writeString('x'),
      () => builder.reset(),
    ]) {
      expect(write, throwsStateError);
    }
    builder.dispose();
    expect(buffer.bytes, isNotEmpty);
  });

  test('model callbacks receive the guarded facade', () {
    final builder = allocator.flatBuffers();
    final model = _CapturingStruct();
    builder.writeListOfStructs([model]);
    expect(identical(model.builder, builder), isTrue);
    builder.dispose();
    expect(() => model.builder!.putUint32(3), throwsStateError);
  });

  test('reentrant input cannot release an allocation while writing', () {
    final builder = allocator.allocate(4);
    var blocked = 0;
    final bytes = _ReentrantBytes(() {
      try {
        builder.dispose();
      } on StateError {
        blocked++;
      }
      try {
        builder.freeze();
      } on StateError {
        blocked++;
      }
    });
    builder.writeBytes(0, bytes);
    final buffer = builder.freeze();
    addTearDown(buffer.dispose);
    expect(buffer.bytes, [1, 2, 3, 4]);
    expect(blocked, greaterThan(0));
  });

  test('native rejection consumes transfers and preserves retained sends', () {
    final buffer = allocator.allocate(4).freeze();
    final bytes = buffer.bytes;
    for (final connection in [0, -1, 0x100000001]) {
      expect(
        () => allocator.send(connection, buffer, transfer: true),
        throwsRangeError,
      );
      expect(buffer.isDisposed, isFalse);
    }
    expect(
      () => allocator.send(0x7fffffff, buffer),
      throwsA(isA<NativeBufferException>()),
    );
    expect(buffer.isDisposed, isFalse);
    expect(buffer.bytes, [0, 0, 0, 0]);
    expect(
      () => allocator.send(0x7fffffff, buffer, transfer: true),
      throwsA(isA<NativeBufferException>()),
    );
    expect(buffer.isDisposed, isTrue);
    expect(bytes, [0, 0, 0, 0]);
    expect(() => allocator.send(0x7fffffff, buffer), throwsStateError);
    // The runtime can initialize later; allocation ownership is independent.
    expect(NativeClientRuntime.instance().nativeBuffers.isSupported, isTrue);
  });

  test(
    'tracked rejection consumes transfers and preserves retained sends',
    () async {
      expect(allocator.supportsWriteCompletion, isTrue);
      final buffer = allocator.allocate(8).freeze();
      expect(
        () => allocator.sendTracked(0, buffer, transfer: true),
        throwsRangeError,
      );
      expect(buffer.isDisposed, isFalse);
      expect(
        () => allocator.sendTracked(0x7fffffff, buffer),
        throwsA(isA<NativeBufferException>()),
      );
      expect(buffer.isDisposed, isFalse);
      expect(
        () => allocator.sendTracked(0x7fffffff, buffer, transfer: true),
        throwsA(isA<NativeBufferException>()),
      );
      expect(buffer.isDisposed, isTrue);
      expect(() => allocator.sendTracked(0x7fffffff, buffer), throwsStateError);
      await expectLater(allocator.drainWrites(0), throwsRangeError);
      await expectLater(
        allocator.drainWrites(0x7fffffff),
        throwsA(isA<NativeBufferException>()),
      );
    },
  );
}

@pragma('vm:entry-point')
Future<void> _ownedFrameServer((SendPort, bool) configuration) async {
  final (replies, webSocket) = configuration;
  if (webSocket) {
    final server = await HttpServer.bind('127.0.0.1', 0);
    replies.send(server.port);
    final request = await server.first;
    final socket = await WebSocketTransformer.upgrade(
      request,
      protocolSelector: (protocols) =>
          protocols.contains('wamp.2.json') ? 'wamp.2.json' : null,
    );
    await for (final message in socket) {
      replies.send(message is String ? utf8.encode(message) : message);
    }
    await server.close(force: true);
  } else {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    replies.send(server.port);
    final socket = await server.first;
    final pending = <int>[];
    var handshake = false;
    await for (final chunk in socket) {
      pending.addAll(chunk);
      if (!handshake && pending.length >= 4) {
        if (pending[0] != 0x7f || (pending[1] & 0x0f) != 1) {
          throw StateError('Unexpected RawSocket handshake');
        }
        socket.add([0x7f, 0xf1, 0, 0]);
        pending.removeRange(0, 4);
        handshake = true;
      }
      while (handshake && pending.length >= 4) {
        final length = (pending[1] << 16) | (pending[2] << 8) | pending[3];
        if (pending.length < length + 4) break;
        if (pending[0] != 0) throw StateError('Expected WAMP frame');
        replies.send(pending.sublist(4, length + 4));
        pending.removeRange(0, length + 4);
      }
    }
    await server.close();
  }
}

class _CapturingStruct extends fb.ObjectBuilder {
  fb.Builder? builder;
  @override
  int finish(fb.Builder fbBuilder) {
    builder = fbBuilder;
    fbBuilder.putUint32(7);
    return fbBuilder.offset;
  }

  @override
  Uint8List toBytes() =>
      throw UnsupportedError('Test uses native struct vector');
}

class _ReentrantBytes extends ListBase<int> {
  _ReentrantBytes(this.callback, {this.count = 4});
  final void Function() callback;
  final int count;
  @override
  int get length => count;
  @override
  set length(int value) => throw UnsupportedError('Fixed test input');
  @override
  int operator [](int index) {
    callback();
    return index + 1;
  }

  @override
  void operator []=(int index, int value) =>
      throw UnsupportedError('Read only');
}
