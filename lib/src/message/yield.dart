import 'abstract_ppt_options.dart';
import 'message_types.dart';
import 'abstract_message_with_payload.dart';

class Yield extends AbstractMessageWithPayload {
  int invocationRequestId;
  YieldOptions? options;

  Yield(this.invocationRequestId,
      {this.options,
      List<dynamic>? arguments,
      Map<String, dynamic>? argumentsKeywords}) {
    id = MessageTypes.CODE_YIELD;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }
}

class YieldOptions extends PPTOptions {
  bool progress = false;

  YieldOptions(
      {bool? progress,
      String? ppt_scheme,
      String? ppt_serializer,
      String? ppt_cipher,
      String? ppt_keyid}) {
      this.progress = progress ?? false;
      this.ppt_scheme = ppt_scheme;
      this.ppt_serializer = ppt_serializer;
      this.ppt_cipher = ppt_cipher;
      this.ppt_keyid = ppt_keyid;
  }

  @override
  bool Verify() {
      return VerifyPPT();
  }
}
