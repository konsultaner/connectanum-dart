import 'dart:typed_data';

import 'abstract_message.dart';

/// Base class for messages that carry positional and keyword arguments.
/// CALL, EVENT, RESULT, ERROR, PUBLISH, INVOCATION and YIELD extend this.
abstract class AbstractMessageWithPayload extends AbstractMessage {
  Uint8List? transparentBinaryPayload;
  List<dynamic>? arguments;
  Map<String, dynamic>? argumentsKeywords;

  /// Construct a message with optional [arguments] and [argumentsKeywords].
  AbstractMessageWithPayload({this.arguments, this.argumentsKeywords});

  /// Transfers the message payload to another message
  void copyPayloadTo(AbstractMessageWithPayload message) {
    message.arguments =
        argumentsKeywords != null && arguments == null ? [] : arguments;
    message.argumentsKeywords = argumentsKeywords;
    message.transparentBinaryPayload = transparentBinaryPayload;
  }
}
