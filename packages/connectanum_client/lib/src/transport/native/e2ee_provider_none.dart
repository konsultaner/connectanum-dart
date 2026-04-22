import 'package:connectanum_core/connectanum_core.dart';

class NativeWampCborXsalsa20Poly1305Provider
    implements DisposableWampE2eeProvider {
  NativeWampCborXsalsa20Poly1305Provider({
    required Map<String, List<int>> keys,
    String? defaultKeyId,
  }) {
    throw UnsupportedError(
      'Native WAMP E2EE provider requires dart:io and the ct_ffi runtime',
    );
  }

  NativeWampCborXsalsa20Poly1305Provider.single({
    required String keyId,
    required List<int> key,
  }) {
    throw UnsupportedError(
      'Native WAMP E2EE provider requires dart:io and the ct_ffi runtime',
    );
  }

  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options,
  ) => throw UnsupportedError(
    'Native WAMP E2EE provider requires dart:io and the ct_ffi runtime',
  );

  @override
  E2EEPayloadView unpackPayload(List<dynamic>? arguments, PPTOptions options) =>
      throw UnsupportedError(
        'Native WAMP E2EE provider requires dart:io and the ct_ffi runtime',
      );

  @override
  void release() {}
}
