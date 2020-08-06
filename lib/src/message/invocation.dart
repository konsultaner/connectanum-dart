import 'dart:async';
import 'dart:collection';

import 'abstract_message_with_payload.dart';
import 'message_types.dart';
import 'uri_pattern.dart';
import 'error.dart';
import 'yield.dart';

class Invocation extends AbstractMessageWithPayload {
  int requestId;
  int registrationId;
  InvocationDetails details;
  StreamController<AbstractMessageWithPayload> _responseStreamController;

  void respondWith(
      {List<Object> arguments,
      Map<String, Object> argumentsKeywords,
      bool isError = false,
      String errorUri,
      bool progressive = false}) {
    if (isError) {
      assert(progressive == false);
      assert(UriPattern.match(errorUri));
      final error = Error(
          MessageTypes.CODE_INVOCATION, requestId, HashMap(), errorUri,
          arguments: arguments, argumentsKeywords: argumentsKeywords);
      _responseStreamController.add(error);
    } else {
      final yield = Yield(requestId,
          options: YieldOptions(progressive),
          arguments: arguments,
          argumentsKeywords: argumentsKeywords);
      _responseStreamController.add(yield);
    }
    if (!progressive) {
      _responseStreamController.close();
    }
  }

  Invocation(this.requestId, this.registrationId, this.details,
      {List<Object> arguments, Map<String, Object> argumentsKeywords}) {
    id = MessageTypes.CODE_INVOCATION;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }

  bool isProgressive() {
    return details.receive_progress ?? false;
  }

  void onResponse(
      void Function(AbstractMessageWithPayload invocationResultMessage)
          onData) {
    _responseStreamController = StreamController<AbstractMessageWithPayload>();
    _responseStreamController.stream.listen(onData);
  }
}

class InvocationDetails {
  // caller_identification == true
  int caller;

  // pattern_based_registration == true
  String procedure;

  // pattern_based_registration == true
  bool receive_progress;

  InvocationDetails(this.caller, this.procedure, this.receive_progress);
}
