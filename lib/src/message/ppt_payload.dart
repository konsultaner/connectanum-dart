import '../message/abstract_ppt_options.dart';
import '../serializer/abstract_serializer.dart';
import '../serializer/cbor/serializer.dart' as cbor_serializer;
import '../serializer/json/serializer.dart' as json_serializer;
import '../serializer/msgpack/serializer.dart' as msgpack_serializer;

/// Container for payloads transmitted using Payload PassThru (PPT).
class PPTPayload {
  /// Positional arguments contained in the payload.
  List<dynamic>? arguments;
  /// Keyword arguments contained in the payload.
  Map<String, dynamic>? argumentsKeywords;

  /// Create a PPT payload with optional [arguments] and [argumentsKeywords].
  PPTPayload({this.arguments, this.argumentsKeywords});

  /// Serialize this payload as a single item according to the PPT options.
  static List<dynamic> packPPTPayload(List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords, PPTOptions options) {
    if (options.pptSerializer != null && options.pptSerializer != 'native') {
      AbstractSerializer serializer;

      switch (options.pptSerializer) {
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
          arguments: arguments, argumentsKeywords: argumentsKeywords);

      return [serializer.serializePPT(pptPayload)];
    } else {
      return [
        {'args': arguments, 'kwargs': argumentsKeywords}
      ];
    }
  }

  /// Deserialize a PPT payload from WAMP message arguments.
  static PPTPayload unpackPPTPayload(
      List<dynamic>? arguments, PPTOptions details) {
    if (arguments == null) {
      return PPTPayload();
    }

    if (details.pptSerializer != null && details.pptSerializer != 'native') {
      AbstractSerializer serializer;

      switch (details.pptSerializer) {
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
          return PPTPayload();
      }

      return serializer.deserializePPT(arguments[0]) ?? PPTPayload();
    } else {
      return PPTPayload(
          arguments: arguments[0]['args'],
          argumentsKeywords: arguments[0]['kwargs']);
    }
  }
}
