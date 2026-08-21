import 'package:connectanum_core/connectanum_core.dart';

import 'e2ee_file_segment.dart';

class NativeWampCborXsalsa20Poly1305Provider
    implements
        DisposableWampE2eeProvider,
        WampE2eeProfileSupport,
        NativeE2eeFileSegmentProvider {
  NativeWampCborXsalsa20Poly1305Provider({
    required Map<String, List<int>> keys,
    String? defaultKeyId,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    String? libraryPath,
  }) {
    throw UnsupportedError(
      'Native WAMP E2EE provider requires dart:io and the ct_ffi runtime',
    );
  }

  NativeWampCborXsalsa20Poly1305Provider.single({
    required String keyId,
    required List<int> key,
    WampE2eeKeySelectionPolicy? keySelectionPolicy,
    String? libraryPath,
  }) {
    throw UnsupportedError(
      'Native WAMP E2EE provider requires dart:io and the ct_ffi runtime',
    );
  }

  @override
  List<dynamic> packPayload(
    List<dynamic>? arguments,
    Map<String, dynamic>? argumentsKeywords,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) => throw UnsupportedError(
    'Native WAMP E2EE provider requires dart:io and the ct_ffi runtime',
  );

  @override
  E2EEPayloadView unpackPayload(
    List<dynamic>? arguments,
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) => throw UnsupportedError(
    'Native WAMP E2EE provider requires dart:io and the ct_ffi runtime',
  );

  @override
  void release() {}

  @override
  bool get supportsNativeE2eeFileSegments => false;

  @override
  NativeE2eeFileSegmentContext prepareNativeE2eeFileSegment(
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  }) => throw UnsupportedError(
    'Native WAMP E2EE file segments require dart:io and the ct_ffi runtime',
  );

  @override
  bool supportsE2eeProfile({
    required int version,
    required String scheme,
    required String serializer,
    required String cipher,
  }) {
    return version == ConnectanumE2eeProfile.version &&
        scheme == ConnectanumE2eeProfile.scheme &&
        serializer == ConnectanumE2eeProfile.serializer &&
        cipher == ConnectanumE2eeProfile.xsalsa20Poly1305;
  }
}

class NativeWampCborAes256GcmProvider
    extends NativeWampCborXsalsa20Poly1305Provider {
  NativeWampCborAes256GcmProvider({
    required super.keys,
    super.defaultKeyId,
    super.keySelectionPolicy,
    super.libraryPath,
  });

  NativeWampCborAes256GcmProvider.single({
    required super.keyId,
    required super.key,
    super.keySelectionPolicy,
    super.libraryPath,
  }) : super.single();

  @override
  bool supportsE2eeProfile({
    required int version,
    required String scheme,
    required String serializer,
    required String cipher,
  }) {
    return version == ConnectanumE2eeProfile.version &&
        scheme == ConnectanumE2eeProfile.scheme &&
        serializer == ConnectanumE2eeProfile.serializer &&
        cipher == ConnectanumE2eeProfile.aes256Gcm;
  }
}
