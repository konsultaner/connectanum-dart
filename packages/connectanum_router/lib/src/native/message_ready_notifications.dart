import 'dart:async';
import 'dart:ffi' as ffi;

typedef _WakeNative = ffi.Void Function();
typedef _RegisterNative =
    ffi.Void Function(ffi.Pointer<ffi.NativeFunction<_WakeNative>>);
typedef _RegisterDart =
    void Function(ffi.Pointer<ffi.NativeFunction<_WakeNative>>);
typedef _ArmNative = ffi.Void Function();
typedef _ArmDart = void Function();

/// Optional, coalesced notifications for the existing native message queues.
/// Notifications carry no message, pointer or ownership obligation.
class NativeMessageReadyNotifications {
  NativeMessageReadyNotifications(this._library) {
    if (_library.providesSymbol('ct_set_message_ready_callback_v1') &&
        _library.providesSymbol('ct_arm_message_ready_callback_v1')) {
      // Keep these non-leaf: removal/arming synchronize with native callbacks.
      _register = _library.lookupFunction<_RegisterNative, _RegisterDart>(
        'ct_set_message_ready_callback_v1',
      );
      _arm = _library.lookupFunction<_ArmNative, _ArmDart>(
        'ct_arm_message_ready_callback_v1',
      );
    }
  }

  final ffi.DynamicLibrary _library;
  _RegisterDart? _register;
  _ArmDart? _arm;
  ffi.NativeCallable<_WakeNative>? _callback;
  bool _suspended = true;
  bool _disposed = false;
  int _generation = 0;
  late final _events = StreamController<void>.broadcast(
    onListen: _start,
    onCancel: _stop,
  );

  bool get hasNativeSupport => _register != null;
  Stream<void> get events => _events.stream;

  void resume() {
    if (_disposed) return;
    _suspended = false;
    _start();
  }

  void suspend() {
    _suspended = true;
    _stop();
  }

  void arm() {
    if (!_disposed && !_suspended && _callback != null) {
      _arm!();
    }
  }

  void _start() {
    if (_disposed ||
        _suspended ||
        !_events.hasListener ||
        _callback != null ||
        !hasNativeSupport) {
      return;
    }
    final generation = ++_generation;
    final callback = ffi.NativeCallable<_WakeNative>.listener(() {
      if (!_disposed && !_suspended && generation == _generation) {
        _events.add(null);
      }
    });
    _callback = callback;
    _register!(callback.nativeFunction);
  }

  void _stop() {
    final callback = _callback;
    if (callback == null) return;
    ++_generation;
    // Native removal waits for every invocation to return before close.
    _register!(ffi.nullptr);
    _callback = null;
    callback.close();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stop();
    unawaited(_events.close());
  }
}
