@TestOn('vm')
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:connectanum_client/connectanum.dart';
import 'package:connectanum_client/native_buffers.dart';
import 'package:connectanum_core/flatbuffers_serializer.dart' as flatbuffers;
import 'package:test/test.dart';

void main() {
  late NativeBufferAllocator allocator;
  setUpAll(() {
    allocator = NativeBufferAllocator(
      DynamicLibrary.open(Platform.environment['CONNECTANUM_NATIVE_LIB']!),
    );
  });

  NativeOwnedBuffer encoded(Uint8List bytes) {
    final builder = allocator.allocate(bytes.length);
    try {
      builder.writeBytes(0, bytes);
      return builder.freeze();
    } finally {
      builder.dispose();
    }
  }

  NativeOwnedBuffer control([AbstractMessage? message]) {
    final builder = allocator.flatBuffers(initialSize: 8192);
    try {
      builder.finish(
        flatbuffers.writeWampFlatBufferMessage(
          message ?? Call(7, 'com.echo'),
          builder,
        ),
      );
      return builder.freeze();
    } finally {
      builder.dispose();
    }
  }

  NativeOwnedBuffer nativeArguments() {
    final builder = allocator.allocate(4);
    try {
      // Construct the encoded array [1, 2, 3] directly in native storage.
      builder.setUint8(0, 0x83);
      builder.setUint8(1, 1);
      builder.setUint8(2, 2);
      builder.setUint8(3, 3);
      return builder.freeze();
    } finally {
      builder.dispose();
    }
  }

  test('native frame capability and direct scalar payload construction', () {
    expect(allocator.supportsFlatBufferFrames, isTrue);
    final envelope = control();
    final args = nativeArguments();
    final frame = allocator.composeFlatBufferFrame(envelope, arguments: args);
    expect(args.inputCopiedBytes, 0);
    expect(args.growthCopiedBytes, 0);
    expect(frame.segmentCount, greaterThan(1));
    expect(frame.length, greaterThan(args.length));
    expect(envelope.isDisposed, isFalse);
    expect(args.isDisposed, isFalse);
    envelope.dispose();
    args.dispose();
    expect(
      flatbuffers.Serializer().deserialize(frame.controlBytes),
      isA<Call>(),
    );
    frame.dispose();
  });

  test(
    'native frame finalizers release payload before independent control view',
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
                '../test/transport/native/support/native_frame_gc_probe.dart',
              )
              .toFilePath(),
        ],
        environment: {
          'CONNECTANUM_NATIVE_LIB':
              Platform.environment['CONNECTANUM_NATIVE_LIB']!,
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stdout,
        contains(
          'native-frame-gc: abandoned frames released payload; derived control view retained then released storage',
        ),
      );
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'retained frame and read-only control view have independent lifetimes',
    () {
      final envelope = control();
      final args = nativeArguments();
      final frame = allocator.composeFlatBufferFrame(envelope, arguments: args);
      final retained = frame.retain();
      final view = frame.controlBytes;
      final expected = view.toList();
      envelope.dispose();
      args.dispose();
      frame.dispose();
      expect(frame.isDisposed, isTrue);
      expect(retained.isDisposed, isFalse);
      expect(retained.length, frame.length);
      expect(retained.controlBytes, expected);
      retained.dispose();
      expect(view, expected);
      expect(() => view[0] = 0, throwsUnsupportedError);
      expect(
        () => ByteData.view(view.buffer).setUint8(0, 0),
        throwsUnsupportedError,
      );
      expect(() => frame.retain(), throwsStateError);
      expect(() => frame.controlBytes, throwsStateError);
      frame.dispose();
    },
  );

  test('invalid composition preserves every caller buffer', () {
    final envelope = control();
    final args = nativeArguments();
    final wrongKeywords = encoded(Uint8List.fromList([0x80]));
    expect(
      () => allocator.composeFlatBufferFrame(
        envelope,
        arguments: args,
        argumentsKeywords: wrongKeywords,
      ),
      throwsA(
        isA<NativeBufferException>().having((error) => error.code, 'code', -4),
      ),
    );
    for (final buffer in [envelope, args, wrongKeywords]) {
      expect(buffer.isDisposed, isFalse);
      expect(buffer.bytes, isNotEmpty);
    }
    final empty = allocator.allocate(0).freeze();
    expect(
      () => allocator.composeFlatBufferFrame(envelope, arguments: empty),
      throwsA(isA<NativeBufferException>()),
    );
    final opaque = allocator.composeFlatBufferFrame(
      envelope,
      opaquePayload: empty,
    );
    expect(opaque.segmentCount, greaterThan(1));
    opaque.dispose();
    empty.dispose();
    for (final buffer in [envelope, args, wrongKeywords]) {
      buffer.dispose();
    }
  });

  test(
    'retained and transferred sends preserve the documented rejection boundary',
    () {
      for (final tracked in [false, true]) {
        final envelope = control();
        final args = nativeArguments();
        final frame = allocator.composeFlatBufferFrame(
          envelope,
          arguments: args,
        );
        void send(int connection, {bool transfer = false}) {
          if (tracked) {
            allocator
                .sendFrameTracked(connection, frame, transfer: transfer)
                .dispose();
          } else {
            allocator.sendFrame(connection, frame, transfer: transfer);
          }
        }

        expect(() => send(0, transfer: true), throwsRangeError);
        expect(frame.isDisposed, isFalse);
        expect(() => send(0x7fffffff), throwsA(isA<NativeBufferException>()));
        expect(frame.isDisposed, isFalse);
        expect(frame.controlBytes, isNotEmpty);
        expect(
          () => send(0x7fffffff, transfer: true),
          throwsA(isA<NativeBufferException>()),
        );
        expect(frame.isDisposed, isTrue);
        expect(() => frame.retain(), throwsStateError);
        expect(args.isDisposed, isFalse);
        frame.dispose();
        envelope.dispose();
        args.dispose();
      }
    },
  );

  test(
    'older ABI and foreign buffers reject before consumption',
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
        'connectanum-frame-abi-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final library =
          '${directory.path}/old.${Platform.isMacOS ? 'dylib' : 'so'}';
      final result = await Process.run('cc', [
        Platform.isMacOS ? '-dynamiclib' : '-shared',
        '-fPIC',
        '-DOWNED_BUFFER_VERSION=1',
        '-DEXTERNAL_LEASE_VERSION=1',
        '-DWRITE_RECEIPT_VERSION=1',
        '-o',
        library,
        fixture,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final old = NativeBufferAllocator(DynamicLibrary.open(library));
      expect(old.isSupported, isTrue);
      expect(old.supportsFlatBufferFrames, isFalse);
      final envelope = control();
      expect(
        () => old.composeFlatBufferFrame(envelope),
        throwsUnsupportedError,
      );
      expect(envelope.isDisposed, isFalse);
      final copiedLibrary =
          '${directory.path}/foreign.${Platform.isMacOS ? 'dylib' : 'so'}';
      await File(
        Platform.environment['CONNECTANUM_NATIVE_LIB']!,
      ).copy(copiedLibrary);
      final foreignAllocator = NativeBufferAllocator(
        DynamicLibrary.open(copiedLibrary),
      );
      expect(foreignAllocator.supportsFlatBufferFrames, isTrue);
      final foreign = foreignAllocator.allocate(1).freeze();
      expect(
        () => allocator.composeFlatBufferFrame(envelope, arguments: foreign),
        throwsArgumentError,
      );
      expect(foreign.isDisposed, isFalse);
      final frame = allocator.composeFlatBufferFrame(envelope);
      expect(
        () => old.sendFrame(1, frame, transfer: true),
        throwsUnsupportedError,
      );
      expect(frame.isDisposed, isFalse);
      expect(
        () => foreignAllocator.sendFrame(1, frame, transfer: true),
        throwsArgumentError,
      );
      expect(frame.isDisposed, isFalse);
      frame.dispose();
      foreign.dispose();
      envelope.dispose();
    },
    skip: Platform.isWindows
        ? 'ABI fixture requires a Unix C toolchain'
        : false,
  );
}
