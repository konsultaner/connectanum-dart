import 'abstract_ppt_options.dart';
import '../message/ppt_payload.dart';

// TODO implement End-to-End Encryption
class E2EEPayload extends PPTPayload {
  String? uri;

  E2EEPayload({this.uri, arguments, argumentsKeywords}) {
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }

  /// Packs E2EE Payload and returns 1-item array for WAMP message arguments
  static List<dynamic> packE2EEPayload(List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords, PPTOptions options) {
    return [];
  }

  static E2EEPayload unpackE2EEPayload(
      List<dynamic>? arguments, PPTOptions options) {
    return E2EEPayload();
  }
}
