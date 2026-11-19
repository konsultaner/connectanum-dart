@TestOn('vm')
library;

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'dart:typed_data';

import 'package:connectanum_router/src/native/mqtt_frame_buffer.dart';
import 'package:test/test.dart';

import '../support/native_lib.dart';

void _echoSnapshot(SendPort parent) {
  final port = ReceivePort();
  parent.send(port.sendPort);
  port.listen((value) {
    final bytes = NativeIsolateBytes.materialize(value as NativeByteSnapshot);
    parent.send(NativeIsolateBytes.transfer(bytes));
  });
}

void main() {
  test(
    'immutable snapshot owns input and shares the same backing across isolates',
    () async {
      final library = ffi.DynamicLibrary.open(resolveOrBuildNativeLib()!);
      NativeMqttFrameBufferAllocator.forLibrary(library);
      final expected = List.generate(65536, (i) => i % 251);
      final source = Uint8List.fromList(expected);
      final transfer = NativeIsolateBytes.transfer(source)!;
      final bytes = NativeIsolateBytes.materialize(transfer);
      source.fillRange(0, source.length, 0);
      expect(() => bytes[0] = 0, throwsUnsupportedError);
      final port = ReceivePort();
      final messages = StreamIterator(port);
      final child = await Isolate.spawn(_echoSnapshot, port.sendPort);
      try {
        await messages.moveNext();
        (messages.current as SendPort).send(transfer);
        await messages.moveNext();
        final received = NativeIsolateBytes.materialize(
          messages.current as NativeByteSnapshot,
        );
        expect(identical(bytes, received), isTrue);
        expect(received, expected);
      } finally {
        child.kill(priority: Isolate.immediate);
        await messages.cancel();
        port.close();
      }
    },
  );
  final legacy = ffi.DynamicLibrary.open(switch (Platform.operatingSystem) {
    'macos' => '/usr/lib/libSystem.B.dylib',
    'linux' => 'libc.so.6',
    'windows' => 'kernel32.dll',
    _ => throw UnsupportedError('Native transport platform'),
  });

  test('legacy libraries support owned small and large MQTT frame bodies', () {
    final allocator = NativeMqttFrameBufferAllocator.forLibrary(legacy);
    expect(allocator.supportsMappedBytes, isFalse);
    for (final length in [0, 16383, 16384, 65537]) {
      final body = allocator.allocate(length);
      expect(body, hasLength(length));
      expect(body.every((byte) => byte == 0), isTrue);
      if (length != 0) {
        body[length - 1] = 251;
        expect(Uint8List.sublistView(body, length - 1), [251]);
      }
    }
    expect(() => allocator.allocate(-1), throwsRangeError);
    expect(() => allocator.allocate(0x80000000), throwsRangeError);
  });

  test('fresh native library provides zeroed, mutable mapped bodies', () {
    final path = resolveOrBuildNativeLib();
    expect(path, isNotNull);
    final library = ffi.DynamicLibrary.open(path!);
    final allocator = NativeMqttFrameBufferAllocator.forLibrary(library);
    expect(allocator.supportsMappedBytes, isTrue);
    expect(
      NativeMqttFrameBufferAllocator.forLibrary(ffi.DynamicLibrary.open(path)),
      same(allocator),
    );
    for (final length in [1, 16383, 16384, 65537, 1 << 20]) {
      final body = allocator.allocate(length);
      expect(body, hasLength(length));
      expect(body.every((byte) => byte == 0), isTrue);
      final tail = Uint8List.sublistView(body, length - 1);
      tail[0] = 249;
      expect(body.last, 249);
    }
  });

  test(
    'native allocation and SDK view failures release ownership exactly once',
    () async {
      final source =
          (await Isolate.resolvePackageUri(
            Uri.parse(
              'package:connectanum_router/src/native/mqtt_frame_buffer.dart',
            ),
          ))!.resolve(
            '../../../test/support/mqtt_frame_allocator_failure_fixture.rs',
          );
      final directory = Directory.systemTemp.createTempSync('mqtt-allocator-');
      final output =
          '${directory.path}/${switch (Platform.operatingSystem) {
            'macos' => 'libfailure.dylib',
            'windows' => 'failure.dll',
            _ => 'libfailure.so',
          }}';
      final compiled = await Process.run('rustc', [
        '--crate-type',
        'cdylib',
        '--edition=2021',
        source.toFilePath(),
        '-o',
        output,
      ]);
      expect(
        compiled.exitCode,
        0,
        reason: '${compiled.stdout}\n${compiled.stderr}',
      );
      final library = ffi.DynamicLibrary.open(output);
      final allocator = NativeMqttFrameBufferAllocator.forLibrary(library);
      final mode = library
          .lookupFunction<ffi.Void Function(ffi.UintPtr), void Function(int)>(
            'fixture_mode',
          );
      final released = library
          .lookupFunction<ffi.UintPtr Function(), int Function()>(
            'fixture_released',
          );
      expect(() => allocator.allocate(65536), throwsStateError);
      expect(released(), 0);
      mode(1);
      expect(() => allocator.allocate(65536), throwsArgumentError);
      expect(released(), 1);
      mode(0);
      expect(() => allocator.allocate(65536), throwsStateError);
      expect(released(), 1);
      expect(
        () => NativeIsolateBytes.transfer(Uint8List(65536)),
        throwsStateError,
      );
      expect(released(), 1);
      mode(1);
      expect(
        () => NativeIsolateBytes.transfer(Uint8List(65536)),
        throwsArgumentError,
      );
      expect(released(), 2);
      NativeMqttFrameBufferAllocator.forLibrary(
        ffi.DynamicLibrary.open(resolveOrBuildNativeLib()!),
      );
      // Keep the cached finalizer library open. POSIX permits unlinking its file;
      // Windows retains the loaded test fixture until the process exits.
      if (!Platform.isWindows) directory.deleteSync(recursive: true);
    },
  );
}
