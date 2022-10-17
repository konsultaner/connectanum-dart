import '../message/abstract_ppt_options.dart';
import '../serializer/cbor/serializer.dart' as cbor_serializer;
import '../serializer/json/serializer.dart' as json_serializer;
import '../serializer/msgpack/serializer.dart' as msgpack_serializer;

// TODO implement End-to-End Encryption
class E2EEPayload {

    static List<dynamic> packE2EEPayload(List<dynamic>? arguments,
        Map<String, dynamic>? argumentsKeywords,
        PPTOptions options) {
        return [];
    }

    static List<dynamic> unpackE2EEPayload(List<dynamic>? arguments,
        PPTOptions options) {
        return [];
    }

}
