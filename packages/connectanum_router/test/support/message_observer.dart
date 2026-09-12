import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';
import 'package:connectanum_client/native_message_handles.dart';

/// Test-only weak observer: never retains storage or reads released payloads.
class MessageObserver {
  MessageObserver(ffi.DynamicLibrary library)
    : watch =
          NativeMessageHandleAbi.detect(library) == NativeMessageHandleAbi.wide
          ? library.lookupFunction<
              ffi.Pointer<ffi.Void> Function(ffi.Int64),
              ffi.Pointer<ffi.Void> Function(int)
            >('ct_test_message_observer_new_wide')
          : library.lookupFunction<
              ffi.Pointer<ffi.Void> Function(ffi.Int32),
              ffi.Pointer<ffi.Void> Function(int)
            >('ct_test_message_observer_new'),
      _watchCall = library
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>, ffi.UintPtr),
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>, int)
          >('ct_test_call_observer_new'),
      alive = library
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('ct_test_message_observer_alive'),
      free = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)
          >('ct_test_message_observer_free');

  final ffi.Pointer<ffi.Void> Function(int) watch;
  final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>, int) _watchCall;
  final int Function(ffi.Pointer<ffi.Void>) alive;
  final void Function(ffi.Pointer<ffi.Void>) free;

  ffi.Pointer<ffi.Void> watchCall(String procedure) {
    final name = procedure.toNativeUtf8();
    try {
      return _watchCall(name.cast(), name.length);
    } finally {
      malloc.free(name);
    }
  }
}
