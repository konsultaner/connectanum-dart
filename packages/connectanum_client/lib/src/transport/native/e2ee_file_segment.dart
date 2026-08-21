import 'package:connectanum_core/connectanum_core.dart';

class NativeE2eeFileSegmentContext {
  const NativeE2eeFileSegmentContext({
    required this.runtimeIdentity,
    required this.sessionHandle,
    required this.keyId,
    required this.cipher,
  });

  final Object runtimeIdentity;
  final int sessionHandle;
  final String keyId;
  final String cipher;
}

abstract interface class NativeE2eeFileSegmentProvider {
  bool get supportsNativeE2eeFileSegments;

  NativeE2eeFileSegmentContext prepareNativeE2eeFileSegment(
    PPTOptions options, {
    WampE2eeRuntimeContext? runtimeContext,
  });
}

int nativeE2eeFileSegmentCiphertextLength(int fileLength, String cipher) {
  if (fileLength < 0) {
    throw ArgumentError.value(fileLength, 'fileLength', 'must be non-negative');
  }
  final byteStringHeaderLength = switch (fileLength) {
    < 24 => 1,
    <= 0xff => 2,
    <= 0xffff => 3,
    <= 0xffffffff => 5,
    _ => 9,
  };
  final nonceLength = switch (cipher) {
    ConnectanumE2eeProfile.aes256Gcm => 12,
    ConnectanumE2eeProfile.xsalsa20Poly1305 => 24,
    _ => throw ArgumentError.value(cipher, 'cipher', 'is unsupported'),
  };
  const envelopeBytesWithoutBinaryHeader = 15;
  const authenticationTagLength = 16;
  return fileLength +
      byteStringHeaderLength +
      envelopeBytesWithoutBinaryHeader +
      nonceLength +
      authenticationTagLength;
}
