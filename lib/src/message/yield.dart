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
    id = MessageTypes.codeYield;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }
}

class YieldOptions extends PPTOptions {
  bool progress = false;

  YieldOptions(
      {bool? progress,
      String? pptScheme,
      String? pptSerializer,
      String? pptCipher,
      String? pptKeyId}) {
    this.progress = progress ?? false;
    this.pptScheme = pptScheme;
    this.pptSerializer = pptSerializer;
    this.pptCipher = pptCipher;
    this.pptKeyId = pptKeyId;
  }

  @override
  bool verify() {
    return verifyPPT();
  }
}
