import 'dart:typed_data';

import 'abstract_message.dart';

/// CALL,EVENT,RESULT,ERROR,PUBLISH,INVOCATION,YIELD may have a transparent payload
abstract class AbstractMessageWithPayload extends AbstractMessage {
  Uint8List transparentBinaryPayload;
  List<Object> arguments;
  Map<String, Object> argumentsKeywords;

  AbstractMessageWithPayload({this.arguments, this.argumentsKeywords});

  /// Transfers the message payload to another message
  void copyPayloadTo(AbstractMessageWithPayload message) {
    message.arguments = argumentsKeywords != null && arguments == null
        ? []
        : arguments;
    message.argumentsKeywords = argumentsKeywords;
    message.transparentBinaryPayload = transparentBinaryPayload;
  }
}
