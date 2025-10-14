/// Payload PassThru Options are the same across all wamp messages
/// this provides a common checks for them
abstract class PPTOptions {
  // Payload PassThru mode options
  String? pptScheme;
  String? pptSerializer;
  String? pptCipher;
  String? pptKeyId;

  bool verifyPPT() {
    if (pptScheme != null &&
        pptScheme != 'wamp' &&
        pptScheme != 'mqtt' &&
        !pptScheme!.startsWith('x_')) {
      throw ArgumentError.value(
          pptScheme, 'PPTSchemeError', 'ppt scheme provided is invalid');
    }

    if (pptScheme! == 'wamp' &&
        (pptSerializer == null || pptSerializer != 'cbor')) {
      // WAMP E2EE works over cbor or flatbuffers, but we support only cbor
      // So checking only against it
      throw ArgumentError.value(pptSerializer, 'PPTSerializerError',
          'ppt serializer provided is invalid or not supported');
    }

    return true;
  }

  bool verify();
}
