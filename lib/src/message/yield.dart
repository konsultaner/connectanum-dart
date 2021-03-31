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

class YieldOptions {
  bool? progress;
  YieldOptions(this.progress);
}
