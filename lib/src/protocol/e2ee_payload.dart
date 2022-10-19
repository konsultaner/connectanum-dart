import '../message/abstract_ppt_options.dart';
import '../serializer/cbor/serializer.dart' as cbor_serializer;
import '../serializer/json/serializer.dart' as json_serializer;
import '../serializer/msgpack/serializer.dart' as msgpack_serializer;
import 'ppt_payload.dart';

// TODO implement End-to-End Encryption
class E2EEPayload extends PPTPayload {

    String? uri;

    E2EEPayload({this.uri, arguments, argumentsKeywords}){
        this.arguments = arguments;
        this.argumentsKeywords = argumentsKeywords;
    }

    /// Packs E2EE Payload and returns 1-item array for WAMP message arguments
    static List<dynamic> packE2EEPayload(List<dynamic>? arguments,
        Map<String, dynamic>? argumentsKeywords,
        PPTOptions options) {
        return [];
    }

    static E2EEPayload unpackE2EEPayload(List<dynamic>? arguments,
        PPTOptions options) {
        return E2EEPayload();
    }

}
