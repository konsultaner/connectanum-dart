import 'abstract_ppt_options.dart';
import '../message/ppt_payload.dart';

// TODO implement End-to-End Encryption
/// Placeholder for end-to-end encrypted payload handling.
class E2EEPayload extends PPTPayload {
  /// Encryption key identifier or URI.
  String? uri;

  /// Create an encrypted payload container.
  E2EEPayload({this.uri, arguments, argumentsKeywords}) {
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }

  /// Packs E2EE Payload and returns a single item array for WAMP message arguments.
  static List<dynamic> packE2EEPayload(List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords, PPTOptions options) {
    return [];
  }

  /// Unpack an encrypted payload into its original form.
  static E2EEPayload unpackE2EEPayload(
      List<dynamic>? arguments, PPTOptions options) {
    return E2EEPayload();
  }
}
