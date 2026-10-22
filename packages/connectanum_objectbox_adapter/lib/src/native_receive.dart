// Exact released Connectanum compatibility layer; network bytes cannot forge
// these Dart ownership anchors. SDK internals are version pinned and tested.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member
import 'dart:ffi';
import 'dart:typed_data';

import 'package:connectanum_client/native_message_bytes.dart';
import 'package:connectanum_client/src/transport/native/external_byte_buffer.dart';
import 'package:connectanum_client/src/transport/native/ffi_bindings.dart'
    as ct;
import 'package:connectanum_client/src/transport/native/message_protocol.dart';
import 'package:connectanum_client/src/transport/native/runtime.dart'
    show NativeClientRuntime, NativeIncomingMessage;
import 'package:ffi/ffi.dart';

final _receiveBridges = Expando<_ReceiveBridge>();

NativeExternalByteSlice? resolveReceivedNativeBytes(
  Uint8List bytes,
  Object? owner,
) {
  Object? candidate = owner;
  for (var depth = 0; depth < 8; depth++) {
    if (candidate is NativeIncomingMessage) {
      final runtime = candidate.runtimeIdentity;
      if (runtime is! NativeClientRuntime) return null;
      final bridge = _receiveBridges[runtime] ??= _ReceiveBridge(
        runtime.libraryPath,
      );
      return bridge.borrow(candidate, bytes);
    }
    if (candidate == null ||
        candidate is num ||
        candidate is String ||
        candidate is bool ||
        candidate is Record) {
      return null;
    }
    final next = sessionMessageAnchorFor(candidate);
    if (identical(next, candidate)) return null;
    candidate = next;
  }
  return null;
}

final class _ReceiveBridge {
  _ReceiveBridge(String path) : this._(DynamicLibrary.open(path));
  _ReceiveBridge._(DynamicLibrary library)
    : bindings = ct.CtFfiBindings(library),
      messageBytes = NativeMessageBytes(library);
  final ct.CtFfiBindings bindings;
  final NativeMessageBytes messageBytes;

  NativeExternalByteSlice? borrow(
    NativeIncomingMessage incoming,
    Uint8List bytes,
  ) {
    if (!messageBytes.supportsZeroCopy) return null;
    final output = calloc<ct.CtMessageInfo>();
    try {
      if (bindings.ctMessagePeek(incoming.handle, output) != 0) return null;
      final info = output.ref;
      if (info.binaryArgPtr != nullptr && info.binaryArgLen == bytes.length) {
        final part =
            (info.flags & NativeMessageMetadata.flagTransparentPayload) != 0
            ? NativeMessageBytePart.transparentPayload
            : NativeMessageBytePart.singleBinaryArgument;
        final result = _export(
          incoming.handle,
          part,
          info.binaryArgPtr,
          info.binaryArgLen,
          bytes,
          encoded: false,
        );
        if (result != null) return result;
      }
      if (info.argsPtr == nullptr || info.argsLen == 0) return null;
      return _export(
        incoming.handle,
        NativeMessageBytePart.arguments,
        info.argsPtr,
        info.argsLen,
        bytes,
        encoded: true,
      );
    } finally {
      calloc.free(output);
    }
  }

  NativeExternalByteSlice? _export(
    int handle,
    NativeMessageBytePart part,
    Pointer<Uint8> pointer,
    int length,
    Uint8List supplied, {
    required bool encoded,
  }) {
    // Acquire a new SDK-owned native lease before using a raw peek pointer.
    // Its backing-store finalizer survives release of the routing handle.
    final Uint8List lease;
    try {
      lease = messageBytes.read(
        handle,
        part,
        borrowed: pointer,
        length: length,
      );
    } on StateError {
      return null;
    }
    final range = encoded ? _singleBinaryRange(lease) : (0, lease.length);
    if (range == null || range.$2 != supplied.length) return null;
    // A lazy decoder can return another view or a Dart-owned copy. Modified
    // lists and forged anchors must never substitute a different native body.
    for (var index = 0; index < supplied.length; index++) {
      if (supplied[index] != lease[range.$1 + index]) return null;
    }
    return NativeExternalByteSlice(
      pointer: pointer + range.$1,
      length: supplied.length,
      owner: lease,
    );
  }

  // Only a complete definite binary value, optionally in a one-element array,
  // is eligible. The runtime may retain CBOR-normalized arguments for another
  // wire codec. Unsupported layouts fall back to a measured staging copy.
  static (int, int)? _singleBinaryRange(Uint8List encoded) {
    if (encoded.isEmpty) return null;
    var at = 0;
    if (encoded[0] == 0x81 || encoded[0] == 0x91) at++;
    if (at == encoded.length) return null;
    final initial = encoded[at++];
    int size;
    if (initial >= 0x40 && initial <= 0x57) {
      size = initial - 0x40;
    } else {
      final width = switch (initial) {
        0x58 || 0xc4 => 1,
        0x59 || 0xc5 => 2,
        0x5a || 0xc6 => 4,
        0x5b => 8,
        _ => 0,
      };
      if (width == 0 || at > encoded.length - width) return null;
      size = 0;
      for (var index = 0; index < width; index++) {
        size = (size << 8) | encoded[at++];
      }
    }
    if (size < 0 || size != encoded.length - at) return null;
    return (at, size);
  }
}
