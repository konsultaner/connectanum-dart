@TestOn('vm')
// ignore_for_file: unnecessary_library_name
library native_ffi_test_mode_test;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:connectanum_core/src/message/call.dart' as call_msg;
import 'package:connectanum_router/src/native/runtime.dart';
import 'package:test/test.dart';

String? _resolveNativeLib() {
  final env = Platform.environment['CONNECTANUM_NATIVE_LIB'];
  if (env != null && env.isNotEmpty && File(env).existsSync()) {
    return env;
  }
  const candidates = [
    'native/transport/target/debug/libct_ffi.so',
    '../../native/transport/target/debug/libct_ffi.so',
    'native/transport/target/ffi-test/debug/libct_ffi.so',
    '../../native/transport/target/ffi-test/debug/libct_ffi.so',
    'native/transport/target/ffi-test/release/libct_ffi.so',
    '../../native/transport/target/ffi-test/release/libct_ffi.so',
    'native/transport/target/release/libct_ffi.so',
    '../../native/transport/target/debug/libct_ffi.so',
    '../../native/transport/target/release/libct_ffi.so',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      return file.absolute.path;
    }
  }
  return null;
}

void main() {
  final nativeLib = _resolveNativeLib();
  final skipReason = nativeLib == null
      ? 'libct_ffi.so missing; build native transport with --features ffi-test first.'
      : null;

  group('ct_ffi test hooks', () {
    test('enqueue and materialise JSON CALL frame', () {
      final runtime = NativeTransportRuntime(libraryPath: nativeLib);
      addTearDown(() {
        runtime.shutdown();
        runtime.dispose();
      });
      expect(
        runtime.supportsTestHooks,
        isTrue,
        reason:
            'libct_ffi.so was built without the ffi-test feature; rebuild with cargo build -p ct_ffi --features ffi-test',
      );

      runtime.start();
      addTearDown(runtime.clearTestMessages);

      const connectionId = 9102;
      final frame = utf8.encode('[48,123,{},"com.example.proc"]');
      final handle = runtime.enqueueTestMessage(
        connectionId: connectionId,
        serializer: NativeMessageSerializer.json,
        frame: Uint8List.fromList(frame),
      );
      expect(handle, greaterThan(0));

      final decoder = NativeMessageHandleDecoder(libraryPath: nativeLib);
      final message = decoder.materialize(handle);
      addTearDown(message.dispose);

      expect(message.serializer, NativeMessageSerializer.json);
      expect(message.message, isA<call_msg.Call>());
      final call = message.message as call_msg.Call;
      expect(call.requestId, equals(123));
      expect(call.procedure, equals('com.example.proc'));

      message.dispose();
      decoder.release(handle);
    }, skip: skipReason);
  });
}
