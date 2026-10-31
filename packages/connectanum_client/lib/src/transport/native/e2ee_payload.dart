import 'dart:typed_data';

import 'package:connectanum_core/connectanum_core.dart';

/// Native-owned ciphertext produced for a Session without exporting its owner.
///
/// The byte view can be serialized by ordinary transports. Native transports
/// may use [storageOwner] to retain the original allocation through the write.
final class NativeE2eeOwnedPayload {
  const NativeE2eeOwnedPayload({
    required this.bytes,
    required this.storageOwner,
    required this.encoding,
  });

  final Uint8List bytes;
  final Object storageOwner;
  final LazyPayloadEncoding encoding;
}

/// Optional native fast path for packing E2EE payloads in Session.
abstract interface class NativeE2eePayloadPacker {
  NativeE2eeOwnedPayload? packNativePayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  });
}
