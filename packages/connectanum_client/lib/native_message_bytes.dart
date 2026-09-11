/// Shared VM-only native message storage support for the client and router.
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_message_handles.dart';

/// Stable native slice selectors; these values are part of the FFI ABI.
enum NativeMessageBytePart {
  /// The complete encoded frame, materialized only when requested.
  frame,

  /// The encoded positional arguments.
  arguments,

  /// The encoded keyword arguments.
  argumentsKeywords,

  /// The encoded message details/options.
  details,

  /// A supported invocation's sole binary argument, without its encoding header.
  singleBinaryArgument,
}

final class _MessageByteView extends ffi.Struct {
  external ffi.Pointer<ffi.Uint8> data;
  @ffi.UintPtr()
  external int length;
  external ffi.Pointer<ffi.Void> owner;
}

typedef _ExportNative =
    ffi.Int32 Function(
      ffi.Int32,
      ffi.Uint32,
      ffi.Pointer<_MessageByteView>,
    );
typedef _ExportDart = int Function(int, int, ffi.Pointer<_MessageByteView>);
typedef _ExportWideNative =
    ffi.Int32 Function(ffi.Int64, ffi.Uint32, ffi.Pointer<_MessageByteView>);

/// Creates byte views that remain valid after a routing handle is released.
///
/// New runtimes export independent native owners, attached to the external
/// typed-data allocation so all subviews retain storage. Older runtimes use an
/// owned Dart copy, never an unowned view. No explicit disposal is required.
final class NativeMessageBytes {
  /// Resolves the optional, paired ownership entry points in [library].
  NativeMessageBytes(ffi.DynamicLibrary library)
    : messageHandleAbi = NativeMessageHandleAbi.detect(library) {
    if (messageHandleAbi == NativeMessageHandleAbi.wide) {
      _export = library.lookupFunction<_ExportWideNative, _ExportDart>(
        'ct_message_buffer_export_wide',
      );
    } else {
      if (!library.providesSymbol('ct_message_buffer_export') ||
          !library.providesSymbol('ct_message_buffer_free')) {
        return;
      }
      _export = library.lookupFunction<_ExportNative, _ExportDart>(
        'ct_message_buffer_export',
      );
    }
    _finalizer = library.lookup<ffi.NativeFinalizerFunction>(
      'ct_message_buffer_free',
    );
    _free = _finalizer!.asFunction<void Function(ffi.Pointer<ffi.Void>)>();
  }

  _ExportDart? _export;

  /// The same complete ABI used by the client and router message bindings.
  final NativeMessageHandleAbi messageHandleAbi;
  ffi.Pointer<ffi.NativeFinalizerFunction>? _finalizer;
  void Function(ffi.Pointer<ffi.Void>)? _free;

  /// Whether this runtime can retain message bytes without a payload copy.
  bool get supportsZeroCopy => _export != null;

  /// Copies [part] and consumes the owned copy under a temporary native owner.
  ///
  /// Use for metadata: a small, long-lived details map must not pin a large
  /// payload. On new runtimes the whole message stays alive through [consume],
  /// allowing its other metadata strings to be copied synchronously. Neither
  /// a borrowed view nor the native owner escapes to [consume]. Its returned
  /// value may retain the Dart copy, but not other borrowed native pointers.
  /// Legacy runtimes require the caller's handle to stay alive throughout.
  T withCopiedBytes<T>(
    int handle,
    NativeMessageBytePart part, {
    required ffi.Pointer<ffi.Uint8> borrowed,
    required int length,
    required T Function(Uint8List copy) consume,
  }) {
    if (messageHandleAbi == NativeMessageHandleAbi.legacy) {
      checkedLegacyMessageHandle(handle);
    }
    if (handle <= 0 || length < 0 || (length > 0 && borrowed == ffi.nullptr)) {
      throw ArgumentError('Invalid native message byte view');
    }
    if (length == 0) return consume(Uint8List(0));
    final export = _export;
    if (export == null) {
      return consume(Uint8List.fromList(borrowed.asTypedList(length)));
    }
    final output = calloc<_MessageByteView>();
    try {
      final status = export(handle, part.index, output);
      if (status != 0) {
        throw StateError('Native message byte export failed ($status)');
      }
      final view = output.ref;
      if (view.owner == ffi.nullptr ||
          view.data != borrowed ||
          view.length != length) {
        throw StateError(
          'Native message byte export disagrees with message info',
        );
      }
      return consume(Uint8List.fromList(view.data.asTypedList(view.length)));
    } finally {
      _free!(output.ref.owner);
      calloc.free(output);
    }
  }

  /// Exports [part] while the caller still owns [handle].
  ///
  /// [borrowed] and [length] must come from that handle's native message info,
  /// not a remote address. They permit safe copying on legacy runtimes and
  /// verify the slice selected by a new runtime. Cross-isolate receivers must
  /// first acquire their own handle; an expired handle must fail closed.
  Uint8List read(
    int handle,
    NativeMessageBytePart part, {
    required ffi.Pointer<ffi.Uint8> borrowed,
    required int length,
  }) {
    if (messageHandleAbi == NativeMessageHandleAbi.legacy) {
      checkedLegacyMessageHandle(handle);
    }
    if (handle <= 0 || length < 0 || (length > 0 && borrowed == ffi.nullptr)) {
      throw ArgumentError('Invalid native message byte view');
    }
    if (length == 0) return Uint8List(0);
    final export = _export;
    if (export == null) return Uint8List.fromList(borrowed.asTypedList(length));
    final output = calloc<_MessageByteView>();
    try {
      final status = export(handle, part.index, output);
      if (status != 0) {
        throw StateError('Native message byte export failed ($status)');
      }
      final view = output.ref;
      if (view.owner == ffi.nullptr ||
          view.data != borrowed ||
          view.length != length) {
        _free!(view.owner);
        throw StateError(
          'Native message byte export disagrees with message info',
        );
      }
      try {
        return view.data.asTypedList(
          view.length,
          finalizer: _finalizer,
          token: view.owner,
        );
      } catch (_) {
        _free!(view.owner);
        rethrow;
      }
    } finally {
      calloc.free(output);
    }
  }
}
