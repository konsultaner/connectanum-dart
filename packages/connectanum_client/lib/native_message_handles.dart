/// Shared VM-only negotiation for opaque native routing-message handles.
library;

import 'dart:ffi' as ffi;

/// One binding family must cover producers, consumers, exports and cleanup.
enum NativeMessageHandleAbi {
  /// Original signed-32-bit ABI, retained for older native libraries.
  legacy,

  /// Additive version-1 signed-64-bit ABI; WAMP wire IDs are unchanged.
  wide;

  /// All symbols required by version 1, including the shared owner destructor.
  static const requiredWideSymbols = <String>[
    'ct_poll_connection_message_wide',
    'ct_wait_connection_message_wide',
    'ct_poll_websocket_message_wide',
    'ct_message_get_wide',
    'ct_message_peek_wide',
    'ct_message_retain_wide',
    'ct_message_release_wide',
    'ct_message_buffer_export_wide',
    'ct_message_buffer_free',
    'ct_message_decode_single_binary_argument_wide',
    'ct_sha256_update_message_binary_argument_wide',
    'ct_e2ee_session_decrypt_message_single_binary_argument_wide',
    'ct_e2ee_session_decrypt_message_payload_consume_wide',
    'ct_forward_publish_event_wide',
    'ct_forward_call_invocation_wide',
    'ct_forward_call_invocation_v2_wide',
    'ct_forward_result_from_yield_wide',
    'ct_forward_result_from_call_wide',
    'ct_forward_error_from_error_wide',
  ];

  /// Reads the advertisement before any message function is bound or called.
  static NativeMessageHandleAbi detect(ffi.DynamicLibrary library) {
    final version = library.providesSymbol('ct_message_handle_abi_version')
        ? library.lookupFunction<ffi.Uint32 Function(), int Function()>(
            'ct_message_handle_abi_version',
          )()
        : null;
    return negotiate(version: version, providesSymbol: library.providesSymbol);
  }

  /// Validates a native advertisement against its available symbol set.
  ///
  /// Unadvertised older libraries use the legacy family. An unsupported or
  /// incomplete advertised ABI fails closed rather than mixing handle widths.
  static NativeMessageHandleAbi negotiate({
    required int? version,
    required bool Function(String symbol) providesSymbol,
  }) {
    if (version == null) return legacy;
    if (version != 1) {
      throw UnsupportedError('Unsupported native message handle ABI: $version');
    }
    for (final symbol in requiredWideSymbols) {
      if (!providesSymbol(symbol)) {
        throw UnsupportedError('Incomplete native message handle ABI: $symbol');
      }
    }
    return wide;
  }
}

/// Rejects truncation before invoking a legacy signed-32-bit callback.
///
/// In-range nonpositive values retain the native error/no-op behavior.
int checkedLegacyMessageHandle(int handle) {
  if (handle < -0x80000000 || handle > 0x7fffffff) {
    throw RangeError.range(handle, -0x80000000, 0x7fffffff, 'message handle');
  }
  return handle;
}
