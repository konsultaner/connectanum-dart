import 'dart:typed_data';

import 'package:connectanum_dart/src/message/message_types.dart';

import 'abstract_message.dart';

/**
 * CALL,EVENT,RESULT,ERROR,PUBLISH,INVOCATION,YIELD may have a transparent payload
 */
abstract class AbstractMessageWithPayload extends AbstractMessage {
  String transparentStringPayload;
  Uint8List transparentBinaryPayload;
  List<Object> arguments;
  Map<String, Object> argumentsKeywords;

  AbstractMessageWithPayload({this.arguments, this.argumentsKeywords});

  /**
   * Transfers the message payload to another message
   * @param message An AbstractMessageWithPayload instance
   */
  void copyPayloadTo(AbstractMessageWithPayload message) {
    message.arguments = this.argumentsKeywords != null && this.arguments == null
        ? []
        : this.arguments;
    message.argumentsKeywords = this.argumentsKeywords;
    message.transparentStringPayload = this.transparentStringPayload;
    message.transparentBinaryPayload = this.transparentBinaryPayload;
  }
}
