/// Payload PassThru Options are the same across all wamp messages
/// this provides a common checks for them
abstract class PPTOptions {

    // Payload Passthru mode options
    String? ppt_scheme;
    String? ppt_serializer;
    String? ppt_cipher;
    String? ppt_keyid;

    bool VerifyPPT() {
        if (ppt_scheme != null &&
            ppt_scheme != 'wamp' &&
            ppt_scheme != 'mqtt' &&
            !ppt_scheme!.startsWith('x_')) {
            throw ArgumentError.value(ppt_scheme, 'PPTSchemeError', 'ppt scheme provided is invalid');
        }

        if (ppt_scheme! == 'wamp' &&
            (ppt_serializer == null || ppt_serializer != 'cbor' )) {
            // WAMP E2EE works over cbor or flatbuffers, but we support only cbor
            // So checking only against it
            throw ArgumentError.value(ppt_serializer, 'PPTSerializerError', 'ppt serializer provided is invalid or not supported');
        }

        return true;
    }

    bool Verify();
}
