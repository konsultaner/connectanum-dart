@TestOn('vm')
library;

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_router/src/native/mqtt_frame_buffer.dart';
import 'package:test/test.dart';

import '../support/native_lib.dart';

void main() {
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
}
