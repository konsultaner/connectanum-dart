import 'package:logging/logging.dart';

import '../message/abstract_ppt_options.dart';
import '../serializer/abstract_serializer.dart';
import '../serializer/cbor/serializer.dart' as cbor_serializer;
import '../serializer/json/serializer.dart' as json_serializer;
import '../serializer/msgpack/serializer.dart' as msgpack_serializer;

class PPTPayload {

    List<dynamic>? arguments;
    Map<String, dynamic>? argumentsKeywords;

    PPTPayload({this.arguments, this.argumentsKeywords});

    static List<dynamic> packPPTPayload(List<dynamic>? arguments,
        Map<String, dynamic>? argumentsKeywords,
        PPTOptions options) {

        if (options.ppt_serializer != null && options.ppt_serializer != 'native') {
            AbstractSerializer serializer;

            switch (options.ppt_serializer) {
                case 'json':
                    serializer = json_serializer.Serializer();
                    break;
                case 'cbor':
                    serializer = cbor_serializer.Serializer();
                    break;
                case 'msgpack':
                    serializer = msgpack_serializer.Serializer();
                    break;
                default:
                    //TODO Throw error/handle invalid serializer
                    return [];
            }

            var pptPayload = PPTPayload(
                arguments: arguments,
                argumentsKeywords: argumentsKeywords);

            return [serializer.serializePPT(pptPayload)];

        } else {
            return [{
                'args': arguments,
                'kwargs': argumentsKeywords
            }];
        }
    }

    static PPTPayload? unpackPPTPayload(List<dynamic>? arguments,
        PPTOptions details) {

        if (details.ppt_serializer != null && details.ppt_serializer != 'native') {
            AbstractSerializer serializer;

            switch (details.ppt_serializer) {
                case 'json':
                    serializer = json_serializer.Serializer();
                    break;
                case 'cbor':
                    serializer = cbor_serializer.Serializer();
                    break;
                case 'msgpack':
                    serializer = msgpack_serializer.Serializer();
                    break;
                default:
                    //TODO Throw error/handle invalid serializer
                    return null;
            }

            return serializer.deserializePPT(arguments?[0]);

        } else {
            return PPTPayload(
                arguments: arguments?[0]['args'],
                argumentsKeywords: arguments?[0]['kwargs']);
        }
    }

}
