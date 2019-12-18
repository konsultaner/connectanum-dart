import 'dart:collection';

import 'package:connectanum_dart/src/message/error.dart';
import 'package:connectanum_dart/src/message/message_types.dart';
import 'package:connectanum_dart/src/message/uri_pattern.dart';
import 'package:connectanum_dart/src/message/yield.dart';
import 'package:rxdart/rxdart.dart';

import 'abstract_message_with_payload.dart';

class Invocation extends AbstractMessageWithPayload {
  int requestId;
  int registrationId;
  InvocationDetails details;
  BehaviorSubject<AbstractMessageWithPayload> _responseSubject;

  respondWith (
      {List<Object> arguments,
      Map<String, Object> argumentsKeywords,
      bool isError: false,
      String errorUri,
      bool progressive: false}) {
    if (isError) {
      assert(progressive == false);
      assert(UriPattern.match(errorUri));
      final Error error = new Error(MessageTypes.CODE_INVOCATION, requestId, new HashMap(), errorUri, arguments: arguments, argumentsKeywords: argumentsKeywords);
      _responseSubject.add(error);
    } else {
      final Yield yield = new Yield(this.requestId, new YieldOptions(progressive), arguments: arguments, argumentsKeywords: argumentsKeywords);
      _responseSubject.add(yield);
    }
    if (!progressive) {
      _responseSubject.close();
    }
  }

  Invocation(this.requestId, this.registrationId, this.details,
      {List<Object> arguments, Map<String, Object> argumentsKeywords}) {
    this.id = MessageTypes.CODE_INVOCATION;
    this.arguments = arguments;
    this.argumentsKeywords = argumentsKeywords;
  }

  bool isProgressive() {
    return this.details.receive_progress ?? false;
  }

  void onResponse(void Function(AbstractMessageWithPayload invocationResultMessage) onData) {
    _responseSubject = new BehaviorSubject<AbstractMessageWithPayload>();
    _responseSubject.listen(onData);
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
